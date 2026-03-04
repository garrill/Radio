#if os(macOS)
import AppKit
import WebKit

/// Opens and manages persistent WKWebView windows for the NTS live tracklist.
/// Uses a shared persistent WKWebsiteDataStore so the user only needs to log in once.
@MainActor
class TracklistWindowManager {
    static let shared = TracklistWindowManager()

    // One window per channel, kept alive so login cookies persist
    private var windows: [RadioChannel: (window: NSWindow, delegate: WindowDelegate)] = [:]

    private static let dataStore = WKWebsiteDataStore.default()

    func open(channel: RadioChannel) {
        if let existing = windows[channel]?.window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let config = WKWebViewConfiguration()
        config.websiteDataStore = Self.dataStore

        let webView = WKWebView(frame: .zero, configuration: config)
        let url = URL(string: "https://www.nts.live/live-tracklist/\(channel.rawValue)")!
        webView.load(URLRequest(url: url))

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 350),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "\(channel.label) — Live Tracklist"
        window.contentView = webView
        window.center()
        window.isReleasedWhenClosed = false
        
        let delegate = WindowDelegate(channel: channel, manager: self)
        window.delegate = delegate
        windows[channel] = (window, delegate)

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    fileprivate func windowClosed(channel: RadioChannel) {
        windows.removeValue(forKey: channel)
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
        Task { @MainActor in
            self.manager?.windowClosed(channel: self.channel)
        }
    }
}
#endif
