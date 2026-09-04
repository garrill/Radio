#if os(macOS)
import SwiftUI
import AppKit
import UniformTypeIdentifiers

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
            DebugSettingsView()
                .tabItem { Label("Debug", systemImage: "ladybug") }
            AboutSettingsView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        // Fix the width on the TabView itself: otherwise the tab-bar pill lays
        // out before the inner `.frame(width:)` propagates up from inside the
        // Form on first open, and the segments collapse to label width until
        // you switch tabs.
        .frame(width: 380)
        .background(WindowButtonHider().frame(width: 0, height: 0))
    }
}

// MARK: - General

struct GeneralSettingsView: View {
    @AppStorage("chatroomLinkType") private var chatroomLinkType = "web"
    @AppStorage("showTracklisting") private var showTracklisting = true
    @AppStorage("artworkSize") private var artworkSize = ArtworkSize.medium

    // System owns login-item state — mirror it, don't persist our own copy.
    @State private var openAtLogin = LoginItem.isEnabled

    var body: some View {
        Form {
            Section("General") {
                Toggle("Open Radio at login", isOn: $openAtLogin)
                    .onChange(of: openAtLogin) { _, want in
                        if !LoginItem.setEnabled(want) {
                            openAtLogin = LoginItem.isEnabled // registration failed — snap back
                        }
                    }
            }

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
        .onAppear { openAtLogin = LoginItem.isEnabled }
    }
}

// MARK: - Debug

struct DebugSettingsView: View {
    @State private var clearingCache = false
    @State private var status: String?

    var body: some View {
        Form {
            Section("Logs") {
                Button("Save Logs…") { save() }
                Text("Writes a diagnostic log file you can send to the developer when reporting a problem.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Section("Tracklist") {
                Button(role: .destructive, action: clearCache) {
                    HStack(spacing: 6) {
                        if clearingCache { ProgressView().controlSize(.small) }
                        Text("Clear Tracklist Cache")
                    }
                }
                .disabled(clearingCache)

                Text("Signs you out of NTS in the tracklist windows so you can switch to another account.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            if let status {
                Text(status)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .padding(.bottom, 8)
    }

    private func save() {
        status = nil
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "radio-logs-\(Self.fileStamp()).txt"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try LogExport.write(to: url)
            status = "Saved \(url.lastPathComponent)"
        } catch {
            status = "Couldn’t save logs: \(error.localizedDescription)"
        }
    }

    private func clearCache() {
        clearingCache = true
        status = nil
        Task {
            await TracklistWindowManager.shared.clearCache()
            clearingCache = false
            status = "Tracklist cache cleared."
        }
    }

    private static func fileStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return f.string(from: Date())
    }
}

// MARK: - About

struct AboutSettingsView: View {
    var body: some View {
        VStack(spacing: 12) {
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

            Divider().frame(width: 160)

            Text("Not affiliated with NTS Radio. Audio streams, schedule data, and the NTS name and logo belong to NTS.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 36)

            HStack(spacing: 10) {
                Button("Check for Updates…") { UpdaterHolder.checkForUpdates() }
                Button("Report a Problem…") { Feedback.report() }
            }
            .controlSize(.small)

            HStack(spacing: 8) {
                Link("NTS", destination: URL(string: "https://www.nts.live")!)
                Text("·").foregroundStyle(.tertiary)
                Link("Source", destination: URL(string: "https://github.com/garrill/Radio")!)
                Text("·").foregroundStyle(.tertiary)
                Link("Built with Sparkle", destination: URL(string: "https://sparkle-project.org")!)
            }
            .font(.system(size: 10))

            Text("© 2026 Jonny Garrill · MIT-licensed · collects nothing")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 28)
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
