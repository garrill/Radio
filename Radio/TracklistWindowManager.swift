#if os(macOS)
import AppKit
import WebKit

/// Opens and manages persistent WKWebView windows for the NTS live tracklist.
/// Windows are kept alive after the user closes them so the WebContent process
/// stays warm — preventing audio stutter on subsequent opens during playback.
@MainActor
class TracklistWindowManager {
    static let shared = TracklistWindowManager()

    private struct Entry {
        let window: NSWindow
        let webView: WKWebView
        let delegate: WindowDelegate
    }

    private var entries: [RadioChannel: Entry] = [:]
    private static let dataStore = WKWebsiteDataStore.default()

    /// Creates windows for all channels without loading any URLs.
    /// Call this at launch to spin up the WebContent process before playback starts.
    func preload() {
        for channel in RadioChannel.allCases where entries[channel] == nil {
            createEntry(for: channel)
        }
    }

    func open(channel: RadioChannel) {
        NSApp.activate(ignoringOtherApps: true)
        let entry = entries[channel] ?? createEntry(for: channel)
        if entry.webView.url == nil {
            let url = URL(string: "https://www.nts.live/live-tracklist/\(channel.rawValue)")!
            entry.webView.load(URLRequest(url: url))
        }
        entry.window.makeKeyAndOrderFront(nil)
    }

    @discardableResult
    private func createEntry(for channel: RadioChannel) -> Entry {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = Self.dataStore

        let webView = WKWebView(frame: .zero, configuration: config)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 350),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: true
        )
        window.title = "\(channel.label) — Live Tracklist"
        window.contentView = webView
        window.center()
        window.isReleasedWhenClosed = false

        let delegate = WindowDelegate(channel: channel, manager: self)
        window.delegate = delegate

        let entry = Entry(window: window, webView: webView, delegate: delegate)
        entries[channel] = entry
        return entry
    }
}

private class WindowDelegate: NSObject, NSWindowDelegate {
    let channel: RadioChannel
    weak var manager: TracklistWindowManager?

    init(channel: RadioChannel, manager: TracklistWindowManager) {
        self.channel = channel
        self.manager = manager
    }

    func windowWillClose(_ notification: Notification) {
        // Window is intentionally kept alive (isReleasedWhenClosed = false)
        // so the WebContent process stays warm for the next open.
    }
}
#endif
