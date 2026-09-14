import Foundation
import Combine
import AVFoundation
import OSLog
#if os(macOS)
import MediaPlayer
import AppKit
#endif

enum RadioChannel: Int, CaseIterable, Identifiable {
    case one = 1
    case two = 2

    var id: Int { rawValue }

    var streamURL: URL {
        switch self {
        case .one: Self.streamOneURL
        case .two: Self.streamTwoURL
        }
    }

    private static let streamOneURL = URL(string: "https://stream-relay-geo.ntslive.net/stream")!
    private static let streamTwoURL = URL(string: "https://stream-relay-geo.ntslive.net/stream2")!

    var label: String {
        switch self {
        case .one: "NTS 1"
        case .two: "NTS 2"
        }
    }

    var menuBarSymbol: String {
        switch self {
        case .one: "1.square.fill"
        case .two: "2.square.fill"
        }
    }

    var next: RadioChannel { self == .one ? .two : .one }
    var previous: RadioChannel { self == .two ? .one : .two }
}

/// What the single `AVPlayer` is currently pointed at — a live NTS channel or an
/// Infinite Mixtape. Equality is by identity (channel case / mixtape alias) so a
/// background refresh of the mixtape list never drops the "playing" highlight.
enum PlayingItem: Equatable, Sendable {
    case channel(RadioChannel)
    case mixtape(Mixtape)

    var streamURL: URL {
        switch self {
        case .channel(let c): c.streamURL
        case .mixtape(let m): m.streamURL
        }
    }

    var label: String {
        switch self {
        case .channel(let c): c.label
        case .mixtape(let m): m.title
        }
    }

    /// The live channel, when this is a channel; `nil` for a mixtape.
    var channel: RadioChannel? {
        if case .channel(let c) = self { return c }
        return nil
    }

    static func == (lhs: PlayingItem, rhs: PlayingItem) -> Bool {
        switch (lhs, rhs) {
        case let (.channel(a), .channel(b)): return a == b
        case let (.mixtape(a), .mixtape(b)): return a.alias == b.alias
        default: return false
        }
    }
}

@MainActor
class RadioPlayer: ObservableObject {
    @Published var playing: PlayingItem?

    /// Read-only convenience for call sites and tests that only care about live channels.
    var playingChannel: RadioChannel? { playing?.channel }
    @Published var isBuffering = false
    @Published var isPanelVisible = false
    /// Set when a stream fails and the one automatic retry is also exhausted. Survives `stop()`
    /// so the panel can show a "playback stopped" state; cleared when playback next starts.
    @Published var streamFailed = false

    /// App-level output volume (0…1), applied to whichever `AVPlayer` is live and persisted
    /// across launches. Independent of system volume. Every `play()` applies it to the new
    /// player; `fadeOutAndStop` ramps the underlying `AVPlayer.volume` relative to this and
    /// never writes back here, so the stored level survives a fade-out.
    private static let volumeKey = "playerVolume"
    @Published var volume: Float = 1.0 {
        didSet {
            player?.volume = volume
            UserDefaults.standard.set(Double(volume), forKey: Self.volumeKey)
        }
    }

    /// Level to restore when the menu volume icon is clicked to un-mute. Not persisted.
    private var volumeBeforeMute: Float = 1.0

    init() {
        if UserDefaults.standard.object(forKey: Self.volumeKey) != nil {
            volume = Float(UserDefaults.standard.double(forKey: Self.volumeKey))
        }
    }

    /// The `speaker.wave.*` glyph for a level, matching the macOS Music app's steps.
    nonisolated static func volumeSymbol(for volume: Float) -> String {
        guard volume > 0 else { return "speaker.slash.fill" }
        switch volume {
        case ...0.25: return "speaker.wave.1.fill"
        case ...0.5:  return "speaker.wave.2.fill"
        default:      return "speaker.wave.3.fill"
        }
    }

    var volumeSymbol: String { Self.volumeSymbol(for: volume) }

    /// Menu volume-icon click: mute when there's sound, otherwise restore the pre-mute
    /// level — falling back to full if that was also zero (0% → 100%).
    func toggleMute() {
        if volume > 0 {
            volumeBeforeMute = volume
            volume = 0
        } else {
            volume = volumeBeforeMute > 0 ? volumeBeforeMute : 1
        }
    }

    /// Enabled mixtapes, in panel order. Media-key next/previous cycle through the
    /// two live channels and then these. Kept current by `AppDelegate`.
    var mixtapeStations: [Mixtape] = []

    /// The Firestore-sourced show currently airing on the playing mixtape — `nil` for
    /// live channels, and reset on every `play()` so a stale title from the previous
    /// mixtape never lingers. Kept current by `AppDelegate` from `MixtapeNowPlayingService`.
    @Published var currentMixtapeNowPlaying: MixtapeNowPlaying?

    private var player: AVPlayer?
    private var timeControlObserver: NSKeyValueObservation?
    private var itemStatusObserver: NSKeyValueObservation?
    private var artworkTask: Task<Void, Never>?
    private var fadeTask: Task<Void, Never>?
    // Keeps the last broadcast so media key play can restore context
    private var lastBroadcast: Broadcast?
    private var lastItem: PlayingItem?

    // Stream watchdog: exponential-backoff reconnects, plus a stall timer for the case
    // where the stream never errors but just sits in "buffering" forever.
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 3
    private let stallTimeout: Duration = .seconds(15)
    private var reconnectTask: Task<Void, Never>?
    private var stallTask: Task<Void, Never>?

    func setup() {
        #if os(macOS)
        setupRemoteCommands()
        #endif
    }

    func toggle(channel: RadioChannel, broadcast: Broadcast? = nil) {
        toggle(.channel(channel), broadcast: broadcast)
    }

    func toggle(mixtape: Mixtape) {
        toggle(.mixtape(mixtape))
    }

    func toggle(_ item: PlayingItem, broadcast: Broadcast? = nil) {
        if playing == item {
            Log.player.log("toggle: stopping \(item.label, privacy: .public)")
            fadeOutAndStop()
        } else {
            Log.player.log("toggle: switching to \(item.label, privacy: .public)")
            fadeOutAndStop { [weak self] in
                self?.play(item, broadcast: broadcast)
            }
        }
    }

    /// Fades volume to zero over ~300 ms then stops. Calls `completion` when done.
    /// Used for user-initiated stops and app quit. `stop()` remains immediate for internal use.
    func fadeOutAndStop(completion: (@MainActor () -> Void)? = nil) {
        guard let p = player else { stop(); completion?(); return }
        fadeTask?.cancel()
        let startVolume = p.volume
        fadeTask = Task { @MainActor [weak self] in
            for i in stride(from: 11, through: 0, by: -1) {
                guard !Task.isCancelled else { break }
                p.volume = startVolume * Float(i) / 12
                try? await Task.sleep(for: .milliseconds(25))
            }
            self?.stop()
            completion?()
        }
    }

    func stop() {
        fadeTask?.cancel()
        fadeTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        stallTask?.cancel()
        stallTask = nil
        player?.pause()
        timeControlObserver?.invalidate()
        timeControlObserver = nil
        itemStatusObserver?.invalidate()
        itemStatusObserver = nil
        player = nil
        playing = nil
        isBuffering = false
        currentMixtapeNowPlaying = nil
        artworkTask?.cancel()
        artworkTask = nil
        #if os(macOS)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
        #endif
    }

    /// Re-attempts the last stream the user asked for. Used by the panel's "playback stopped" retry.
    func retryLastStream() {
        guard let item = lastItem ?? playing else { return }
        Log.player.notice("Manual retry of \(item.label, privacy: .public)")
        play(item, broadcast: lastBroadcast)
    }

    func play(channel: RadioChannel, broadcast: Broadcast? = nil, isReconnect: Bool = false) {
        play(.channel(channel), broadcast: broadcast, isReconnect: isReconnect)
    }

    /// `isReconnect` keeps the watchdog's attempt counter across an automatic retry;
    /// a user-initiated play resets it.
    func play(_ item: PlayingItem, broadcast: Broadcast? = nil, isReconnect: Bool = false) {
        stop()
        streamFailed = false
        if !isReconnect {
            reconnectAttempts = 0
            Log.player.notice("Play \(item.label, privacy: .public)")
        }

        let avItem = AVPlayerItem(url: item.streamURL)
        let newPlayer = AVPlayer(playerItem: avItem)
        newPlayer.volume = volume
        player = newPlayer
        playing = item
        isBuffering = true
        lastItem = item
        lastBroadcast = broadcast

        timeControlObserver = newPlayer.observe(\.timeControlStatus, options: [.new]) { [weak self] p, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isBuffering = p.timeControlStatus == .waitingToPlayAtSpecifiedRate
                switch p.timeControlStatus {
                case .playing:
                    if self.reconnectAttempts > 0 {
                        Log.player.notice("Stream recovered after \(self.reconnectAttempts) attempt(s)")
                    }
                    self.reconnectAttempts = 0
                    self.streamFailed = false
                    self.stallTask?.cancel()
                    self.stallTask = nil
                case .waitingToPlayAtSpecifiedRate:
                    self.startStallWatchdog()
                default:
                    break
                }
            }
        }

        itemStatusObserver = avItem.observe(\.status, options: [.new]) { [weak self] playerItem, _ in
            guard playerItem.status == .failed else { return }
            let message = playerItem.error?.localizedDescription ?? "unknown error"
            Task { @MainActor [weak self] in
                self?.handleStreamProblem("item failed: \(message)")
            }
        }

        newPlayer.play()

        #if os(macOS)
        updateNowPlaying(item: item, broadcast: broadcast)
        #endif
    }

    /// Fires if the stream sits in "buffering" for `stallTimeout` without ever erroring —
    /// otherwise it would show "buffering" forever.
    private func startStallWatchdog() {
        stallTask?.cancel()
        stallTask = Task { [weak self] in
            try? await Task.sleep(for: self?.stallTimeout ?? .seconds(15))
            guard let self, !Task.isCancelled, self.isBuffering, self.playing != nil else { return }
            self.handleStreamProblem("stalled while buffering")
        }
    }

    /// Reconnect with exponential backoff (2 s, 4 s, 8 s); give up into `streamFailed`
    /// after `maxReconnectAttempts`.
    private func handleStreamProblem(_ reason: String) {
        guard playing != nil, let item = lastItem else { return }
        reconnectTask?.cancel()
        stallTask?.cancel()
        stallTask = nil
        reconnectAttempts += 1

        guard reconnectAttempts <= maxReconnectAttempts else {
            Log.player.error("Stream gave up after \(self.maxReconnectAttempts) attempts — \(reason, privacy: .public)")
            stop()
            streamFailed = true
            return
        }

        let delay = min(20.0, pow(2.0, Double(reconnectAttempts - 1)) * 2)
        Log.player.notice("Stream problem (\(reason, privacy: .public)) — reconnect \(self.reconnectAttempts)/\(self.maxReconnectAttempts) in \(Int(delay)) s")
        let broadcast = lastBroadcast
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled, self.playing != nil else { return }
            self.play(item, broadcast: broadcast, isReconnect: true)
        }
    }

    #if os(macOS)
    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        // MPRemoteCommandCenter fires on an unspecified thread.
        // Dispatch to MainActor before touching any @MainActor-isolated state.
        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.playing != nil {
                    self.fadeOutAndStop()
                } else {
                    self.play(self.lastItem ?? .channel(.one), broadcast: self.lastBroadcast)
                }
            }
            return .success
        }

        center.playCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.play(self.playing ?? self.lastItem ?? .channel(.one),
                          broadcast: self.lastBroadcast)
            }
            return .success
        }

        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.stop() }
            return .success
        }

        center.nextTrackCommand.isEnabled = true
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.cycleStation(by: 1) }
            return .success
        }

        center.previousTrackCommand.isEnabled = true
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.cycleStation(by: -1) }
            return .success
        }
    }

    /// The full media-key rotation: NTS 1, NTS 2, then the enabled mixtapes.
    private var allStations: [PlayingItem] {
        [.channel(.one), .channel(.two)] + mixtapeStations.map(PlayingItem.mixtape)
    }

    private func cycleStation(by delta: Int) {
        let stations = allStations
        guard !stations.isEmpty else { return }
        let current = playing ?? lastItem
        let index = current.flatMap { stations.firstIndex(of: $0) } ?? 0
        let target = stations[(index + delta + stations.count) % stations.count]
        play(target)
    }

    func updateNowPlaying(item: PlayingItem, broadcast: Broadcast?) {
        let artist: String
        switch item {
        case .channel(let c): artist = c.label
        case .mixtape: artist = "Infinite Mixtape"
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: broadcast?.title ?? item.label,
            MPMediaItemPropertyArtist: artist,
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: 1.0,
        ]
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = .playing

        // Fetch artwork asynchronously; cancel any previous fetch first.
        artworkTask?.cancel()
        let artworkURL: URL? = {
            switch item {
            case .channel: return broadcast?.artworkURL
            case .mixtape(let m): return m.artworkURL ?? broadcast?.artworkURL
            }
        }()
        guard let artworkURL else { return }
        artworkTask = Task { [weak self, item] in
            guard let (data, _) = try? await URLSession.shared.data(from: artworkURL),
                  !Task.isCancelled,
                  let image = NSImage(data: data),
                  self?.playing == item else { return }
            let artwork = MPMediaItemArtwork(boundsSize: CGSize(width: 600, height: 600)) { _ in image }
            info[MPMediaItemPropertyArtwork] = artwork
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        }
    }

    /// Called by `AppDelegate` as `MixtapeNowPlayingService` resolves the show currently
    /// airing on `mixtape`. Patches the already-published `MPNowPlayingInfo` in place —
    /// swapping the generic mixtape name for the real show title, mixtape name moving to
    /// the artist line — rather than restarting playback.
    func setMixtapeNowPlaying(_ nowPlaying: MixtapeNowPlaying?, for mixtape: Mixtape) {
        guard playing == .mixtape(mixtape) else { return }
        currentMixtapeNowPlaying = nowPlaying
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPMediaItemPropertyTitle] = nowPlaying?.title ?? mixtape.title
        info[MPMediaItemPropertyArtist] = mixtape.title
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
    #endif
}
