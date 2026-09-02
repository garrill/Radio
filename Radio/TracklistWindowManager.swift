#if os(macOS)
import AppKit
import WebKit
import OSLog

/// Opens and manages persistent `WKWebView` windows for the NTS live tracklist.
///
/// Windows (and their WebContent processes) are kept alive after the user closes them
/// so reopening during playback doesn't stutter. But NTS's tracklist page runs a live
/// ticker, so a *hidden* page still pegs a WebCore thread and holds ~120 MB. To avoid
/// paying that while nothing is on screen, an idle window is reloaded to `about:blank`
/// after `idleGrace` seconds — the window and its warm process stay, the live page
/// doesn't. `open(channel:)` reloads the real URL. While playback is active we skip the
/// blanking (a reload stutter mid-playback is the thing this class exists to prevent).
@MainActor
class TracklistWindowManager {
    static let shared = TracklistWindowManager()

    private final class Entry {
        let window: NSWindow
        let webView: WKWebView
        let delegate: WindowDelegate
        var idleBlank: DispatchWorkItem?
        var isBlank = false

        init(window: NSWindow, webView: WKWebView, delegate: WindowDelegate) {
            self.window = window
            self.webView = webView
            self.delegate = delegate
        }
    }

    private var entries: [RadioChannel: Entry] = [:]
    private static let dataStore = WKWebsiteDataStore.default()
    private static let blankURL = URL(string: "about:blank")!
    private let idleGrace: TimeInterval = 60

    /// Set by `AppDelegate` from `player.$playingChannel`. Pages are kept warm while true.
    var isPlaybackActive = false {
        didSet { if isPlaybackActive { entries.keys.forEach { cancelIdleBlank(for: $0) } } }
    }

    /// Creates windows for all channels and loads their tracklist URLs, so an early
    /// first open is instant. Pages that are never opened get blanked after `idleGrace`.
    func preload() {
        for channel in RadioChannel.allCases where entries[channel] == nil {
            let entry = createEntry(for: channel)
            entry.webView.load(URLRequest(url: tracklistURL(for: channel)))
            scheduleIdleBlank(for: channel)
        }
    }

    func open(channel: RadioChannel) {
        NSApp.activate(ignoringOtherApps: true)
        let entry = entries[channel] ?? createEntry(for: channel)
        cancelIdleBlank(for: channel)
        if entry.isBlank || entry.webView.url == nil {
            Log.tracklist.debug("Reloading \(channel.label, privacy: .public) tracklist")
            entry.webView.load(URLRequest(url: tracklistURL(for: channel)))
            entry.isBlank = false
        }
        entry.window.makeKeyAndOrderFront(nil)
    }

    fileprivate func windowClosed(_ channel: RadioChannel) {
        scheduleIdleBlank(for: channel)
    }

    // MARK: - Idle blanking

    private func scheduleIdleBlank(for channel: RadioChannel) {
        guard let entry = entries[channel] else { return }
        entry.idleBlank?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let entry = self.entries[channel] else { return }
            entry.idleBlank = nil
            guard !entry.window.isVisible, !self.isPlaybackActive else {
                self.scheduleIdleBlank(for: channel) // still in use — try again later
                return
            }
            guard !entry.isBlank else { return }
            Log.tracklist.debug("Blanking idle \(channel.label, privacy: .public) tracklist window")
            entry.webView.load(URLRequest(url: Self.blankURL))
            entry.isBlank = true
        }
        entry.idleBlank = work
        DispatchQueue.main.asyncAfter(deadline: .now() + idleGrace, execute: work)
    }

    private func cancelIdleBlank(for channel: RadioChannel) {
        entries[channel]?.idleBlank?.cancel()
        entries[channel]?.idleBlank = nil
    }

    // MARK: - Construction

    private func tracklistURL(for channel: RadioChannel) -> URL {
        URL(string: "https://www.nts.live/live-tracklist/\(channel.rawValue)")!
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
        // Window is kept alive (isReleasedWhenClosed = false); after a grace period
        // the manager reloads it to about:blank so the hidden page stops burning CPU.
        MainActor.assumeIsolated {
            manager?.windowClosed(channel)
        }
    }
}
#endif
