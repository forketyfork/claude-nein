import SwiftUI

struct AboutView: View {
    @Environment(\.presentationMode) var presentationMode
    
    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
    
    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // App Icon and Title
            VStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage!)
                    .resizable()
                    .frame(width: 64, height: 64)
                
                Text("ClaudeNein")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Claude Code Spending Monitor")
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
            
            Divider()
                .padding(.horizontal, 40)
            
            // Version Information
            VStack(spacing: 8) {
                Text("Version \(appVersion) (\(buildNumber))")
                    .font(.body)
                    .foregroundColor(.primary)
            }
            
            // Copyright
            Text("© 2025 Forketyfork")
                .font(.body)
                .foregroundColor(.secondary)
            
            // Repository Link
            Button(action: openRepository) {
                HStack {
                    Image(systemName: "link")
                    Text("View on GitHub")
                }
                .foregroundColor(.accentColor)
            }
            .buttonStyle(.borderless)
            .onHover { hovering in
                NSCursor.pointingHand.set()
            }
            
            Spacer()
            
            // Close Button
            Button("Close") {
                presentationMode.wrappedValue.dismiss()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(40)
        .frame(width: 400, height: 350)
    }
    
    private func openRepository() {
        if let url = URL(string: "https://github.com/forketyfork/claude-nein") {
            NSWorkspace.shared.open(url)
        }
    }
}

#if DEBUG
struct AboutView_Previews: PreviewProvider {
    static var previews: some View {
        AboutView()
    }
}
#endif