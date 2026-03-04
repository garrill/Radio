import SwiftUI

@main
struct RadioApp: App {
    #if os(macOS)
    @StateObject private var player = RadioPlayer()
    @StateObject private var ntsService = NTSService()
    #endif

    var body: some Scene {
        #if os(macOS)
        MenuBarExtra {
            ContentView()
                .environmentObject(player)
                .environmentObject(ntsService)
        } label: {
            if let playing = player.playingChannel {
                Image(systemName: playing.menuBarSymbol)
            } else {
                Image("NTSLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 16)
            }
        }
        .menuBarExtraStyle(.window)
        #else
        WindowGroup {
            Text("NTS Radio requires macOS")
        }
        #endif
    }
}
