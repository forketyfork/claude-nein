import Foundation
import OSLog

/// Manages launching ClaudeNein at user login using a LaunchAgent
class LaunchAtLoginManager: ObservableObject {
    static let shared = LaunchAtLoginManager()

    @Published private(set) var isEnabled: Bool

    private let fileManager = FileManager.default
    private let label = "me.forketyfork.ClaudeNein"
    private var agentURL: URL {
        let launchAgents = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        return launchAgents.appendingPathComponent("\(label).plist")
    }

    private init() {
        // Initialize isEnabled with a default value first
        isEnabled = false
        // Then set the actual value based on file existence
        isEnabled = fileManager.fileExists(atPath: agentURL.path)
    }

    /// Toggle the Run at Login setting
    func toggle() {
        isEnabled ? disable() : enable()
    }

    /// Enable the LaunchAgent
    func enable() {
        do {
            try ensureLaunchAgentsDirectory()
            try createAgentPlist()
            isEnabled = true
            Logger.app.info("✅ Enabled Run at Login")
        } catch {
            Logger.app.error("❌ Failed to enable Run at Login: \(error.localizedDescription)")
        }
    }

    /// Disable the LaunchAgent
    func disable() {
        do {
            if fileManager.fileExists(atPath: agentURL.path) {
                try fileManager.removeItem(at: agentURL)
            }
            isEnabled = false
            Logger.app.info("✅ Disabled Run at Login")
        } catch {
            Logger.app.error("❌ Failed to disable Run at Login: \(error.localizedDescription)")
        }
    }

    private func ensureLaunchAgentsDirectory() throws {
        let dir = agentURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: dir.path) {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    private func createAgentPlist() throws {
        guard let execPath = Bundle.main.executableURL?.path else {
            throw NSError(domain: "LaunchAtLogin", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing executable path"])
        }

        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [execPath],
            "RunAtLoad": true
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: agentURL)
    }
}
