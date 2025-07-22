import Foundation
import AppKit
import OSLog

/// Manages access to the user's home directory in a sandboxed environment
class HomeDirectoryAccessManager: ObservableObject {
    
    // MARK: - Properties
    
    @Published private(set) var hasAccess = false
    @Published private(set) var isRequestingAccess = false
    
    private let bookmarkKey = "HomeDirectoryBookmark"
    private var securedURL: URL?
    
    // MARK: - Initialization
    
    init() {
        checkExistingAccess()
    }
    
    deinit {
        stopAccessingSecuredResource()
    }
    
    // MARK: - Public Methods
    
    /// Request access to the user's home directory
    /// - Returns: True if access was granted, false otherwise
    @discardableResult
    func requestHomeDirectoryAccess() async -> Bool {
        await MainActor.run {
            isRequestingAccess = true
        }
        
        defer {
            Task { @MainActor in
                isRequestingAccess = false
            }
        }
        
        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async { [weak self] in
                self?.showAccessRequestPanel { success in
                    continuation.resume(returning: success)
                }
            }
        }
    }
    
    /// Check if we currently have access to the home directory
    var hasValidAccess: Bool {
        return hasAccess && securedURL != nil
    }
    
    /// Get the secured home directory URL for file operations
    /// - Returns: The secured URL if access is available, nil otherwise
    func getSecuredHomeDirectoryURL() -> URL? {
        guard hasValidAccess else { return nil }
        return securedURL
    }
    
    /// Revoke access to the home directory
    func revokeAccess() {
        stopAccessingSecuredResource()
        removeStoredBookmark()
        
        hasAccess = false
        securedURL = nil
        
        Logger.security.info("🚫 Home directory access revoked")
    }
    
    // MARK: - Private Methods
    
    private func checkExistingAccess() {
        guard let bookmarkData = UserDefaults.standard.data(forKey: bookmarkKey) else {
            Logger.security.debug("🔍 No existing home directory bookmark found")
            return
        }
        
        do {
            var isStale = false
            let restoredURL = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            
            if isStale {
                Logger.security.warning("⚠️ Home directory bookmark is stale, access may be limited")
                removeStoredBookmark()
                return
            }
            
            if restoredURL.startAccessingSecurityScopedResource() {
                securedURL = restoredURL
                hasAccess = true
                Logger.security.info("✅ Restored home directory access from bookmark")
            } else {
                Logger.security.error("❌ Failed to start accessing home directory from bookmark")
                removeStoredBookmark()
            }
            
        } catch {
            Logger.security.error("❌ Failed to restore home directory bookmark: \(error.localizedDescription)")
            removeStoredBookmark()
        }
    }
    
    private func showAccessRequestPanel(completion: @escaping (Bool) -> Void) {
        let panel = NSOpenPanel()
        
        // Configure the panel
        panel.title = "Grant Home Directory Access"
        panel.message = "ClaudeNein needs access to your home directory to monitor Claude config files.\n\nPlease select your home directory to grant permission."
        panel.prompt = "Grant Access"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        
        // Set the default directory to the user's home
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        
        // Show the panel
        panel.begin { [weak self] result in
            guard let self = self else {
                completion(false)
                return
            }
            
            if result == .OK, let selectedURL = panel.url {
                self.handleDirectorySelection(selectedURL, completion: completion)
            } else {
                Logger.security.info("🚫 User cancelled home directory access request")
                completion(false)
            }
        }
    }
    
    private func handleDirectorySelection(_ selectedURL: URL, completion: @escaping (Bool) -> Void) {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        
        // Verify the selected directory is the home directory or a parent that includes it
        guard selectedURL.standardized.path == homeDirectory.standardized.path ||
              homeDirectory.standardized.path.hasPrefix(selectedURL.standardized.path + "/") else {
            
            Logger.security.warning("⚠️ Selected directory does not provide access to home directory")
            showInvalidSelectionAlert()
            completion(false)
            return
        }
        
        // Create security-scoped bookmark
        do {
            let bookmarkData = try selectedURL.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            
            // Store the bookmark
            UserDefaults.standard.set(bookmarkData, forKey: bookmarkKey)
            UserDefaults.standard.synchronize()
            
            // Start accessing the secured resource
            if selectedURL.startAccessingSecurityScopedResource() {
                stopAccessingSecuredResource() // Stop any previous access
                securedURL = selectedURL
                hasAccess = true
                
                Logger.security.info("✅ Successfully granted home directory access")
                Logger.security.debug("📁 Secured access to: \(selectedURL.path, privacy: .private)")
                
                completion(true)
            } else {
                Logger.security.error("❌ Failed to start accessing selected directory")
                completion(false)
            }
            
        } catch {
            Logger.security.error("❌ Failed to create security-scoped bookmark: \(error.localizedDescription)")
            completion(false)
        }
    }
    
    private func showInvalidSelectionAlert() {
        let alert = NSAlert()
        alert.messageText = "Invalid Directory Selection"
        alert.informativeText = "Please select your home directory to grant ClaudeNein access to Claude config files."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        
        alert.runModal()
    }
    
    private func stopAccessingSecuredResource() {
        securedURL?.stopAccessingSecurityScopedResource()
    }
    
    private func removeStoredBookmark() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        UserDefaults.standard.synchronize()
    }
}

// MARK: - Extensions

extension HomeDirectoryAccessManager {
    
    /// Convenience method to check if a specific path is accessible
    /// - Parameter path: The file path to check
    /// - Returns: True if the path is accessible through our secured URL
    func canAccess(path: String) -> Bool {
        guard let securedURL = securedURL else { return false }
        
        let targetURL = URL(fileURLWithPath: path)
        let securedPath = securedURL.standardized.path
        let targetPath = targetURL.standardized.path
        
        return targetPath.hasPrefix(securedPath)
    }
    
    /// Get a URL for a path within the secured directory
    /// - Parameter relativePath: Path relative to the secured directory
    /// - Returns: URL if accessible, nil otherwise
    func securedURL(for relativePath: String) -> URL? {
        guard let baseURL = securedURL else { return nil }
        return baseURL.appendingPathComponent(relativePath)
    }
}