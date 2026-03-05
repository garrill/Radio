import SwiftUI

@main
struct RadioApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif

    var body: some Scene {
        #if os(macOS)
        // Settings scene keeps the app alive without a dock window.
        // LSUIElement=true in Info.plist hides the dock icon.
        Settings { EmptyView() }
        #else
        WindowGroup {
            Text("NTS Radio requires macOS")
        }
        #endif
    }
}
