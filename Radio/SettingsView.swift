#if os(macOS)
import SwiftUI
import AppKit

// MARK: - Window Manager

@MainActor
class SettingsWindowManager {
    static let shared = SettingsWindowManager()
    private var window: NSWindow?

    func open() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let controller = NSHostingController(rootView: SettingsView())
        let w = NSWindow(contentViewController: controller)
        w.title = "Radio Settings"
        w.styleMask = [.titled, .closable]
        w.isReleasedWhenClosed = false
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = w
    }
}

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
        .frame(minWidth: 380, maxWidth: .infinity, minHeight: 420, maxHeight: .infinity)
    }
}

// MARK: - General

struct GeneralSettingsView: View {
    @AppStorage("chatroomLinkType") private var chatroomLinkType = "web"
    @AppStorage("showTracklisting") private var showTracklisting = true

    var body: some View {
        Form {
            Section("Chatroom") {
                Picker("Open in", selection: $chatroomLinkType) {
                    Text("Web Browser").tag("web")
                    Text("Discord App").tag("app")
                    Text("Hide").tag("hidden")
                }
                .pickerStyle(.radioGroup)
            }

            Section("Tracklist") {
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
