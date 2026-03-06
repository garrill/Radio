import Foundation
import Combine
import AVFoundation
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

    private static let streamOneURL = URL(string: "http://stream-relay-geo.ntslive.net/stream")!
    private static let streamTwoURL = URL(string: "http://stream-relay-geo.ntslive.net/stream2")!

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

    private var player: AVPlayer?
    private var timeControlObserver: NSKeyValueObservation?
    private var itemStatusObserver: NSKeyValueObservation?
    private var artworkTask: Task<Void, Never>?
    // Keeps the last broadcast so media key play can restore context
    private var lastBroadcast: Broadcast?
    private var lastChannel: RadioChannel?

    func setup() {
        #if os(macOS)
        setupRemoteCommands()
        #endif
    }

    func toggle(channel: RadioChannel, broadcast: Broadcast? = nil) {
        if playingChannel == channel {
            stop()
        } else {
            play(channel: channel, broadcast: broadcast)
        }
    }

    func stop() {
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

    func play(channel: RadioChannel, broadcast: Broadcast? = nil) {
        stop()
        let item = AVPlayerItem(url: channel.streamURL)
        let newPlayer = AVPlayer(playerItem: item)
        player = newPlayer
        playingChannel = channel
        isBuffering = true
        lastChannel = channel
        lastBroadcast = broadcast

        timeControlObserver = newPlayer.observe(\.timeControlStatus, options: [.new]) { [weak self] p, _ in
            Task { @MainActor [weak self] in
                self?.isBuffering = p.timeControlStatus == .waitingToPlayAtSpecifiedRate
            }
        }

        // Stop cleanly if the stream item fails (network loss, bad URL, server error)
        itemStatusObserver = item.observe(\.status, options: [.new]) { [weak self] playerItem, _ in
            if playerItem.status == .failed {
                Task { @MainActor [weak self] in self?.stop() }
            }
        }

        newPlayer.play()

        #if os(macOS)
        updateNowPlaying(channel: channel, broadcast: broadcast)
        #endif
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
                    self.stop()
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
