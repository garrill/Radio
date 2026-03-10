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
            return
        }

        // Defer the expensive WKWebView + WebContent process creation off the
        // current run-loop iteration so it doesn't block AVPlayer's audio thread.
        DispatchQueue.main.async { [weak self] in
            self?.createWindow(for: channel)
        }
    }

    private func createWindow(for channel: RadioChannel) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = Self.dataStore

        let webView = WKWebView(frame: .zero, configuration: config)

        // NSWindow defer: true delays backing-store allocation until first draw,
        // spreading the GPU setup cost instead of hitting it all at once.
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
        windows[channel] = (window, delegate)

        window.makeKeyAndOrderFront(nil)

        // Load the URL after the window is on screen so WebKit's render pipeline
        // initialises alongside the window rather than blocking before it appears.
        let url = URL(string: "https://www.nts.live/live-tracklist/\(channel.rawValue)")!
        webView.load(URLRequest(url: url))
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
