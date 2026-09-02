import SwiftUI
#if os(macOS)
import AppKit
#endif

struct ContentView: View {
    @EnvironmentObject var player: RadioPlayer
    @EnvironmentObject var ntsService: NTSService

    @State private var pulseOpacity: Double = 1.0
    @AppStorage("chatroomLinkType") private var chatroomLinkType = "web"
    @AppStorage("didSeeIntro") private var didSeeIntro = false
    #if os(macOS)
    @StateObject private var updaterVM = CheckForUpdatesViewModel()
    #endif

    var body: some View {
        VStack(spacing: 0) {
            topBanner

            if ntsService.isLoading {
                loadingView
            } else if ntsService.channels.isEmpty {
                loadErrorView
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
                MenuRowButton(icon: "macwindow", label: "Website") {
                    if let url = URL(string: "https://nts.live") {
                        #if os(macOS)
                        NSWorkspace.shared.open(url)
                        #else
                        UIApplication.shared.open(url)
                        #endif
                    }
                }
                if chatroomLinkType != "hidden" {
                    MenuRowButton(icon: "bubble.left", label: "Chatroom") {
                        openChatroom()
                    }
                }
                #if os(macOS)
                MenuRowButton(icon: "exclamationmark.bubble", label: "Report a Problem") {
                    Feedback.report()
                }
                MenuRowButton(icon: "arrow.down.circle", label: "Check for Updates") {
                    updaterVM.checkForUpdates()
                }
                .disabled(!updaterVM.canCheckForUpdates)
                SettingsMenuButton()
                #endif
                MenuRowButton(icon: "xmark.rectangle", label: "Quit Radio", isLast: true) {
                    #if os(macOS)
                    NSApplication.shared.terminate(nil)
                    #endif
                }
            }
            .padding(.top, 5)
            .padding(.bottom, 5) // Extra bottom padding prevents corner-radius clipping
        }
        .frame(width: 280)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
        .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 6)
        .overlay(alignment: .top) { introHint }
        .padding(24) // Room for shadow to render beyond panel edge
        .onChange(of: player.playingChannel) { _, channel in
            // Once they've started playback they've found the app — retire the intro hint.
            if channel != nil { didSeeIntro = true }
        }
    }

    // MARK: - Top Banner

    /// At most one of: offline notice, playback-failed notice, or the one-time intro hint.
    @ViewBuilder private var topBanner: some View {
        if ntsService.isOffline {
            bannerRow {
                Image(systemName: "wifi.slash").font(.system(size: 11))
                Text("No internet connection").font(.system(size: 12))
            }
        } else if player.streamFailed {
            bannerRow {
                Image(systemName: "exclamationmark.triangle").font(.system(size: 11))
                Text("Playback stopped").font(.system(size: 12))
                Button("Retry") { player.retryLastStream() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
        }
    }

    /// One-time hint on first launch, floated over the panel so it never disturbs the
    /// fixed panel height. Clears on first interaction or when playback starts.
    @ViewBuilder private var introHint: some View {
        if !didSeeIntro {
            HStack(spacing: 6) {
                Image(systemName: "hand.wave.fill").font(.system(size: 11))
                Text("Radio lives in your menu bar — click the icon any time")
                    .font(.system(size: 11))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: 240)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
            .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
            .padding(.top, 8)
            .transition(.opacity)
            .onTapGesture { withAnimation { didSeeIntro = true } }
        }
    }

    private func bannerRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) { content() }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            Divider()
        }
    }

    private func openChatroom() {
        #if os(macOS)
        let url: URL
        if chatroomLinkType == "app" {
            url = URL(string: "discord://discord.com/channels/909834111592591421/933364043459227708")!
        } else {
            url = URL(string: "https://discord.com/channels/909834111592591421/933364043459227708")!
        }
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
            }.padding(.top, 2)
        }
    }

    // MARK: - Loading / Error

    private var loadingView: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Connecting…")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(height: 140)
        .frame(maxWidth: .infinity)
    }

    /// Shown when a fetch has finished but there's still no schedule to display.
    private var loadErrorView: some View {
        VStack(spacing: 8) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
            Text(ntsService.isOffline ? "Schedule unavailable offline" : "Couldn't load the schedule")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Button("Try Again") { ntsService.fetchManual() }
                .controlSize(.small)
        }
        .frame(height: 140)
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    ContentView()
        .environmentObject(RadioPlayer())
        .environmentObject(NTSService())
}
