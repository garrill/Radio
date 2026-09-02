#if os(macOS)
import ServiceManagement
import OSLog

/// Thin wrapper over `SMAppService.mainApp` — "open Radio at login".
/// The status is owned by the system, so treat `isEnabled` as the source of truth
/// and reconcile any UI toggle against it.
enum LoginItem {
    private static let log = Log.loginItem

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Registers or unregisters the app as a login item. Returns whether the change took;
    /// on failure the caller should re-read `isEnabled` and reflect that.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            return true
        } catch {
            log.error("Could not \(enabled ? "enable" : "disable", privacy: .public) launch at login: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
#endif
