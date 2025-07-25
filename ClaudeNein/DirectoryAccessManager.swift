import Foundation

/// Protocol for managing directory access in different environments (production, testing)
protocol DirectoryAccessManager {
    /// Check if we currently have access to the monitored directory
    var hasValidAccess: Bool { get }
    
    /// Get the URL for the .claude directory
    var claudeDirectoryURL: URL? { get }
    
    /// Get the URL for the projects directory within the .claude directory
    var claudeProjectsDirectoryURL: URL? { get }

    /// All Claude directories that we have access to
    var claudeDirectories: [URL] { get }
    
    /// Request access to the directory (async for UI prompts in production)
    /// - Returns: True if access was granted, false otherwise
    func requestHomeDirectoryAccess() async -> Bool
    
    /// Revoke access to the directory
    func revokeAccess()
    
    /// Check if a specific path is accessible
    /// - Parameter path: The file path to check
    /// - Returns: True if the path is accessible
    func canAccess(path: String) -> Bool
    
    /// Get a URL for a path within the secured directory
    /// - Parameter relativePath: Path relative to the secured directory
    /// - Returns: URL if accessible, nil otherwise
    func securedURL(for relativePath: String) -> URL?
}