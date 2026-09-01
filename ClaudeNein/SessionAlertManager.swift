import Foundation
import UserNotifications
import OSLog

/// Monitors session token usage and posts notifications at threshold levels
class SessionAlertManager {
    static let shared = SessionAlertManager()

    private let logger = Logger(subsystem: "ClaudeNein", category: "SessionAlert")
    private let center = UNUserNotificationCenter.current()
    private let userDefaults = UserDefaults.standard

    private let enabledKey = "sessionAlertsEnabled"
    private let warningKey = "sessionAlertWarningThreshold"
    private let criticalKey = "sessionAlertCriticalThreshold"

    private let sessionTokenLimit = 1_000_000 // 5-hour session limit

    private var lastLevel: SessionAlertLevel = .none

    private init() {
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            if !granted {
                self.logger.warning("User notifications not authorized")
            }
        }
    }

    /// Evaluate current token usage and send notifications if thresholds are crossed
    func evaluate(tokensUsed: Int) -> SessionAlertLevel {
        guard alertsEnabled else { return .none }

        let percent = Double(tokensUsed) / Double(sessionTokenLimit)
        let warning = warningThreshold / 100.0
        let critical = criticalThreshold / 100.0

        var level: SessionAlertLevel = .none
        if percent >= critical {
            level = .critical
        } else if percent >= warning {
            level = .warning
        }

        if level != .none && level != lastLevel {
            sendNotification(for: level, percent: percent)
        }

        if level != lastLevel {
            lastLevel = level
        }

        if level == .none {
            lastLevel = .none
        }

        return level
    }

    private func sendNotification(for level: SessionAlertLevel, percent: Double) {
        let content = UNMutableNotificationContent()
        let percentString = Int(percent * 100)

        switch level {
        case .warning:
            content.title = "Session tokens \(percentString)% used"
        case .critical:
            content.title = "Session tokens \(percentString)% used"
        case .none:
            return
        }

        content.body = "You have used \(percentString)% of your 5-hour session token limit."

        let request = UNNotificationRequest(
            identifier: "sessionAlert-\(level)",
            content: content,
            trigger: nil
        )
        center.add(request) { error in
            if let error = error {
                self.logger.error("Failed to post notification: \(error.localizedDescription)")
            }
        }
    }

    private var alertsEnabled: Bool {
        if userDefaults.object(forKey: enabledKey) == nil {
            return true
        }
        return userDefaults.bool(forKey: enabledKey)
    }

    private var warningThreshold: Double {
        let value = userDefaults.double(forKey: warningKey)
        return value > 0 ? value : 70.0
    }

    private var criticalThreshold: Double {
        let value = userDefaults.double(forKey: criticalKey)
        return value > 0 ? value : 90.0
    }
}

enum SessionAlertLevel {
    case none
    case warning
    case critical
}

