#if os(macOS)
import Foundation
import OSLog

/// Reads the app's own unified-log entries back out via `OSLogStore` and writes
/// them to a plain-text file for the Settings ▸ Debug pane, so a beta tester can
/// save a dump and send it in. `.currentProcessIdentifier` scope needs no
/// entitlement and returns entries this process emitted since launch.
enum LogExport {
    static let subsystem = "com.garrill.Radio"

    struct Line {
        let date: Date
        let category: String
        let level: String
        let message: String

        var formatted: String {
            "\(Self.stamp.string(from: date))  \(level.padding(toLength: 6, withPad: " ", startingAt: 0))  [\(category)] \(message)"
        }

        private static let stamp: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "HH:mm:ss.SSS"
            return f
        }()
    }

    /// Writes a plain-text dump to `url`, with a header carrying app/OS version.
    static func write(to url: URL, maxAge: TimeInterval = 24 * 3600) throws {
        let lines = (try? fetch(since: Date().addingTimeInterval(-maxAge))) ?? []
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        var text = """
        Radio \(version) (\(build))
        macOS \(ProcessInfo.processInfo.operatingSystemVersionString)
        Exported \(ISO8601DateFormatter().string(from: Date()))
        Entries: \(lines.count)

        """
        text += lines.map(\.formatted).joined(separator: "\n")
        text += "\n"
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func fetch(since: Date) throws -> [Line] {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let position = store.position(date: since)
        let predicate = NSPredicate(format: "subsystem == %@", subsystem)
        return try store.getEntries(at: position, matching: predicate)
            .compactMap { $0 as? OSLogEntryLog }
            .map { Line(date: $0.date,
                        category: $0.category,
                        level: label(for: $0.level),
                        message: $0.composedMessage) }
    }

    private static func label(for level: OSLogEntryLog.Level) -> String {
        switch level {
        case .debug: "debug"
        case .info: "info"
        case .notice: "notice"
        case .error: "error"
        case .fault: "fault"
        case .undefined: "—"
        @unknown default: "?"
        }
    }
}
#endif
