#if os(macOS)
import SwiftUI

// MARK: - Root

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gear") }
            AboutSettingsView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .padding()
    }
}

// MARK: - General

struct GeneralSettingsView: View {
    @AppStorage("chatroomLinkType") private var chatroomLinkType = "web"
    @AppStorage("showTracklisting") private var showTracklisting = true
    @AppStorage("artworkSize") private var artworkSize = "medium"

    var body: some View {
        Form {
            Section("UI") {
                Picker("Chatroom", selection: $chatroomLinkType) {
                    Text("Web Browser").tag("web")
                    Text("Discord App").tag("app")
                    Text("Hide").tag("hidden")
                }
                Picker("Artwork size", selection: $artworkSize) {
                    Text("Small").tag("small")
                    Text("Medium").tag("medium")
                    Text("Large").tag("large")
                }
                Toggle("Show tracklist button", isOn: $showTracklisting)
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .padding(.bottom, 8)
    }
}

// MARK: - About

struct AboutSettingsView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)

            Text(appName)
                .font(.title3.weight(.semibold))

            VStack(spacing: 3) {
                Text("Version \(appVersion)")
                    .foregroundStyle(.secondary)
                Text("Build \(buildNumber)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 40)
        .frame(width: 380)
    }

    private var appName: String {
        Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "Radio"
    }
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }
    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }
}

#Preview {
    SettingsView()
}
#endif
