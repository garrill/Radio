#if os(macOS)
import AppKit

enum Feedback {
    /// Opens a new GitHub issue with the app version, build, and OS version pre-filled,
    /// so a beta tester's report always carries the context needed to act on it.
    static func report() {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersionString

        let body = """


        ---
        Radio \(version) (\(build)) · \(os)
        """

        var components = URLComponents(string: "https://github.com/garrill/Radio/issues/new")!
        components.queryItems = [URLQueryItem(name: "body", value: body)]
        guard let url = components.url else { return }
        NSWorkspace.shared.open(url)
    }
}
#endif
