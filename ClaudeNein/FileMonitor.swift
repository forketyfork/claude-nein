import Foundation
import Combine
import OSLog
import CoreServices

/// Monitors Claude config directories for file changes and provides real-time updates
class FileMonitor: ObservableObject {
    
    // MARK: - Properties
    
    @Published private(set) var isMonitoring = false
    
    /// Publisher that emits the URLs of files that have changed
    var fileChanges: AnyPublisher<[URL], Never> {
        fileChangeSubject.eraseToAnyPublisher()
    }
    
    private let fileChangeSubject = PassthroughSubject<[URL], Never>()
    
    private let accessManager: DirectoryAccessManager
    private let monitorQueue = DispatchQueue(label: "com.forketyfork.ClaudeNein.fileMonitor", qos: .background)
    
    // FSEvents stream for recursive directory monitoring
    private var eventStream: FSEventStreamRef?
    
    // Debouncing to group rapid file changes
    private var debounceTimer: Timer?
    private var pendingChanges = Set<URL>()
    
    // MARK: - Initialization
    
    init(accessManager: DirectoryAccessManager) {
        self.accessManager = accessManager
    }
    
    deinit {
        stopMonitoring()
    }
    
    // MARK: - Public Methods
    
    /// Starts monitoring the Claude directory for `.jsonl` file changes.
    func startMonitoring() async {
        guard !isMonitoring else {
            Logger.fileMonitor.info("File monitoring is already active.")
            return
        }
        
        guard accessManager.hasValidAccess else {
            Logger.fileMonitor.warning("Cannot start monitoring without directory access.")
            return
        }
        
        await MainActor.run {
            self.isMonitoring = true
        }
        
        monitorQueue.async { [weak self] in
            self?.setupFSEventsMonitoring()
        }
    }
    
    /// Stops the file monitoring service.
    func stopMonitoring() {
        guard isMonitoring else { return }
        
        Task { @MainActor in
            self.isMonitoring = false
        }
        
        monitorQueue.async { [weak self] in
            self?.teardownFSEventsMonitoring()
        }
    }
    
    // MARK: - Private Setup and Teardown
    
    private func setupFSEventsMonitoring() {
        guard let claudeDir = accessManager.claudeDirectoryURL else {
            Logger.fileMonitor.error("Failed to get Claude directory URL.")
            return
        }
        
        // Verify the Claude directory exists
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: claudeDir.path) else {
            Logger.fileMonitor.warning("Claude directory does not exist: \(claudeDir.path)")
            return
        }
        
        Logger.fileMonitor.info("🔍 Starting FSEvents monitoring for: \(claudeDir.path)")
        
        // FSEvents callback that processes file system events
        let callback: FSEventStreamCallback = { _, clientCallBackInfo, numEvents, eventPaths, eventFlags, eventIds in
            guard let clientCallBackInfo = clientCallBackInfo else { return }
            let monitor = Unmanaged<FileMonitor>.fromOpaque(clientCallBackInfo).takeUnretainedValue()
            guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else { return }
            
            var changedFiles: [URL] = []
            
            for i in 0..<numEvents {
                let path = paths[i]
                let flags = eventFlags[i]
                let url = URL(fileURLWithPath: path)
                
                Logger.fileMonitor.debug("FSEvent: \(path) (flags: \(flags))")
                
                // Check if this is a .jsonl file
                if url.pathExtension == "jsonl" {
                    // Verify the file exists (it might have been deleted)
                    if FileManager.default.fileExists(atPath: path) {
                        changedFiles.append(url)
                        Logger.fileMonitor.debug("  ➕ Added JSONL file: \(url.lastPathComponent)")
                    } else {
                        Logger.fileMonitor.debug("  ➖ JSONL file was deleted: \(url.lastPathComponent)")
                    }
                }
                // Check if this is a directory event that might contain new .jsonl files
                else if (flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsDir)) != 0 {
                    Logger.fileMonitor.debug("  📁 Directory event, scanning for JSONL files")
                    let jsonlFiles = monitor.scanDirectoryForJSONLFiles(url)
                    changedFiles.append(contentsOf: jsonlFiles)
                }
            }
            
            if !changedFiles.isEmpty {
                monitor.handleDetectedChanges(changedFiles)
            }
        }
        
        // Create FSEventStream context with self as clientCallBackInfo
        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()
        
        // Create the FSEventStream
        eventStream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            [claudeDir.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0, // 1 second latency for debouncing
            FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagFileEvents |
                kFSEventStreamCreateFlagWatchRoot |
                kFSEventStreamCreateFlagUseCFTypes
            )
        )
        
        guard let eventStream = eventStream else {
            Logger.fileMonitor.error("❌ Failed to create FSEventStream")
            return
        }
        
        // Schedule the stream on the monitor queue's run loop
        FSEventStreamSetDispatchQueue(eventStream, monitorQueue)
        
        // Start the stream
        let started = FSEventStreamStart(eventStream)
        if started {
            Logger.fileMonitor.info("✅ FSEvents monitoring started successfully")
        } else {
            Logger.fileMonitor.error("❌ Failed to start FSEventStream")
            FSEventStreamRelease(eventStream)
            self.eventStream = nil
        }
    }
    
    private func teardownFSEventsMonitoring() {
        guard let eventStream = eventStream else { return }
        
        Logger.fileMonitor.info("🛑 Stopping FSEvents monitoring")
        
        FSEventStreamStop(eventStream)
        FSEventStreamInvalidate(eventStream)
        FSEventStreamRelease(eventStream)
        self.eventStream = nil
        
        // Cancel any pending debounce timer
        DispatchQueue.main.async {
            self.debounceTimer?.invalidate()
            self.debounceTimer = nil
        }
        
        Logger.fileMonitor.info("✅ FSEvents monitoring stopped")
    }
    
    // MARK: - Event Handling
    
    private func handleDetectedChanges(_ changedFiles: [URL]) {
        monitorQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Add to pending changes
            for url in changedFiles {
                self.pendingChanges.insert(url)
            }
            
            Logger.fileMonitor.info("📝 Added \(changedFiles.count) file(s) to pending changes")
            
            // Debounce the processing to group rapid changes
            DispatchQueue.main.async {
                self.debounceTimer?.invalidate()
                self.debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                    self?.processPendingChanges()
                }
            }
        }
    }
    
    /// Scan a directory for JSONL files and return their URLs
    private func scanDirectoryForJSONLFiles(_ directoryURL: URL) -> [URL] {
        let fileManager = FileManager.default
        
        do {
            let contents = try fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            
            let jsonlFiles = contents.filter { url in
                url.pathExtension == "jsonl" && !url.hasDirectoryPath
            }
            
            if !jsonlFiles.isEmpty {
                Logger.fileMonitor.info("📂 Found \(jsonlFiles.count) JSONL files in: \(directoryURL.path)")
            }
            
            return jsonlFiles
            
        } catch {
            Logger.fileMonitor.warning("Failed to scan directory for JSONL files: \(directoryURL.path) - \(error)")
            return []
        }
    }
    
    private func processPendingChanges() {
        monitorQueue.async { [weak self] in
            guard let self = self, !self.pendingChanges.isEmpty else {
                Logger.fileMonitor.debug("No pending changes to process")
                return
            }
            
            let urlsToProcess = Array(self.pendingChanges)
            self.pendingChanges.removeAll()
            
            Logger.fileMonitor.info("🚀 Processing changes for \(urlsToProcess.count) file(s):")
            for url in urlsToProcess {
                Logger.fileMonitor.info("  📄 \(url.lastPathComponent)")
            }
            
            self.fileChangeSubject.send(urlsToProcess)
        }
    }
}