#if os(macOS)
import Combine
import Sparkle

/// Owns the app's single `SPUStandardUpdaterController`. `AppDelegate` touches `shared` once at
/// launch to force its creation (which starts the updater). The panel's "Check for Updates"
/// row reaches the same instance here — SwiftUI has no menu-bar commands to hang it off, since
/// Radio ships no windows or main menu.
enum UpdaterHolder {
    static let shared = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    /// Kicks off a user-initiated update check. Wrapped so callers don't need `import Sparkle`.
    static func checkForUpdates() {
        shared.updater.checkForUpdates()
    }
}

/// Mirrors `SPUUpdater.canCheckForUpdates` into a `@Published` property so the "Check for
/// Updates" control can disable itself while a check is already running — Sparkle's recommended
/// SwiftUI pattern, since the updater isn't an `ObservableObject`.
final class CheckForUpdatesViewModel: ObservableObject {
    @Published private(set) var canCheckForUpdates = false

    init(updater: SPUUpdater = UpdaterHolder.shared.updater) {
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        UpdaterHolder.shared.updater.checkForUpdates()
    }
}
#endif
