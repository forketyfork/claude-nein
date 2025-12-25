import Foundation
import Combine
import OSLog
import CoreServices
import UniformTypeIdentifiers

/// Monitors Claude config directories for file changes and provides real-time updates
///
/// This class uses Swift's modern concurrency system with proper Sendable conformance
/// and enhanced file monitoring capabilities available in macOS 26.
@MainActor
final class FileMonitor: ObservableObject, Sendable {
    
    // MARK: - Properties
    
    @Published private(set) var isMonitoring = false
    
    /// Publisher that emits the URLs of files that have changed
    /// Using AsyncPublisher for better integration with Swift Concurrency
    var fileChanges: AsyncPublisher<AnyPublisher<[URL], Never>> {
        fileChangeSubject.eraseToAnyPublisher().values
    }
    
    /// Traditional publisher for backward compatibility
    var fileChangesPublisher: AnyPublisher<[URL], Never> {
        fileChangeSubject.eraseToAnyPublisher()
    }
    
    private let fileChangeSubject = PassthroughSubject<[URL], Never>()
    
    private let accessManager: DirectoryAccessManager
    
    // Enhanced FSEvents stream for recursive directory monitoring
    private var eventStream: FSEventStreamRef?
    
    // Modern debouncing using Task and async/await
    private var debounceTask: Task<Void, Never>?
    private var pendingChanges = Set<URL>()
    
    // File type checking using UniformTypeIdentifiers
    private let jsonlUTType = UTType(filenameExtension: "jsonl") ?? .json
    
    // MARK: - Initialization
    
    init(accessManager: DirectoryAccessManager) {
        self.accessManager = accessManager
    }
    
    deinit {
        // Use modern Task-based cleanup for async operations
        Task { [weak self] in
            await self?.stopMonitoring()
        }
    }
    
    // MARK: - Public Methods
    
    /// Starts monitoring the Claude directory for `.jsonl` file changes using modern async APIs.
    func startMonitoring() async {
        guard accessManager.hasValidAccess else {
            Logger.fileMonitor.warning("Cannot start monitoring without directory access.")
            return
        }
        
        await setupFSEventsMonitoring()
    }
    
    /// Stops the file monitoring service using modern async cleanup.
    func stopMonitoring() async {
        guard isMonitoring else { return }
        
        isMonitoring = false
        await teardownFSEventsMonitoring()
    }
    
    // MARK: - Private Setup and Teardown
    
    private func setupFSEventsMonitoring() async {
        guard !isMonitoring else {
            Logger.fileMonitor.info("File monitoring is already active.")
            return
        }
        
        let directories = accessManager.claudeDirectories
        guard !directories.isEmpty else {
            Logger.fileMonitor.error("Failed to get Claude directories")
            return
        }

        let fileManager = FileManager.default
        var existingPaths: [String] = []
        
        // Verify directories exist using modern file management APIs
        for dir in directories {
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: dir.path, isDirectory: &isDirectory) && isDirectory.boolValue {
                existingPaths.append(dir.path)
            } else {
                Logger.fileMonitor.warning("Claude directory does not exist: \(dir.path)")
            }
        }

        guard !existingPaths.isEmpty else { return }

        Logger.fileMonitor.info("🔍 Starting FSEvents monitoring for: \(existingPaths.joined(separator: ", "))")
        
        // Enhanced FSEvents callback with better error handling and modern Swift patterns
        let callback: FSEventStreamCallback = { _, clientCallBackInfo, numEvents, eventPaths, eventFlags, eventIds in
            guard let clientCallBackInfo = clientCallBackInfo else { return }
            let monitor = Unmanaged<FileMonitor>.fromOpaque(clientCallBackInfo).takeUnretainedValue()
            guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else { return }

            // Copy FSEvent flags before launching async task since pointers are only valid during callback
            let flagsCopy = Array(UnsafeBufferPointer(start: eventFlags, count: numEvents))

            Task { @MainActor in
                await monitor.processFileSystemEvents(paths: paths, flags: flagsCopy)
            }
        }
        
        // Create FSEventStream context with enhanced error handling
        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()
        
        // Create the FSEventStream with enhanced flags for macOS 26
        eventStream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            existingPaths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5, // Reduced latency for better responsiveness
            FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagFileEvents |
                kFSEventStreamCreateFlagWatchRoot |
                kFSEventStreamCreateFlagUseCFTypes |
                kFSEventStreamCreateFlagMarkSelf // Enhanced flag available in macOS 26
            )
        )
        
        guard let eventStream = eventStream else {
            Logger.fileMonitor.error("❌ Failed to create FSEventStream")
            return
        }
        
        // Use modern dispatch queue management
        FSEventStreamSetDispatchQueue(eventStream, DispatchQueue.global(qos: .background))
        
        // Start the stream with enhanced error checking
        let started = FSEventStreamStart(eventStream)
        if started {
            isMonitoring = true
            Logger.fileMonitor.info("✅ FSEvents monitoring started successfully")
        } else {
            Logger.fileMonitor.error("❌ Failed to start FSEventStream")
            FSEventStreamRelease(eventStream)
            self.eventStream = nil
        }
    }
    
    private func teardownFSEventsMonitoring() async {
        guard let eventStream = eventStream else { return }
        
        Logger.fileMonitor.info("🛑 Stopping FSEvents monitoring")
        
        FSEventStreamStop(eventStream)
        FSEventStreamInvalidate(eventStream)
        FSEventStreamRelease(eventStream)
        self.eventStream = nil
        
        // Cancel any pending debounce task using modern Task cancellation
        debounceTask?.cancel()
        debounceTask = nil
        
        Logger.fileMonitor.info("✅ FSEvents monitoring stopped")
    }
    
    // MARK: - Event Handling
    
    /// Modern async event processing using structured concurrency
    private func processFileSystemEvents(paths: [String], flags: [FSEventStreamEventFlags]) async {
        var changedFiles: [URL] = []

        for i in 0..<flags.count {
            let path = paths[i]
            let eventFlags = flags[i]
            let url = URL(fileURLWithPath: path)
            
            Logger.fileMonitor.debug("FSEvent: \(path) (flags: \(eventFlags))")
            
            // Enhanced file type checking using UniformTypeIdentifiers
            if await isJSONLFile(url) {
                // Verify the file exists using modern async file operations
                if await fileExists(at: url) {
                    changedFiles.append(url)
                    Logger.fileMonitor.debug("  ➕ Added JSONL file: \(url.lastPathComponent)")
                } else {
                    Logger.fileMonitor.debug("  ➖ JSONL file was deleted: \(url.lastPathComponent)")
                }
            }
            // Check if this is a directory event that might contain new .jsonl files
            else if (eventFlags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsDir)) != 0 {
                Logger.fileMonitor.debug("  📁 Directory event, scanning for JSONL files")
                let jsonlFiles = await scanDirectoryForJSONLFiles(url)
                changedFiles.append(contentsOf: jsonlFiles)
            }
        }
        
        if !changedFiles.isEmpty {
            await handleDetectedChanges(changedFiles)
        }
    }
    
    /// Enhanced file type detection using UniformTypeIdentifiers
    private func isJSONLFile(_ url: URL) async -> Bool {
        // Check file extension first (fastest)
        if url.pathExtension.lowercased() == "jsonl" {
            return true
        }
        
        // Fallback to UTType checking for more robust detection
        do {
            let resourceValues = try url.resourceValues(forKeys: [.contentTypeKey])
            if let contentType = resourceValues.contentType {
                return contentType.conforms(to: jsonlUTType) || contentType.conforms(to: .json)
            }
        } catch {
            Logger.fileMonitor.debug("Could not determine content type for \(url.path): \(error)")
        }
        
        return false
    }
    
    /// Async file existence check
    private func fileExists(at url: URL) async -> Bool {
        return await withCheckedContinuation { continuation in
            Task {
                let exists = FileManager.default.fileExists(atPath: url.path)
                continuation.resume(returning: exists)
            }
        }
    }
    
    /// Modern debouncing using async/await and Task cancellation
    private func handleDetectedChanges(_ changedFiles: [URL]) async {
        // Add to pending changes
        for url in changedFiles {
            pendingChanges.insert(url)
        }
        
        Logger.fileMonitor.info("📝 Added \(changedFiles.count) file(s) to pending changes")
        
        // Cancel existing debounce task
        debounceTask?.cancel()
        
        // Create new debounce task with modern Swift concurrency
        debounceTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(500)) // Modern sleep API
                if !Task.isCancelled {
                    await processPendingChanges()
                }
            } catch {
                // Task was cancelled, which is expected behavior
                Logger.fileMonitor.debug("Debounce task cancelled")
            }
        }
    }
    
    /// Scan a directory for JSONL files using modern async APIs and return their URLs
    private func scanDirectoryForJSONLFiles(_ directoryURL: URL) async -> [URL] {
        return await withCheckedContinuation { continuation in
            Task {
                let fileManager = FileManager.default
                
                do {
                    let contents = try fileManager.contentsOfDirectory(
                        at: directoryURL,
                        includingPropertiesForKeys: [.isRegularFileKey, .contentTypeKey],
                        options: [.skipsHiddenFiles]
                    )
                    
                    let jsonlFiles = contents.filter { url in
                        !url.hasDirectoryPath && url.pathExtension.lowercased() == "jsonl"
                    }
                    
                    if !jsonlFiles.isEmpty {
                        Logger.fileMonitor.info("📂 Found \(jsonlFiles.count) JSONL files in: \(directoryURL.path)")
                    }
                    
                    continuation.resume(returning: jsonlFiles)
                    
                } catch {
                    Logger.fileMonitor.warning("Failed to scan directory for JSONL files: \(directoryURL.path) - \(error)")
                    continuation.resume(returning: [])
                }
            }
        }
    }
    
    private func processPendingChanges() async {
        guard !pendingChanges.isEmpty else {
            Logger.fileMonitor.debug("No pending changes to process")
            return
        }
        
        let urlsToProcess = Array(pendingChanges)
        pendingChanges.removeAll()
        
        Logger.fileMonitor.info("🚀 Processing changes for \(urlsToProcess.count) file(s):")
        for url in urlsToProcess {
            Logger.fileMonitor.info("  📄 \(url.lastPathComponent)")
        }
        
        fileChangeSubject.send(urlsToProcess)
    }
}
