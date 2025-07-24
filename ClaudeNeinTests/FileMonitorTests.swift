import XCTest
import Combine
@testable import ClaudeNein

final class FileMonitorTests: XCTestCase {
    
    var mockAccessManager: MockDirectoryAccessManager!
    var fileMonitor: FileMonitor!
    var cancellables: Set<AnyCancellable>!
    
    // MARK: - Async Condition Waiting Utility
    
    /// Waits for a condition to become true by polling every 100ms
    /// - Parameters:
    ///   - condition: The condition to check
    ///   - timeout: Maximum time to wait in seconds (default: 5.0)
    ///   - pollInterval: How often to check the condition in seconds (default: 0.1)
    /// - Throws: XCTestError if timeout is reached
    func waitForCondition(
        _ condition: @escaping () async -> Bool,
        timeout: TimeInterval = 5.0,
        pollInterval: TimeInterval = 0.1
    ) async throws {
        let startTime = Date()
        
        while Date().timeIntervalSince(startTime) < timeout {
            if await condition() {
                return
            }
            
            try await Task.sleep(nanoseconds: UInt64(pollInterval * 100_000_000))
        }
        
        throw NSError(
            domain: "TestTimeout",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Condition not met within \(timeout) seconds"]
        )
    }
    
    override func setUp() {
        super.setUp()
        
        // Create mock access manager with fresh temporary directory
        mockAccessManager = MockDirectoryAccessManager()
        
        // Create file monitor with mock
        fileMonitor = FileMonitor(accessManager: mockAccessManager)
        
        cancellables = Set<AnyCancellable>()
    }
    
    override func tearDown() {
        cancellables.forEach { $0.cancel() }
        cancellables = nil
        
        // Stop monitoring
        fileMonitor?.stopMonitoring()
        fileMonitor = nil
        
        // Clean up temporary directory
        mockAccessManager?.cleanupTestDirectory()
        mockAccessManager = nil
        
        super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testFileMonitorInitialization() {
        XCTAssertNotNil(fileMonitor)
        XCTAssertFalse(fileMonitor.isMonitoring)
    }
    
    func testFileMonitorPublisherSetup() {
        XCTAssertNotNil(fileMonitor.fileChanges)
    }
    
    // MARK: - Access Management Tests
    
    func testFileMonitorWithoutAccess() async {
        // Revoke access
        mockAccessManager.revokeAccess()
        
        // Try to start monitoring
        await fileMonitor.startMonitoring()
        
        // Should not start monitoring without access
        // TODO proper waiting
        XCTAssertFalse(fileMonitor.isMonitoring)
    }
    
    func testFileMonitorWithAccess() async throws {
        // Ensure access is granted
        let accessGranted = await mockAccessManager.requestHomeDirectoryAccess()
        XCTAssertTrue(accessGranted)
        
        // Start monitoring
        await fileMonitor.startMonitoring()
        
        // Should start monitoring with access
        try await waitForCondition {
            return self.fileMonitor.isMonitoring
        }
    }
    
    // MARK: - File Change Detection Tests
    
    func testFileAdditionDetection() async throws {
        // Ensure access and start monitoring
        _ = await mockAccessManager.requestHomeDirectoryAccess()
        await fileMonitor.startMonitoring()
        
        // Wait for monitoring to be active
        try await waitForCondition {
            return self.fileMonitor.isMonitoring
        }
        
        // Allow FSEvents to fully initialize (FSEvents has internal latency)
//        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        // Set up file change collection
        var detectedFiles: [URL] = []
        
        fileMonitor.fileChanges
            .sink { urls in
                detectedFiles.append(contentsOf: urls)
            }
            .store(in: &cancellables)
        
        // Add a new JSONL file
        let newFileURL = mockAccessManager.temporaryDirectoryURL
            .appendingPathComponent(".claude/projects/test_project/new_file.jsonl")
        
        let newContent = """
        {"type":"assistant","uuid":"new-uuid","timestamp":"2025-07-23T15:00:00.000Z","sessionId":"new-session","message":{"model":"claude-3-5-sonnet-20241022","usage":{"input_tokens":300,"output_tokens":150}}}
        """
        
        // Ensure cleanup happens even if test fails
        addTeardownBlock {
            try? FileManager.default.removeItem(at: newFileURL)
        }
        
        // Write the file and force filesystem sync
        try newContent.write(to: newFileURL, atomically: true, encoding: .utf8)
        sync() // Force filesystem flush
        
        // Wait for file to be detected
        try await waitForCondition {
            return detectedFiles.contains { $0.lastPathComponent == "new_file.jsonl" }
        }
        
        // Verify the file was detected
        XCTAssertTrue(detectedFiles.contains { $0.lastPathComponent == "new_file.jsonl" },
                     "FSEvents should detect new JSONL file creation")
    }
    
    func testFileModificationDetection() async throws {
        // Ensure access and start monitoring
        _ = await mockAccessManager.requestHomeDirectoryAccess()
        await fileMonitor.startMonitoring()
        
        // Wait for monitoring to be active
        try await waitForCondition {
            return self.fileMonitor.isMonitoring
        }
        
        // Set up file change collection
        var detectedFiles: [URL] = []
        
        fileMonitor.fileChanges
            .sink { urls in
                detectedFiles.append(contentsOf: urls)
            }
            .store(in: &cancellables)
        
        // Modify existing file
        let existingFileURL = mockAccessManager.temporaryDirectoryURL
            .appendingPathComponent(".claude/projects/test_project/sample.jsonl")
        
        // Save original content for restoration
        let originalContent = try String(contentsOf: existingFileURL)
        
        // Ensure restoration happens even if test fails
        addTeardownBlock {
            try? originalContent.write(to: existingFileURL, atomically: true, encoding: .utf8)
        }
        
        // Append new content
        let additionalContent = """
        
        {"type":"assistant","uuid":"modified-uuid","timestamp":"2025-07-23T16:00:00.000Z","sessionId":"modified-session","message":{"model":"claude-3-5-sonnet-20241022","usage":{"input_tokens":400,"output_tokens":200}}}
        """
        
        // Use atomic write to ensure FSEvents sees the change
        let modifiedContent = originalContent + additionalContent
        try modifiedContent.write(to: existingFileURL, atomically: true, encoding: .utf8)
        sync() // Force filesystem flush
        
        // Wait for file modification to be detected
        try await waitForCondition {
            return detectedFiles.contains { $0.lastPathComponent == "sample.jsonl" }
        }
        
        // Verify the file was detected
        XCTAssertTrue(detectedFiles.contains { $0.lastPathComponent == "sample.jsonl" },
                     "FSEvents should detect JSONL file modification")
    }
    
    func testNewDirectoryDetection() async throws {
        // Ensure access and start monitoring
        _ = await mockAccessManager.requestHomeDirectoryAccess()
        await fileMonitor.startMonitoring()
        
        // Wait for monitoring to be active
        try await waitForCondition {
            return self.fileMonitor.isMonitoring
        }
        
        // Set up file change collection
        var detectedFiles: [URL] = []
        
        fileMonitor.fileChanges
            .sink { urls in
                detectedFiles.append(contentsOf: urls)
            }
            .store(in: &cancellables)
        
        // Create new directory with JSONL file
        let newDirURL = mockAccessManager.temporaryDirectoryURL
            .appendingPathComponent(".claude/projects/new_project")
        
        // Ensure cleanup happens even if test fails
        addTeardownBlock {
            try? FileManager.default.removeItem(at: newDirURL)
        }
        
        // Create directory first
        try FileManager.default.createDirectory(at: newDirURL, withIntermediateDirectories: true)
        
        let newFileURL = newDirURL.appendingPathComponent("project.jsonl")
        let newContent = """
        {"type":"assistant","uuid":"new-project-uuid","timestamp":"2025-07-23T17:00:00.000Z","sessionId":"new-project-session","message":{"model":"claude-3-5-sonnet-20241022","usage":{"input_tokens":500,"output_tokens":250}}}
        """
        
        try newContent.write(to: newFileURL, atomically: true, encoding: .utf8)
        sync() // Force filesystem flush
        
        // Wait for new file in new directory to be detected
        try await waitForCondition {
            return detectedFiles.contains { $0.lastPathComponent == "project.jsonl" }
        }
        
        // Verify the file was detected
        XCTAssertTrue(detectedFiles.contains { $0.lastPathComponent == "project.jsonl" },
                     "FSEvents should detect new JSONL file in new directory")
    }
    
    func testNonJSONLFilesIgnored() async throws {
        // Ensure access and start monitoring
        _ = await mockAccessManager.requestHomeDirectoryAccess()
        await fileMonitor.startMonitoring()
        
        // Wait for monitoring to be active
        try await waitForCondition {
            return self.fileMonitor.isMonitoring
        }
        
        // Set up file change collection
        var detectedFiles: [URL] = []
        
        fileMonitor.fileChanges
            .sink { urls in
                detectedFiles.append(contentsOf: urls)
            }
            .store(in: &cancellables)
        
        // Add a non-JSONL file
        let nonJSONLFileURL = mockAccessManager.temporaryDirectoryURL
            .appendingPathComponent(".claude/projects/test_project/readme.txt")
        
        // Ensure cleanup happens even if test fails
        addTeardownBlock {
            try? FileManager.default.removeItem(at: nonJSONLFileURL)
        }
        
        try "This is not a JSONL file".write(to: nonJSONLFileURL, atomically: true, encoding: .utf8)
        sync() // Force filesystem flush
        
        // Wait a reasonable time to ensure no non-JSONL files are detected
        // If they were going to be detected, they would appear within 3 seconds
        do {
            try await waitForCondition({
                return detectedFiles.contains { $0.lastPathComponent == "readme.txt" }
            }, timeout: 3.0)
            // If we get here, the non-JSONL file was detected (which is bad)
            XCTFail("Non-JSONL files should be filtered out by FSEvents processing")
        } catch {
            // This is expected - the condition should timeout because non-JSONL files should be ignored
        }
        
        // Verify no non-JSONL files were detected
        XCTAssertFalse(detectedFiles.contains { $0.lastPathComponent == "readme.txt" },
                      "Non-JSONL files should be filtered out by FSEvents processing")
    }
    
    // MARK: - Monitoring State Tests
    
    func testStartStopMonitoring() async throws {
        // Ensure access
        _ = await mockAccessManager.requestHomeDirectoryAccess()
        
        // Initially not monitoring
        XCTAssertFalse(fileMonitor.isMonitoring)
        
        // Start monitoring
        await fileMonitor.startMonitoring()
        try await waitForCondition {
            return self.fileMonitor.isMonitoring
        }
        
        // Stop monitoring
        fileMonitor.stopMonitoring()
        
        // Wait for monitoring to stop
        try await waitForCondition {
            return !self.fileMonitor.isMonitoring
        }
    }
    
    func testDoubleStartMonitoring() async throws {
        // Ensure access
        _ = await mockAccessManager.requestHomeDirectoryAccess()
        
        // Start monitoring twice
        await fileMonitor.startMonitoring()
        await fileMonitor.startMonitoring()
        
        // Should still be monitoring (no crash or issues)
        try await waitForCondition {
            return self.fileMonitor.isMonitoring
        }
    }
    
}
