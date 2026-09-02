import SwiftUI
#if os(macOS)
import AppKit
#endif

struct ChannelRow: View {
    let channel: RadioChannel
    let data: ChannelData?

    @EnvironmentObject var player: RadioPlayer
    @AppStorage("showTracklisting") private var showTracklisting = true
    @AppStorage("artworkSize") private var artworkSize = ArtworkSize.medium

    private var artworkDimension: CGFloat { artworkSize.dimension }

    @State private var isHovered = false
    @State private var isTracklistHovered = false
    @State private var isBottomHovered = false
    // Stable anchor for the progress TimelineView. `from: .now` re-evaluated every
    // render churns SwiftUI's UpdateFilter (~25% idle CPU with the panel open).
    @State private var timelineAnchor = Date()

    private var isPlaying: Bool { player.playingChannel == channel }
    private var isBuffering: Bool { player.isBuffering && isPlaying }
    private var currentBroadcast: Broadcast? { data?.effectiveNow }
    private var nextBroadcast: Broadcast? { data?.effectiveNext }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                artworkView

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 0) {
                        channelBadge
                        Spacer()
                        if showTracklisting && artworkSize != .large { tracklistButton }
                    }

                    if let broadcast = currentBroadcast {
                        Text(broadcast.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(3)
                            .padding(.leading, 2)
                    } else {
                        Text("Loading…")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 2)
                    }

                    Spacer(minLength: 0)

                    if showTracklisting && artworkSize == .large { tracklistButton }
                }
                .frame(height: artworkDimension)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)

            if let broadcast = currentBroadcast {
                progressBar(for: broadcast)
            } else {
                Color.clear.frame(height: 27)
            }

            if nextBroadcast != nil {
                bottomRow
            } else {
                Color.clear.frame(height: 24)
            }
        }
        .onHover { isHovered = $0 }
        .contentShape(Rectangle())
        .onTapGesture {
            player.toggle(channel: channel, broadcast: currentBroadcast)
        }
    }

    // MARK: Artwork

    private var artworkView: some View {
        ZStack {
            Rectangle()
                .fill(.secondary.opacity(0.12))
                .frame(width: artworkDimension, height: artworkDimension)

            if let url = currentBroadcast?.artworkURL {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    }
                }
                .frame(width: artworkDimension, height: artworkDimension)
            }

            // Dark scrim whenever there's an overlay to show
            if isBuffering || isPlaying || isHovered {
                Rectangle()
                    .fill(.black.opacity(0.45))
                    .frame(width: artworkDimension, height: artworkDimension)
            }

            if isBuffering {
                // 2 stacked spinners to make them translucent, effectively having an opacity value of 2.
                // This is the only way i have found to make the spinners less translucent
                // only change this if you are 100% sure your method works
                ZStack {
                    ProgressView()
                        .controlSize(.small)
                        .colorScheme(.dark)
                    ProgressView()
                        .controlSize(.small)
                        .colorScheme(.dark)
                 }
            } else if isPlaying && isHovered {
                Image(systemName: "stop.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
            } else if isPlaying && player.isPanelVisible {
                WaveformView()
                    .frame(width: 22, height: 18)
                    .foregroundStyle(.white)
            } else if isHovered {
                Image(systemName: "play.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .offset(x: 1.5)
            }
        }
        .frame(width: artworkDimension, height: artworkDimension)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .animation(.easeInOut(duration: 0.12), value: isPlaying)
        .animation(.easeInOut(duration: 0.12), value: isBuffering)
    }

    // MARK: Channel Badge

    private var channelBadge: some View {
        HStack(spacing: 2) {
            if currentBroadcast?.isRepeat == true {
                Image(systemName: "repeat")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            } else {
                LiveIndicator(isActive: player.isPanelVisible)
            }

            Image(systemName: channel.menuBarSymbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(.leading, 2)

            if let location = currentBroadcast?.location {
                MarqueeText(text: location, maxWidth: 60, isActive: player.isPanelVisible)
                    .fontWidth(.condensed)
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 8)
        .padding(.vertical, 2)
        .background(.secondary.opacity(0.3), in: Capsule())
    }

    // MARK: Tracklist Button

    private var tracklistButton: some View {
        Button {
            #if os(macOS)
            TracklistWindowManager.shared.open(channel: channel)
            #endif
        } label: {
            HStack(spacing: 3) {
                Text("Tracklist")
                    .font(.system(size: 10))
                    .lineLimit(1)
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 9))
            }
            .fixedSize()
            .foregroundStyle(isTracklistHovered ? Color.primary : Color.secondary)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { isTracklistHovered = $0 }
    }

    // MARK: Progress Bar

    private func progressBar(for broadcast: Broadcast) -> some View {
        // Only tick the TimelineView while the panel is visible — avoids
        // waking the SwiftUI render tree every 20 s in the background.
        Group {
            if player.isPanelVisible {
                TimelineView(.periodic(from: timelineAnchor, by: 20)) { _ in
                    progressBarContent(for: broadcast)
                }
            } else {
                progressBarContent(for: broadcast)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    private func progressBarContent(for broadcast: Broadcast) -> some View {
        VStack(spacing: 3) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.secondary.opacity(0.15))
                        .frame(height: 3)
                    Capsule()
                        .fill(isPlaying ? Color.accentColor : Color.secondary.opacity(0.45))
                        .frame(width: geo.size.width * broadcast.progress, height: 3)
                }
            }
            .frame(height: 3)

            HStack {
                Text(broadcast.formattedTime(broadcast.startDate))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                Spacer()
                Text(broadcast.formattedTime(broadcast.endDate))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
    }

    // MARK: Bottom Row

    private var bottomRow: some View {
        HStack(spacing: 5) {
            if let next = nextBroadcast {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                Text("Up next")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
                NextBroadcastMarquee(broadcast: next, isHovered: isBottomHovered, maxWidth: 185, isActive: player.isPanelVisible)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
        .onHover { isBottomHovered = $0 }
    }
}
