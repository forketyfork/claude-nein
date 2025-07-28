import Foundation
@testable import ClaudeNein

/// Mock implementation of DirectoryAccessManager for testing
class MockDirectoryAccessManager: DirectoryAccessManager {
    
    // MARK: - Properties
    
    private let tempDirectoryURL: URL
    private var _hasValidAccess: Bool = true
    
    var hasValidAccess: Bool {
        return _hasValidAccess
    }
    
    var claudeProjectsDirectoryURL: URL? {
        guard hasValidAccess else { return nil }
        return tempDirectoryURL.appendingPathComponent(".claude/projects", isDirectory: true)
    }

    var claudeDirectories: [URL] {
        guard let projectsDir = claudeProjectsDirectoryURL else { return [] }
        return [projectsDir]
    }
    
    // MARK: - Initialization
    
    init() {
        // Create a unique temporary directory for this test instance
        let tempDir = FileManager.default.temporaryDirectory
        self.tempDirectoryURL = tempDir.appendingPathComponent("ClaudeNeinTests-\(UUID().uuidString)", isDirectory: true)
        setupTestDirectory()
    }
    
    // MARK: - DirectoryAccessManager Protocol
    
    func requestHomeDirectoryAccess() async -> Bool {
        _hasValidAccess = true
        return true
    }
    
    func revokeAccess() {
        _hasValidAccess = false
    }
    
    func canAccess(path: String) -> Bool {
        guard hasValidAccess else { return false }
        let targetURL = URL(fileURLWithPath: path)
        let tempPath = tempDirectoryURL.standardized.path
        let targetPath = targetURL.standardized.path
        return targetPath.hasPrefix(tempPath)
    }
    
    func securedURL(for relativePath: String) -> URL? {
        guard hasValidAccess else { return nil }
        return tempDirectoryURL.appendingPathComponent(relativePath)
    }
    
    // MARK: - Test Helpers
    
    /// Set access state for testing
    func setAccess(_ hasAccess: Bool) {
        _hasValidAccess = hasAccess
    }
    
    /// Create the temporary test directory structure with fresh test data
    private func setupTestDirectory() {
        let fileManager = FileManager.default
        
        do {
            // Create the temporary directory structure
            try fileManager.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
            
            guard let projectsDir = claudeProjectsDirectoryURL else {
                print("Failed to get Claude projects directory URL")
                return
            }
            
            // Create .claude/projects directories
            try fileManager.createDirectory(at: projectsDir, withIntermediateDirectories: true)
            
            // Create test project directories
            let testProjectDir = projectsDir.appendingPathComponent("test_project")
            let anotherProjectDir = projectsDir.appendingPathComponent("another_project")
            
            try fileManager.createDirectory(at: testProjectDir, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: anotherProjectDir, withIntermediateDirectories: true)
            
            // Create test data files with hardcoded content
            try createTestDataFiles(testProjectDir: testProjectDir, anotherProjectDir: anotherProjectDir)
            
            print("✅ Created temporary test directory: \(tempDirectoryURL.path)")
            
        } catch {
            print("❌ Failed to setup temporary test directory: \(error)")
        }
    }
    
    /// Create test data files with hardcoded content
    private func createTestDataFiles(testProjectDir: URL, anotherProjectDir: URL) throws {
        let sampleContent = """
        {"type":"assistant","uuid":"test-uuid-1","timestamp":"2025-07-23T14:00:00.000Z","sessionId":"test-session","message":{"model":"claude-3-5-sonnet-20241022","usage":{"input_tokens":100,"output_tokens":50}}}
        {"type":"assistant","uuid":"test-uuid-2","timestamp":"2025-07-23T14:01:00.000Z","sessionId":"test-session","message":{"model":"claude-3-5-sonnet-20241022","usage":{"input_tokens":200,"output_tokens":75}}}
        """
        
        let initialContent = """
        {"type":"assistant","uuid":"initial-uuid","timestamp":"2025-07-23T13:00:00.000Z","sessionId":"initial-session","message":{"model":"claude-3-5-sonnet-20241022","usage":{"input_tokens":50,"output_tokens":25}}}
        """
        
        let sampleFileURL = testProjectDir.appendingPathComponent("sample.jsonl")
        let initialFileURL = anotherProjectDir.appendingPathComponent("initial.jsonl")
        
        try sampleContent.write(to: sampleFileURL, atomically: true, encoding: .utf8)
        try initialContent.write(to: initialFileURL, atomically: true, encoding: .utf8)
        
        print("✅ Created test data files:")
        print("  - \(sampleFileURL.path)")
        print("  - \(initialFileURL.path)")
    }
    
    /// Clean up the temporary test directory completely
    func cleanupTestDirectory() {
        let fileManager = FileManager.default
        
        do {
            if fileManager.fileExists(atPath: tempDirectoryURL.path) {
                try fileManager.removeItem(at: tempDirectoryURL)
                print("✅ Cleaned up temporary test directory: \(tempDirectoryURL.path)")
            }
        } catch {
            print("⚠️ Failed to cleanup temporary test directory: \(error)")
        }
    }
    
    /// Get the temporary directory URL for tests that need direct access
    var temporaryDirectoryURL: URL {
        return tempDirectoryURL
    }
}