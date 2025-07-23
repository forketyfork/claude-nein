import Foundation
import Combine
import OSLog

/// Monitors Claude config directories for file changes and provides real-time updates
class FileMonitor: ObservableObject {
    
    // MARK: - Properties
    
    @Published private(set) var isMonitoring = false
    
    /// Publisher that emits the URLs of files that have changed
    var fileChanges: AnyPublisher<[URL], Never> {
        fileChangeSubject.eraseToAnyPublisher()
    }
    
    private let fileChangeSubject = PassthroughSubject<[URL], Never>()
    
    private let accessManager: HomeDirectoryAccessManager
    private let monitorQueue = DispatchQueue(label: "com.forketyfork.ClaudeNein.fileMonitor", qos: .background)
    
    private var directoryWatchers: [DispatchSourceFileSystemObject] = []
    private var monitoredDirectories: [URL] = []
    
    // Debouncing to group rapid file changes
    private var debounceTimer: Timer?
    private var pendingChanges = Set<URL>()
    
    // MARK: - Initialization
    
    init(accessManager: HomeDirectoryAccessManager) {
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
        
        isMonitoring = true
        
        monitorQueue.async {
            self.setupDirectoryMonitoring()
        }
    }
    
    /// Stops the file monitoring service.
    func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false
        
        monitorQueue.async {
            self.teardownDirectoryMonitoring()
        }
    }
    
    // MARK: - Private Setup and Teardown
    
    private func setupDirectoryMonitoring() {
        guard let claudeDir = accessManager.claudeDirectoryURL else {
            Logger.fileMonitor.error("Failed to get Claude directory URL.")
            return
        }
        
        monitoredDirectories = [claudeDir]
        Logger.fileMonitor.info("Starting to monitor directory: \(claudeDir.path)")
        
        for directoryURL in monitoredDirectories {
            let fileDescriptor = open(directoryURL.path, O_EVTONLY)
            guard fileDescriptor != -1 else {
                Logger.fileMonitor.error("Failed to open file descriptor for \(directoryURL.path). Error: \(String(cString: strerror(errno)))")
                continue
            }
            
            let watcher = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fileDescriptor,
                eventMask: .write,
                queue: monitorQueue
            )
            
            watcher.setEventHandler { [weak self] in
                self?.handleFileSystemEvent(in: directoryURL)
            }
            
            watcher.setCancelHandler {
                close(fileDescriptor)
            }
            
            watcher.resume()
            directoryWatchers.append(watcher)
        }
    }
    
    private func teardownDirectoryMonitoring() {
        Logger.fileMonitor.info("Stopping directory monitoring.")
        directoryWatchers.forEach { $0.cancel() }
        directoryWatchers.removeAll()
        debounceTimer?.invalidate()
        debounceTimer = nil
    }
    
    // MARK: - Event Handling
    
    private func handleFileSystemEvent(in directoryURL: URL) {
        // The event gives us the directory, so we need to find which file(s) changed.
        // A simple approach is to just scan for all .jsonl files and add them to the pending set.
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: directoryURL, includingPropertiesForKeys: nil) else {
            return
        }
        
        let jsonlFiles = enumerator.allObjects
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "jsonl" }
        
        for url in jsonlFiles {
            pendingChanges.insert(url)
        }
        
        // Debounce the changes to avoid processing too frequently
        DispatchQueue.main.async {
            self.debounceTimer?.invalidate()
            self.debounceTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
                self?.processPendingChanges()
            }
        }
    }
    
    private func processPendingChanges() {
        monitorQueue.async { [weak self] in
            guard let self = self, !self.pendingChanges.isEmpty else { return }
            
            let urlsToProcess = Array(self.pendingChanges)
            self.pendingChanges.removeAll()
            
            Logger.fileMonitor.info("Processing changes for \(urlsToProcess.count) file(s).")
            self.fileChangeSubject.send(urlsToProcess)
        }
    }
}
