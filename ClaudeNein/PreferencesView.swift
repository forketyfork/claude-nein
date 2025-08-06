import SwiftUI

/// App preferences for session alert settings
struct PreferencesView: View {
    @AppStorage("sessionAlertsEnabled") private var alertsEnabled = true
    @AppStorage("sessionAlertWarningThreshold") private var warningThreshold = 70.0
    @AppStorage("sessionAlertCriticalThreshold") private var criticalThreshold = 90.0

    var body: some View {
        Form {
            Toggle("Enable session token alerts", isOn: $alertsEnabled)
            HStack {
                Text("Warning threshold (%)")
                TextField("", value: $warningThreshold, format: .number)
                    .frame(width: 60)
            }
            HStack {
                Text("Critical threshold (%)")
                TextField("", value: $criticalThreshold, format: .number)
                    .frame(width: 60)
            }
        }
        .padding(20)
        .frame(width: 300)
    }
}

#Preview {
    PreferencesView()
}
