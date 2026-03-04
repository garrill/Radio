import SwiftUI
#if os(macOS)
import AppKit
#endif

struct ContentView: View {
    @EnvironmentObject var player: RadioPlayer
    @EnvironmentObject var ntsService: NTSService

    var body: some View {
        VStack(spacing: 0) {
            if ntsService.isLoading {
                loadingView
            } else {
                channelList
            }

            Divider()
            VStack(spacing: 0) {
                MenuRowButton(icon: "arrow.clockwise", label: "Refresh") {
                    ntsService.fetch()
                }
                MenuRowButton(icon: "bubble.left", label: "Chatroom") {
                    openChatroom()
                }
                MenuRowButton(icon: "xmark.square", label: "Quit Radio") {
                    #if os(macOS)
                    NSApplication.shared.terminate(nil)
                    #endif
                }
            }
            .padding(.vertical, 4)
        }
        .frame(width: 348)
        .onAppear {
            ntsService.startPolling()
            player.setup()
        }
        .onDisappear { ntsService.stopPolling() }
    }

    private func openChatroom() {
        #if os(macOS)
        // Try Discord app first via custom scheme, fall back to browser
        let appURL = URL(string: "discord://discord.com/channels/909834111592591421/933364043459227708")!
        let webURL = URL(string: "https://discord.com/channels/909834111592591421/933364043459227708")!
        if !NSWorkspace.shared.open(appURL) {
            NSWorkspace.shared.open(webURL)
        }
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

    private var isPlaying: Bool { player.playingChannel == channel }
    private var isBuffering: Bool { player.isBuffering && isPlaying }

    // Use effective broadcast so the UI stays current even when the API lags
    private var currentBroadcast: Broadcast? { data?.effectiveNow }
    private var nextBroadcast: Broadcast? { data?.effectiveNext }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                artworkView

                VStack(alignment: .leading, spacing: 4) {
                    channelBadge

                    if let broadcast = currentBroadcast {
                        Text(broadcast.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Loading…")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                }

                Spacer(minLength: 0)

                playButton
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)

            if let broadcast = currentBroadcast {
                progressBar(for: broadcast)
            }

            bottomRow
        }
    }

    // MARK: Artwork

    private var artworkView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9)
                .fill(.secondary.opacity(0.12))
                .frame(width: 72, height: 72)

            if let url = currentBroadcast?.artworkURL {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    }
                }
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 9))
            }

            if isPlaying {
                RoundedRectangle(cornerRadius: 9)
                    .fill(.black.opacity(0.35))
                    .frame(width: 72, height: 72)

                if isBuffering {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    WaveformView()
                        .frame(width: 22, height: 18)
                        .foregroundStyle(.white)
                }
            }
        }
        .onTapGesture {
            player.toggle(channel: channel, broadcast: currentBroadcast)
        }
    }

    // MARK: Channel Badge

    private var channelBadge: some View {
        Text(channel.label)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.secondary.opacity(0.12), in: Capsule())
    }

    // MARK: Play Button

    private var playButton: some View {
        Button {
            player.toggle(channel: channel, broadcast: currentBroadcast)
        } label: {
            ZStack {
                Circle()
                    .fill(isPlaying ? Color.accentColor : Color.primary.opacity(0.08))
                    .frame(width: 36, height: 36)

                Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isPlaying ? .white : .primary)
                    .offset(x: isPlaying ? 0 : 1)
            }
        }
        .buttonStyle(.plain)
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

    // MARK: Bottom Row (up next + tracklist link)

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
            } else {
                Spacer()
            }

            Spacer(minLength: 8)

            Button {
                #if os(macOS)
                TracklistWindowManager.shared.open(channel: channel)
                #endif
            } label: {
                HStack(spacing: 3) {
                    Text("Tracklist")
                        .font(.system(size: 11))
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 10))
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
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
                    .font(.system(size: 13))
                    .frame(width: 16)
                Text(label)
                    .font(.system(size: 13))
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
