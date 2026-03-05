import SwiftUI
#if os(macOS)
import AppKit
#endif

struct ContentView: View {
    @EnvironmentObject var player: RadioPlayer
    @EnvironmentObject var ntsService: NTSService

    @State private var pulseOpacity: Double = 1.0

    var body: some View {
        VStack(spacing: 0) {
            if ntsService.isLoading {
                loadingView
            } else {
                channelList
                    .opacity(pulseOpacity)
                    .onChange(of: ntsService.isRefreshing) { _, refreshing in
                        if refreshing {
                            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                                pulseOpacity = 0.35
                            }
                        } else {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                pulseOpacity = 1.0
                            }
                        }
                    }
            }

            Divider()
            VStack(spacing: 0) {
                MenuRowButton(icon: "arrow.clockwise", label: "Refresh") {
                    ntsService.fetchManual()
                }
                MenuRowButton(icon: "bubble.left", label: "Chatroom") {
                    openChatroom()
                }
                MenuRowButton(icon: "xmark.rectangle", label: "Quit Radio") {
                    #if os(macOS)
                    NSApplication.shared.terminate(nil)
                    #endif
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 4) // Extra bottom padding prevents corner-radius clipping
            
        }
        .frame(width: 280)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private func openChatroom() {
        #if os(macOS)
        let url = URL(string: "https://discord.com/channels/909834111592591421/933364043459227708")!
        NSWorkspace.shared.open(url)
        #endif
    }

    // MARK: - Channel List

    private var channelList: some View {
        VStack(spacing: 0) {
            ForEach(RadioChannel.allCases.indices, id: \.self) { index in
                let channel = RadioChannel.allCases[index]
                let channelData = ntsService.channels.first {
                    $0.channelName == "\(channel.rawValue)"
                }
                ChannelRow(channel: channel, data: channelData)

                if index < RadioChannel.allCases.count - 1 {
                    Divider()
                        .padding(.horizontal, 14)
                }
            }
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Connecting…")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(height: 140)
    }
}

// MARK: - Channel Row

struct ChannelRow: View {
    let channel: RadioChannel
    let data: ChannelData?

    @EnvironmentObject var player: RadioPlayer
    @State private var isHovered = false
    @State private var isTracklistHovered = false

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
                        tracklistButton
                    }

                    if let broadcast = currentBroadcast {
                        Text(broadcast.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.leading, 2)
                    } else {
                        Text("Loading…")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 2)
                    }

                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)

            if let broadcast = currentBroadcast {
                progressBar(for: broadcast)
            }

            if nextBroadcast != nil {
                bottomRow
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
                .frame(width: 80, height: 80)

            if let url = currentBroadcast?.artworkURL {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    }
                }
                .frame(width: 80, height: 80)
            }

            // Dark scrim whenever there's an overlay to show
            if isBuffering || isPlaying || isHovered {
                Rectangle()
                    .fill(.black.opacity(0.45))
                    .frame(width: 80, height: 80)
            }

            if isBuffering {
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
            } else if isPlaying {
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
        .frame(width: 80, height: 80)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture {
            player.toggle(channel: channel, broadcast: currentBroadcast)
        }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .animation(.easeInOut(duration: 0.12), value: isPlaying)
        .animation(.easeInOut(duration: 0.12), value: isBuffering)
    }

    // MARK: Channel Badge

    private var channelBadge: some View {
        HStack(spacing: 2) {
            if currentBroadcast?.isRepeat == true {
                Image(systemName: "repeat.circle.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            } else {
                LiveIndicator()
            }
            

            Image(systemName: channel.menuBarSymbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(.leading, 2)

            if let location = currentBroadcast?.location {
                MarqueeText(text: location, maxWidth: 60)
                    .fontWidth(.condensed)
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 8)
        .padding(.vertical, 2)
        .background(.secondary.opacity(0.15), in: Capsule())
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
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    // MARK: Bottom Row

    private var bottomRow: some View {
        HStack(alignment: .center) {
            if let next = nextBroadcast {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                    Text("Up next")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                    Text(next.title)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }
}

// MARK: - Menu Row Button

struct MenuRowButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .frame(width: 14)
                Text(label)
                    .font(.system(size: 12))
                Spacer()
            }
            .foregroundStyle(isHovered ? Color.white : Color.primary)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isHovered ? Color.accentColor : Color.clear)
            )
            .padding(.horizontal, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Marquee Text

struct MarqueeText: View {
    let text: String
    let maxWidth: CGFloat

    @State private var animate = false
    @State private var naturalWidth: CGFloat = 0

    private var overflow: CGFloat { max(0, naturalWidth - maxWidth) }

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize()
            // Measure the actual SwiftUI-rendered width (respects fontWidth env, screen scale, etc.)
            .background(
                GeometryReader { geo in
                    Color.clear.onAppear { naturalWidth = geo.size.width }
                }
            )
            .offset(x: animate ? -overflow : 0)
            .frame(
                width: overflow > 1 ? maxWidth : naturalWidth > 0 ? naturalWidth : nil,
                alignment: .leading
            )
            .clipped()
            .task(id: overflow > 1) {
                guard overflow > 1 else {
                    animate = false
                    return
                }
                animate = false
                let duration = max(2.0, Double(overflow) / 20)
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(2))
                    withAnimation(.linear(duration: duration)) { animate = true }
                    try? await Task.sleep(for: .seconds(duration + 2))
                    withAnimation(.linear(duration: duration)) { animate = false }
                    try? await Task.sleep(for: .seconds(duration))
                }
            }
    }
}

// MARK: - Live Indicator

struct LiveIndicator: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.red.opacity(pulse ? 0.0 : 0.35))
                .frame(width: 8, height: 8)
                .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: pulse)
            Circle()
                .fill(Color.red)
                .frame(width: 5, height: 5)
        }
        .onAppear { pulse = true }
    }
}

// MARK: - Waveform Animation

struct WaveformView: View {
    @State private var phase = false

    private let heights: [[CGFloat]] = [
        [4, 14, 8, 12, 5],
        [10, 6, 14, 4, 12]
    ]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { i in
                Capsule()
                    .frame(width: 2.5, height: phase ? heights[1][i] : heights[0][i])
                    .animation(
                        .easeInOut(duration: 0.45)
                            .repeatForever()
                            .delay(Double(i) * 0.09),
                        value: phase
                    )
            }
        }
        .onAppear { phase = true }
    }
}

#Preview {
    ContentView()
        .environmentObject(RadioPlayer())
        .environmentObject(NTSService())
}
