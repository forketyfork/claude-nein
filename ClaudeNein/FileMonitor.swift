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
        guard let projectsDir = accessManager.claudeProjectsDirectoryURL else {
            Logger.fileMonitor.error("Failed to get Claude projects directory URL.")
            return
        }
        
        // Verify the projects directory exists
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: projectsDir.path) else {
            Logger.fileMonitor.warning("Claude projects directory does not exist: \(projectsDir.path)")
            return
        }
        
        // Start with the main projects directory
        var directoriesToMonitor = [projectsDir]
        
        // Add all existing project subdirectories for monitoring
        if let enumerator = fileManager.enumerator(at: projectsDir, includingPropertiesForKeys: [.isDirectoryKey]) {
            for case let url as URL in enumerator {
                do {
                    let resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey])
                    if resourceValues.isDirectory == true {
                        directoriesToMonitor.append(url)
                    }
                } catch {
                    Logger.fileMonitor.warning("Failed to check if \(url.path) is directory: \(error)")
                }
            }
        }
        
        monitoredDirectories = directoriesToMonitor
        Logger.fileMonitor.info("📊 Starting to monitor \(directoriesToMonitor.count) directories under: \(projectsDir.path)")
        
        for (index, directoryURL) in monitoredDirectories.enumerated() {
            Logger.fileMonitor.debug("  \(index + 1). \(directoryURL.lastPathComponent)")
            setupWatcher(for: directoryURL)
        }
    }
    
    private func setupWatcher(for directoryURL: URL) {
        let fileDescriptor = open(directoryURL.path, O_EVTONLY)
        guard fileDescriptor != -1 else {
            Logger.fileMonitor.error("Failed to open file descriptor for \(directoryURL.path). Error: \(String(cString: strerror(errno)))")
            return
        }
        
        let watcher = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .delete],
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
    
    private func teardownDirectoryMonitoring() {
        Logger.fileMonitor.info("Stopping directory monitoring.")
        directoryWatchers.forEach { $0.cancel() }
        directoryWatchers.removeAll()
        debounceTimer?.invalidate()
        debounceTimer = nil
    }
    
    // MARK: - Event Handling
    
    private func handleFileSystemEvent(in directoryURL: URL) {
        Logger.fileMonitor.info("🔍 File system event detected in: \(directoryURL.path)")
        
        let fileManager = FileManager.default
        
        do {
            let contents = try fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey])
            
            // Check for JSONL files in this directory
            let jsonlFiles = contents.filter { 
                $0.pathExtension == "jsonl" && $0.hasDirectoryPath == false
            }
            
            // Check if this is the main projects directory - if so, always check for new subdirectories
            let isMainProjectsDir = (directoryURL == accessManager.claudeProjectsDirectoryURL)
            
            if !jsonlFiles.isEmpty {
                Logger.fileMonitor.info("📁 Found \(jsonlFiles.count) JSONL files in \(directoryURL.path)")
                for url in jsonlFiles {
                    pendingChanges.insert(url)
                    Logger.fileMonitor.debug("  ➕ Added to pending: \(url.lastPathComponent)")
                }
            }
            
            // Always check for new directories if this is the main projects directory
            // or if we found JSONL files (indicating activity)
            if isMainProjectsDir || !jsonlFiles.isEmpty {
                checkForNewDirectories()
            }
            
            // Trigger processing if we found files or if this is the main directory (new subdirs might have files)
            if !jsonlFiles.isEmpty || isMainProjectsDir {
                // Debounce the changes to avoid processing too frequently
                DispatchQueue.main.async {
                    self.debounceTimer?.invalidate()
                    self.debounceTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
                        self?.processPendingChanges()
                    }
                }
            }
            
        } catch {
            Logger.fileMonitor.error("Failed to read directory contents for \(directoryURL.path): \(error)")
        }
    }
    
    /// Check for new project directories and add them to monitoring
    private func checkForNewDirectories() {
        guard let projectsDir = accessManager.claudeProjectsDirectoryURL else { return }
        
        let fileManager = FileManager.default
        do {
            let contents = try fileManager.contentsOfDirectory(at: projectsDir, includingPropertiesForKeys: [.isDirectoryKey])
            
            let newDirectories = contents.filter { url in
                url.hasDirectoryPath && !monitoredDirectories.contains(url)
            }
            
            if !newDirectories.isEmpty {
                Logger.fileMonitor.info("Found \(newDirectories.count) new project directories to monitor")
                for newDir in newDirectories {
                    monitoredDirectories.append(newDir)
                    setupWatcher(for: newDir)
                    
                    // Immediately check for existing JSONL files in the new directory
                    scanDirectoryForJSONLFiles(newDir)
                }
            }
            
        } catch {
            Logger.fileMonitor.error("Failed to check for new directories: \(error)")
        }
    }
    
    /// Scan a directory for JSONL files and add them to pending changes
    private func scanDirectoryForJSONLFiles(_ directoryURL: URL) {
        let fileManager = FileManager.default
        do {
            let contents = try fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: [.isRegularFileKey])
            
            let jsonlFiles = contents.filter { 
                $0.pathExtension == "jsonl" && $0.hasDirectoryPath == false
            }
            
            if !jsonlFiles.isEmpty {
                Logger.fileMonitor.info("📂 Found \(jsonlFiles.count) existing JSONL files in new directory: \(directoryURL.path)")
                for url in jsonlFiles {
                    pendingChanges.insert(url)
                    Logger.fileMonitor.debug("  ➕ Added existing file: \(url.lastPathComponent)")
                }
            }
            
        } catch {
            Logger.fileMonitor.warning("Failed to scan new directory for JSONL files: \(directoryURL.path) - \(error)")
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
