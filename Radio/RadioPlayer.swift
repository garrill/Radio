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

@MainActor
class RadioPlayer: ObservableObject {
    @Published var playingChannel: RadioChannel?
    @Published var isBuffering = false
    @Published var isPanelVisible = false
    /// Set when a stream fails and the one automatic retry is also exhausted. Survives `stop()`
    /// so the panel can show a "playback stopped" state; cleared when playback next starts.
    @Published var streamFailed = false

    private var player: AVPlayer?
    private var timeControlObserver: NSKeyValueObservation?
    private var itemStatusObserver: NSKeyValueObservation?
    private var artworkTask: Task<Void, Never>?
    private var fadeTask: Task<Void, Never>?
    // Keeps the last broadcast so media key play can restore context
    private var lastBroadcast: Broadcast?
    private var lastChannel: RadioChannel?

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
        if playingChannel == channel {
            Log.player.log("toggle: stopping \(channel.label, privacy: .public)")
            fadeOutAndStop()
        } else {
            Log.player.log("toggle: switching to \(channel.label, privacy: .public)")
            fadeOutAndStop { [weak self] in
                self?.play(channel: channel, broadcast: broadcast)
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
        playingChannel = nil
        isBuffering = false
        artworkTask?.cancel()
        artworkTask = nil
        #if os(macOS)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
        #endif
    }

    /// Re-attempts the last stream the user asked for. Used by the panel's "playback stopped" retry.
    func retryLastStream() {
        guard let channel = lastChannel ?? playingChannel else { return }
        Log.player.notice("Manual retry of \(channel.label, privacy: .public)")
        play(channel: channel, broadcast: lastBroadcast)
    }

    /// `isReconnect` keeps the watchdog's attempt counter across an automatic retry;
    /// a user-initiated play resets it.
    func play(channel: RadioChannel, broadcast: Broadcast? = nil, isReconnect: Bool = false) {
        stop()
        streamFailed = false
        if !isReconnect {
            reconnectAttempts = 0
            Log.player.notice("Play \(channel.label, privacy: .public)")
        }

        let item = AVPlayerItem(url: channel.streamURL)
        let newPlayer = AVPlayer(playerItem: item)
        player = newPlayer
        playingChannel = channel
        isBuffering = true
        lastChannel = channel
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

        itemStatusObserver = item.observe(\.status, options: [.new]) { [weak self] playerItem, _ in
            guard playerItem.status == .failed else { return }
            let message = playerItem.error?.localizedDescription ?? "unknown error"
            Task { @MainActor [weak self] in
                self?.handleStreamProblem("item failed: \(message)")
            }
        }

        newPlayer.play()

        #if os(macOS)
        updateNowPlaying(channel: channel, broadcast: broadcast)
        #endif
    }

    /// Fires if the stream sits in "buffering" for `stallTimeout` without ever erroring —
    /// otherwise it would show "buffering" forever.
    private func startStallWatchdog() {
        stallTask?.cancel()
        stallTask = Task { [weak self] in
            try? await Task.sleep(for: self?.stallTimeout ?? .seconds(15))
            guard let self, !Task.isCancelled, self.isBuffering, self.playingChannel != nil else { return }
            self.handleStreamProblem("stalled while buffering")
        }
    }

    /// Reconnect with exponential backoff (2 s, 4 s, 8 s); give up into `streamFailed`
    /// after `maxReconnectAttempts`.
    private func handleStreamProblem(_ reason: String) {
        guard playingChannel != nil, let channel = lastChannel else { return }
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
            guard let self, !Task.isCancelled, self.playingChannel != nil else { return }
            self.play(channel: channel, broadcast: broadcast, isReconnect: true)
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
                if self.playingChannel != nil {
                    self.fadeOutAndStop()
                } else {
                    self.play(channel: self.lastChannel ?? .one, broadcast: self.lastBroadcast)
                }
            }
            return .success
        }

        center.playCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.play(channel: self.playingChannel ?? self.lastChannel ?? .one,
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
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.play(channel: (self.playingChannel ?? .one).next)
            }
            return .success
        }

        center.previousTrackCommand.isEnabled = true
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.play(channel: (self.playingChannel ?? .two).previous)
            }
            return .success
        }
    }

    func updateNowPlaying(channel: RadioChannel, broadcast: Broadcast?) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: broadcast?.title ?? channel.label,
            MPMediaItemPropertyArtist: channel.label,
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: 1.0,
        ]
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = .playing

        // Fetch artwork asynchronously; cancel any previous fetch first.
        artworkTask?.cancel()
        guard let artworkURL = broadcast?.artworkURL else { return }
        artworkTask = Task { [weak self, channel] in
            guard let (data, _) = try? await URLSession.shared.data(from: artworkURL),
                  !Task.isCancelled,
                  let image = NSImage(data: data),
                  self?.playingChannel == channel else { return }
            let artwork = MPMediaItemArtwork(boundsSize: CGSize(width: 600, height: 600)) { _ in image }
            info[MPMediaItemPropertyArtwork] = artwork
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        }
    }
    #endif
}
