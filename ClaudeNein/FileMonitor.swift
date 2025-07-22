import Foundation
import Combine

/// Monitors Claude config directories for file changes and provides real-time updates
class FileMonitor: ObservableObject {
    
    // MARK: - Types
    
    /// Represents the state of a monitored file
    struct FileState {
        let url: URL
        let modificationDate: Date
        let size: Int64
        
        static func create(from url: URL) -> FileState? {
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                let modificationDate = attributes[.modificationDate] as? Date ?? Date()
                let size = attributes[.size] as? Int64 ?? 0
                return FileState(url: url, modificationDate: modificationDate, size: size)
            } catch {
                handleFileSystemError(error, path: url.path)
                return nil
            }
        }
        
        private static func handleFileSystemError(_ error: Error, path: String) {
            let nsError = error as NSError
            
            switch nsError.code {
            case NSFileReadNoPermissionError:
                print("🚫 Permission denied: \(path)")
            case NSFileReadNoSuchFileError:
                print("❓ File not found: \(path)")
            case NSFileReadCorruptFileError:
                print("💥 Corrupted file: \(path)")
            default:
                // Check for disk full
                if nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileWriteOutOfSpaceError {
                    print("💾 Disk full - cannot process: \(path)")
                } else if path.hasPrefix("/Volumes/") || path.hasPrefix("//") {
                    print("🌐 Network file system error: \(path)")
                } else {
                    print("⚠️ Failed to get file attributes for \(path): \(error.localizedDescription)")
                }
            }
        }
    }
    
    /// File change notification
    struct FileChangeNotification {
        let changedFiles: [URL]
        let timestamp: Date
    }
    
    /// File monitoring errors
    enum FileMonitorError: Error, LocalizedError {
        case permissionDenied(path: String)
        case fileNotFound(path: String)
        case diskFull
        case corruptedFile(path: String)
        case networkError(path: String)
        case unknownError(underlying: Error)
        
        var errorDescription: String? {
            switch self {
            case .permissionDenied(let path):
                return "Permission denied accessing: \(path)"
            case .fileNotFound(let path):
                return "File not found: \(path)"
            case .diskFull:
                return "Disk is full - cannot process files"
            case .corruptedFile(let path):
                return "File appears corrupted: \(path)"
            case .networkError(let path):
                return "Network file system error for: \(path)"
            case .unknownError(let underlying):
                return "Unknown error: \(underlying.localizedDescription)"
            }
        }
    }
    
    // MARK: - Properties
    
    @Published private(set) var isMonitoring = false
    @Published private(set) var lastUpdateTime = Date()
    
    // Use a single serial queue for all file monitoring operations to ensure thread safety
    private let monitorQueue = DispatchQueue(label: "fileMonitor", qos: .utility)
    
    // File state tracking - access only from monitorQueue
    private var trackedFiles: [URL: FileState] = [:]
    private var monitoredDirectories: [URL] = []
    
    // Debouncing - access only from monitorQueue
    private var debounceTimer: DispatchSourceTimer?
    private var pendingChanges: Set<URL> = []
    private let debounceInterval: TimeInterval = 0.5
    
    // Cache management - access only from monitorQueue
    private var processedEntries: [String: UsageEntry] = [:]
    private var lastFullScan: Date?
    
    // Periodic refresh - access only from monitorQueue
    private var refreshTimer: DispatchSourceTimer?
    private let refreshInterval: TimeInterval = 20.0
    
    // Directory watcher using DispatchSource - access only from monitorQueue
    private var directoryWatchers: [DispatchSourceFileSystemObject] = []
    
    // Publishers
    private let fileChangeSubject = PassthroughSubject<FileChangeNotification, Never>()
    
    /// Publisher that emits when files change
    var fileChanges: AnyPublisher<FileChangeNotification, Never> {
        fileChangeSubject.eraseToAnyPublisher()
    }
    
    // MARK: - Initialization
    
    deinit {
        stopMonitoring()
    }
    
    // MARK: - Public Methods
    
    /// Start monitoring Claude config directories
    func startMonitoring() {
        guard !isMonitoring else { return }
        
        monitorQueue.async { [weak self] in
            self?.setupMonitoring()
        }
    }
    
    /// Stop monitoring file changes
    func stopMonitoring() {
        monitorQueue.async { [weak self] in
            self?.teardownMonitoring()
        }
    }
    
    /// Force a refresh of all monitored files
    func forceRefresh() {
        monitorQueue.async { [weak self] in
            self?.performFullScan()
        }
    }
    
    /// Get all cached usage entries
    func getCachedEntries() -> [UsageEntry] {
        return monitorQueue.sync {
            Array(processedEntries.values)
        }
    }
    
    /// Get entries that have been modified since the last check
    func getModifiedEntries(since date: Date) -> [UsageEntry] {
        return monitorQueue.sync {
            processedEntries.values.filter { $0.timestamp >= date }
        }
    }
    
    /// Clear the cache and force a full rescan
    func clearCache() {
        monitorQueue.async { [weak self] in
            self?.processedEntries.removeAll()
            self?.trackedFiles.removeAll()
            self?.lastFullScan = nil
            self?.performFullScan()
        }
    }
    
    // MARK: - Private Methods
    
    private func setupMonitoring() {
        // Find Claude directories
        monitoredDirectories = JSONLParser.findClaudeConfigDirectories()
        
        guard !monitoredDirectories.isEmpty else {
            print("⚠️ No Claude config directories found for monitoring")
            return
        }
        
        print("📁 Monitoring directories: \(monitoredDirectories.map { $0.path })")
        
        // Set up directory watchers
        setupDirectoryWatchers()
        
        // Perform initial scan
        performFullScan()
        
        // Start periodic refresh timer
        startPeriodicRefresh()
        
        DispatchQueue.main.async { [weak self] in
            self?.isMonitoring = true
        }
    }
    
    private func teardownMonitoring() {
        // Stop directory watchers
        for watcher in directoryWatchers {
            watcher.cancel()
        }
        directoryWatchers.removeAll()
        
        // Stop timers
        refreshTimer?.cancel()
        refreshTimer = nil
        
        debounceTimer?.cancel()
        debounceTimer = nil
        
        DispatchQueue.main.async { [weak self] in
            self?.isMonitoring = false
        }
    }
    
    private func setupDirectoryWatchers() {
        for directory in monitoredDirectories {
            setupWatcher(for: directory)
        }
    }
    
    private func setupWatcher(for directory: URL) {
        let fileDescriptor = open(directory.path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            handleDirectoryOpenError(directory.path)
            return
        }
        
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .extend, .attrib, .rename],
            queue: monitorQueue
        )
        
        source.setEventHandler { [weak self] in
            self?.handleDirectoryChange(at: directory)
        }
        
        source.setCancelHandler {
            close(fileDescriptor)
        }
        
        source.resume()
        directoryWatchers.append(source)
    }
    
    private func handleDirectoryOpenError(_ path: String) {
        let error = String(cString: strerror(errno))
        
        switch errno {
        case EACCES:
            print("🚫 Permission denied accessing directory: \(path)")
            print("   Please ensure ClaudeNein has necessary file system permissions")
        case ENOENT:
            print("❓ Directory not found: \(path)")
        case ENOTDIR:
            print("⚠️ Path is not a directory: \(path)")
        case EMFILE, ENFILE:
            print("💾 Too many open files - system limit reached")
        default:
            print("⚠️ Failed to open directory for monitoring: \(path) (\(error))")
        }
    }
    
    private func handleDirectoryChange(at directory: URL) {
        // Scan the directory for JSONL file changes
        let currentFiles = JSONLParser.discoverJSONLFiles(in: [directory])
        var changedFiles: [URL] = []
        
        for file in currentFiles {
            guard let currentState = FileState.create(from: file) else { continue }
            
            if let previousState = trackedFiles[file] {
                // Check if file has changed
                if previousState.modificationDate != currentState.modificationDate ||
                   previousState.size != currentState.size {
                    changedFiles.append(file)
                }
            } else {
                // New file
                changedFiles.append(file)
            }
        }
        
        if !changedFiles.isEmpty {
            for file in changedFiles {
                pendingChanges.insert(file)
            }
            scheduleDebounce()
        }
    }
    
    private func scheduleDebounce() {
        debounceTimer?.cancel()
        
        let timer = DispatchSource.makeTimerSource(queue: monitorQueue)
        timer.schedule(deadline: .now() + debounceInterval)
        timer.setEventHandler { [weak self] in
            self?.processDebounceQueue()
        }
        timer.resume()
        
        debounceTimer = timer
    }
    
    private func processDebounceQueue() {
        // This is already running on monitorQueue due to the timer being scheduled on it
        let changedFiles = Array(pendingChanges)
        pendingChanges.removeAll()
        
        if !changedFiles.isEmpty {
            processFileChanges(changedFiles)
            
            let notification = FileChangeNotification(
                changedFiles: changedFiles,
                timestamp: Date()
            )
            
            DispatchQueue.main.async { [weak self] in
                self?.fileChangeSubject.send(notification)
                self?.lastUpdateTime = Date()
            }
        }
    }
    
    private func processFileChanges(_ files: [URL]) {
        let parser = JSONLParser()
        var hasChanges = false
        
        for file in files {
            // Check if file still exists
            guard FileManager.default.fileExists(atPath: file.path) else {
                // File was deleted, remove from tracking
                trackedFiles.removeValue(forKey: file)
                // Remove entries from cache that came from this file
                removeEntriesFromFile(file)
                hasChanges = true
                continue
            }
            
            // Get current file state
            guard let currentState = FileState.create(from: file) else {
                continue
            }
            
            // Check if file has actually changed
            if let previousState = trackedFiles[file],
               previousState.modificationDate == currentState.modificationDate &&
               previousState.size == currentState.size {
                continue // No actual changes
            }
            
            // Update tracked state
            trackedFiles[file] = currentState
            
            // Parse new entries from file
            do {
                let entries = try parser.parseJSONLFile(at: file)
                updateCacheWithEntries(entries, from: file)
                hasChanges = true
                print("📊 Updated \(entries.count) entries from \(file.lastPathComponent)")
            } catch {
                print("⚠️ Failed to parse updated file \(file): \(error.localizedDescription)")
            }
        }
        
        if hasChanges {
            print("🔄 Processed changes in \(files.count) files")
        }
    }
    
    private func performFullScan() {
        print("🔍 Performing full scan of JSONL files...")
        
        let allFiles = JSONLParser.discoverJSONLFiles(in: monitoredDirectories)
        let parser = JSONLParser()
        var totalEntries = 0
        
        // Update file tracking
        trackedFiles.removeAll()
        processedEntries.removeAll()
        
        for file in allFiles {
            guard let fileState = FileState.create(from: file) else {
                continue
            }
            
            trackedFiles[file] = fileState
            
            do {
                let entries = try parser.parseJSONLFile(at: file)
                updateCacheWithEntries(entries, from: file)
                totalEntries += entries.count
            } catch {
                print("⚠️ Failed to parse \(file): \(error.localizedDescription)")
            }
        }
        
        lastFullScan = Date()
        print("✅ Full scan complete: \(totalEntries) entries from \(allFiles.count) files")
        
        // Notify about the full refresh
        let notification = FileChangeNotification(
            changedFiles: allFiles,
            timestamp: Date()
        )
        
        DispatchQueue.main.async { [weak self] in
            self?.fileChangeSubject.send(notification)
            self?.lastUpdateTime = Date()
        }
    }
    
    private func updateCacheWithEntries(_ entries: [UsageEntry], from file: URL) {
        // Remove existing entries from this file first
        removeEntriesFromFile(file)
        
        // Add new entries with file source tracking
        for entry in entries {
            let cacheKey = "\(file.path):\(entry.id)"
            processedEntries[cacheKey] = entry
        }
    }
    
    private func removeEntriesFromFile(_ file: URL) {
        let filePrefix = "\(file.path):"
        let keysToRemove = processedEntries.keys.filter { $0.hasPrefix(filePrefix) }
        for key in keysToRemove {
            processedEntries.removeValue(forKey: key)
        }
    }
    
    private func startPeriodicRefresh() {
        let timer = DispatchSource.makeTimerSource(queue: monitorQueue)
        timer.schedule(deadline: .now() + refreshInterval, repeating: refreshInterval)
        timer.setEventHandler { [weak self] in
            self?.checkForMissedChanges()
        }
        timer.resume()
        
        refreshTimer = timer
    }
    
    private func checkForMissedChanges() {
        print("🔄 Periodic refresh check...")
        
        var changedFiles: [URL] = []
        
        // Check all tracked files for changes
        for (file, previousState) in trackedFiles {
            guard let currentState = FileState.create(from: file) else {
                // File no longer exists
                changedFiles.append(file)
                continue
            }
            
            if previousState.modificationDate != currentState.modificationDate ||
               previousState.size != currentState.size {
                changedFiles.append(file)
            }
        }
        
        // Check for new files
        let discoveredFiles = JSONLParser.discoverJSONLFiles(in: monitoredDirectories)
        let newFiles = discoveredFiles.filter { trackedFiles[$0] == nil }
        changedFiles.append(contentsOf: newFiles)
        
        if !changedFiles.isEmpty {
            print("📁 Found \(changedFiles.count) changed files during periodic check")
            processFileChanges(changedFiles)
            
            let notification = FileChangeNotification(
                changedFiles: changedFiles,
                timestamp: Date()
            )
            
            DispatchQueue.main.async { [weak self] in
                self?.fileChangeSubject.send(notification)
                self?.lastUpdateTime = Date()
            }
        }
    }
}

// MARK: - Extensions

extension FileMonitor.FileState: Equatable {
    static func == (lhs: FileMonitor.FileState, rhs: FileMonitor.FileState) -> Bool {
        return lhs.url == rhs.url &&
               lhs.modificationDate == rhs.modificationDate &&
               lhs.size == rhs.size
    }
}