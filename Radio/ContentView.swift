import SwiftUI
#if os(macOS)
import AppKit
#endif

struct ContentView: View {
    @EnvironmentObject var player: RadioPlayer
    @EnvironmentObject var ntsService: NTSService

    @State private var pulseOpacity: Double = 1.0
    @AppStorage("chatroomLinkType") private var chatroomLinkType = "web"

    var body: some View {
        VStack(spacing: 0) {
            if ntsService.isOffline {
                HStack(spacing: 6) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 11))
                    Text("No internet connection")
                        .font(.system(size: 12))
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                Divider()
            }

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
                if chatroomLinkType != "hidden" {
                    MenuRowButton(icon: "bubble.left", label: "Chatroom") {
                        openChatroom()
                    }
                }
                #if os(macOS)
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
        .padding(24) // Room for shadow to render beyond panel edge
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

#Preview {
    ContentView()
        .environmentObject(RadioPlayer())
        .environmentObject(NTSService())
}
