#if os(macOS)
import SwiftUI
import AppKit

// MARK: - Window button hider

private class _ButtonHiderView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window?.standardWindowButton(.zoomButton)?.isHidden = true
    }
}

private struct WindowButtonHider: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { _ButtonHiderView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
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
        .background(WindowButtonHider().frame(width: 0, height: 0))
    }
}

// MARK: - General

struct GeneralSettingsView: View {
    @AppStorage("chatroomLinkType") private var chatroomLinkType = "web"
    @AppStorage("showTracklisting") private var showTracklisting = true
    @AppStorage("artworkSize") private var artworkSize = ArtworkSize.medium

    var body: some View {
        Form {
            Section("User interface") {
                Picker("Chatroom link", selection: $chatroomLinkType) {
                    Text("Open in browser").tag("web")
                    Text("Open in Discord").tag("app")
                    Text("Hide link").tag("hidden")
                }
                Picker("Artwork size", selection: $artworkSize) {
                    ForEach(ArtworkSize.allCases, id: \.self) { size in
                        Text(size.label).tag(size)
                    }
                }
                Toggle("Show tracklist link", isOn: $showTracklisting)
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

            HStack(spacing: 6) {
                Text("Version \(appVersion)")
                    .foregroundStyle(.secondary)
                Text("(\(buildNumber))")
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
