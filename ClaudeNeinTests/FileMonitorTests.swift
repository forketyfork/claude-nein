import XCTest
import Combine
@testable import ClaudeNein

final class FileMonitorTests: XCTestCase {
    
    var mockAccessManager: MockDirectoryAccessManager!
    var fileMonitor: FileMonitor!
    var cancellables: Set<AnyCancellable>!
    
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
        XCTAssertFalse(fileMonitor.isMonitoring)
    }
    
    func testFileMonitorWithAccess() async {
        // Ensure access is granted
        let accessGranted = await mockAccessManager.requestHomeDirectoryAccess()
        XCTAssertTrue(accessGranted)
        
        // Start monitoring
        await fileMonitor.startMonitoring()
        
        // Should start monitoring with access
        XCTAssertTrue(fileMonitor.isMonitoring)
    }
    
    // MARK: - File Change Detection Tests
    
    func testFileAdditionDetection() async throws {
        // Ensure access and start monitoring
        _ = await mockAccessManager.requestHomeDirectoryAccess()
        await fileMonitor.startMonitoring()
        
        // Wait for FSEvents to fully initialize (1+ seconds for stream + latency)
        try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
        
        // Set up expectation for file changes
        let expectation = XCTestExpectation(description: "File addition detected")
        var detectedFiles: [URL] = []
        
        fileMonitor.fileChanges
            .sink { urls in
                detectedFiles.append(contentsOf: urls)
                if !urls.isEmpty {
                    expectation.fulfill()
                }
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
        
        // Wait for FSEvents detection (1 second latency + 0.5 second debounce + buffer)
        await fulfillment(of: [expectation], timeout: 3.0)
        
        // Verify the file was detected
        XCTAssertTrue(detectedFiles.contains { $0.lastPathComponent == "new_file.jsonl" },
                     "FSEvents should detect new JSONL file creation")
    }
    
    func testFileModificationDetection() async throws {
        // Ensure access and start monitoring
        _ = await mockAccessManager.requestHomeDirectoryAccess()
        await fileMonitor.startMonitoring()
        
        // Wait for FSEvents to fully initialize
        try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
        
        // Set up expectation for file changes
        let expectation = XCTestExpectation(description: "File modification detected")
        var detectedFiles: [URL] = []
        
        fileMonitor.fileChanges
            .sink { urls in
                detectedFiles.append(contentsOf: urls)
                if !urls.isEmpty {
                    expectation.fulfill()
                }
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
        
        // Wait for FSEvents detection
        await fulfillment(of: [expectation], timeout: 3.0)
        
        // Verify the file was detected
        XCTAssertTrue(detectedFiles.contains { $0.lastPathComponent == "sample.jsonl" },
                     "FSEvents should detect JSONL file modification")
    }
    
    func testNewDirectoryDetection() async throws {
        // Ensure access and start monitoring
        _ = await mockAccessManager.requestHomeDirectoryAccess()
        await fileMonitor.startMonitoring()
        
        // Wait for FSEvents to fully initialize
        try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
        
        // Set up expectation for file changes
        let expectation = XCTestExpectation(description: "New directory with files detected")
        var detectedFiles: [URL] = []
        
        fileMonitor.fileChanges
            .sink { urls in
                detectedFiles.append(contentsOf: urls)
                if !urls.isEmpty {
                    expectation.fulfill()
                }
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
        
        // Longer delay to let directory creation propagate through FSEvents
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        let newFileURL = newDirURL.appendingPathComponent("project.jsonl")
        let newContent = """
        {"type":"assistant","uuid":"new-project-uuid","timestamp":"2025-07-23T17:00:00.000Z","sessionId":"new-project-session","message":{"model":"claude-3-5-sonnet-20241022","usage":{"input_tokens":500,"output_tokens":250}}}
        """
        
        try newContent.write(to: newFileURL, atomically: true, encoding: .utf8)
        sync() // Force filesystem flush
        
        // Wait longer for FSEvents detection of new directory + file
        await fulfillment(of: [expectation], timeout: 5.0)
        
        // Verify the file was detected
        XCTAssertTrue(detectedFiles.contains { $0.lastPathComponent == "project.jsonl" },
                     "FSEvents should detect new JSONL file in new directory")
    }
    
    func testNonJSONLFilesIgnored() async throws {
        // Ensure access and start monitoring
        _ = await mockAccessManager.requestHomeDirectoryAccess()
        await fileMonitor.startMonitoring()
        
        // Wait for FSEvents to fully initialize
        try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
        
        // Set up expectation - we expect NO changes for non-JSONL files
        let expectation = XCTestExpectation(description: "No changes detected for non-JSONL files")
        expectation.isInverted = true // We expect this NOT to be fulfilled
        
        var detectedAnyFiles = false
        fileMonitor.fileChanges
            .sink { urls in
                // Only count files as detected if they match the non-JSONL file we're testing
                let nonJSONLDetected = urls.contains { $0.lastPathComponent == "readme.txt" }
                if nonJSONLDetected {
                    detectedAnyFiles = true
                    expectation.fulfill() // This should NOT happen
                }
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
        
        // Wait sufficient time for FSEvents to potentially detect the change
        // but expect that it will be filtered out
        await fulfillment(of: [expectation], timeout: 3.0)
        
        // Verify no non-JSONL files were detected
        XCTAssertFalse(detectedAnyFiles, "Non-JSONL files should be filtered out by FSEvents processing")
    }
    
    // MARK: - Monitoring State Tests
    
    func testStartStopMonitoring() async {
        // Ensure access
        _ = await mockAccessManager.requestHomeDirectoryAccess()
        
        // Initially not monitoring
        XCTAssertFalse(fileMonitor.isMonitoring)
        
        // Start monitoring
        await fileMonitor.startMonitoring()
        XCTAssertTrue(fileMonitor.isMonitoring)
        
        // Stop monitoring
        fileMonitor.stopMonitoring()
        
        // Give it a moment to stop
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        XCTAssertFalse(fileMonitor.isMonitoring)
    }
    
    func testDoubleStartMonitoring() async {
        // Ensure access
        _ = await mockAccessManager.requestHomeDirectoryAccess()
        
        // Start monitoring twice
        await fileMonitor.startMonitoring()
        await fileMonitor.startMonitoring()
        
        // Should still be monitoring (no crash or issues)
        XCTAssertTrue(fileMonitor.isMonitoring)
    }
    
}