import Foundation
import AppKit
import OSLog

/// Manages access to the Claude directories in a sandboxed environment
class HomeDirectoryAccessManager: ObservableObject, DirectoryAccessManager {

    // MARK: - Properties

    @Published private(set) var hasAccess = false
    @Published private(set) var isRequestingAccess = false

    private let bookmarkKeys: [String: String] = [
        "ClaudeDirectoryBookmark": ".claude/projects",
        "ConfigClaudeDirectoryBookmark": ".config/claude/projects"
    ]

    private var securedURLs: [URL] = []
    private let directoriesToMonitor: [URL]
    
    // MARK: - Initialization
    
    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        directoriesToMonitor = bookmarkKeys.values.map { relativePath in
            home.appendingPathComponent(relativePath, isDirectory: true)
        }
        checkExistingAccess()
    }
    
    deinit {
        stopAccessingSecuredResource()
    }
    
    // MARK: - Public Methods
    
    /// Request access to the Claude directories
    /// - Returns: True if access was granted, false otherwise
    @discardableResult
    func requestHomeDirectoryAccess() async -> Bool {
        if hasValidAccess { return true }

        let proceed = await MainActor.run { showAccessAlert() }
        guard proceed else { return false }

        await MainActor.run { isRequestingAccess = true }

        var granted = false
        for (key, relativePath) in bookmarkKeys {
            let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(relativePath, isDirectory: true)
            if await requestAccess(for: directory, bookmarkKey: key) {
                granted = true
            }
        }

        await MainActor.run { isRequestingAccess = false }
        hasAccess = granted
        return granted
    }
    
    /// Check if we currently have access to the home directory
    var hasValidAccess: Bool {
        return hasAccess && !securedURLs.isEmpty
    }
    func getSecuredHomeDirectoryURL() -> URL? {
        FileManager.default.homeDirectoryForCurrentUser
    }
    
    var claudeDirectories: [URL] {
        return securedURLs
    }

    /// Revoke access to all directories
    func revokeAccess() {
        stopAccessingSecuredResource()
        removeStoredBookmarks()
        securedURLs.removeAll()
        hasAccess = false
        Logger.security.info("🚫 Claude directory access revoked")
    }

    // MARK: - Private Methods

    private func checkExistingAccess() {
        for (key, relativePath) in bookmarkKeys {
            guard let data = UserDefaults.standard.data(forKey: key) else { continue }
            do {
                var isStale = false
                let url = try URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
                if isStale {
                    Logger.security.warning("⚠️ Bookmark for \(relativePath) is stale")
                    removeStoredBookmark(forKey: key)
                    continue
                }
                if url.startAccessingSecurityScopedResource() {
                    securedURLs.append(url)
                    hasAccess = true
                    Logger.security.info("✅ Restored access for \(url.lastPathComponent)")
                } else {
                    Logger.security.error("❌ Failed to access bookmarked directory: \(url.path)")
                    removeStoredBookmark(forKey: key)
                }
            } catch {
                Logger.security.error("❌ Failed to restore bookmark for \(key): \(error.localizedDescription)")
                removeStoredBookmark(forKey: key)
            }
        }
    }

    @MainActor
    private func showAccessAlert() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Allow Access to Claude Directories?"
        alert.informativeText = "ClaudeNein needs read-only access to your Claude config directories to monitor spending."
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func requestAccess(for directory: URL, bookmarkKey: String) async -> Bool {
        await withCheckedContinuation { continuation in
            Task { @MainActor in
                let panel = NSOpenPanel()
                panel.title = "Grant Access"
                panel.message = "Please grant access to \(directory.path)"
                panel.prompt = "Grant Access"
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.allowsMultipleSelection = false
                panel.canCreateDirectories = false
                panel.directoryURL = directory

                panel.begin { [weak self] result in
                    guard let self = self, result == .OK, let url = panel.url else {
                        continuation.resume(returning: false)
                        return
                    }

                    do {
                        let bookmarkData = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                        if url.startAccessingSecurityScopedResource() {
                            self.securedURLs.append(url)
                            UserDefaults.standard.set(bookmarkData, forKey: bookmarkKey)
                            UserDefaults.standard.synchronize()
                            continuation.resume(returning: true)
                        } else {
                            continuation.resume(returning: false)
                        }
                    } catch {
                        Logger.security.error("❌ Failed to create bookmark: \(error.localizedDescription)")
                        continuation.resume(returning: false)
                    }
                }
            }
        }
    }

    private func stopAccessingSecuredResource() {
        for url in securedURLs {
            url.stopAccessingSecurityScopedResource()
        }
    }

    private func removeStoredBookmark(forKey key: String) {
        UserDefaults.standard.removeObject(forKey: key)
    }

    private func removeStoredBookmarks() {
        for key in bookmarkKeys.keys { removeStoredBookmark(forKey: key) }
        UserDefaults.standard.synchronize()
    }
}

// MARK: - Extensions

extension HomeDirectoryAccessManager {
    func canAccess(path: String) -> Bool {
        for url in securedURLs {
            let securedPath = url.standardized.path
            let targetPath = URL(fileURLWithPath: path).standardized.path
            if targetPath.hasPrefix(securedPath) { return true }
        }
        return false
    }

    func securedURL(for relativePath: String) -> URL? {
        guard let baseURL = securedURLs.first else { return nil }
        return baseURL.appendingPathComponent(relativePath)
    }
}
