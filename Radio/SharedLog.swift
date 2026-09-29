import Foundation
import OSLog

/// Bridges log lines from the widget extension process into the main app's debug-panel export.
///
/// The widget extension runs as its own OS process, so `OSLogStore(scope: .currentProcessIdentifier)`
/// in `LogExport` (which only sees entries the *current* process emitted) never picks up anything the
/// widget logs. This appends the same lines to a small file in the shared App Group container, which
/// `LogExport` reads back and merges in alongside the app's own unified-log entries.
enum SharedLog {
    private static let appGroupID = "group.com.garrill.Radio"
    private static let fileName = "widget-log.txt"
    private static let maxBytes = 64 * 1024
    private static let queue = DispatchQueue(label: "com.garrill.Radio.sharedlog")

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(fileName)
    }

    /// Logs to the unified log via `logger` and appends the same line to the shared file.
    static func log(_ logger: Logger, _ message: String, category: String) {
        logger.log("\(message, privacy: .public)")
        append("[\(category)] \(message)")
    }

    static func error(_ logger: Logger, _ message: String, category: String) {
        logger.error("\(message, privacy: .public)")
        append("[\(category)] ERROR: \(message)")
    }

    /// Reads back accumulated cross-process lines for the debug-panel export, oldest first.
    static func readLines() -> [String] {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return []
        }
        return text.split(separator: "\n").map(String.init)
    }

    private static func append(_ line: String) {
        queue.sync {
            guard let url = fileURL else { return }
            let stamped = Data("\(stamp.string(from: Date()))  \(line)\n".utf8)
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                handle.seekToEndOfFile()
                handle.write(stamped)
            } else {
                try? stamped.write(to: url)
            }
            trimIfNeeded(url)
        }
    }

    /// Keeps the shared file from growing unbounded across widget refresh cycles.
    private static func trimIfNeeded(_ url: URL) {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int, size > maxBytes,
              let data = try? Data(contentsOf: url) else { return }
        try? data.suffix(maxBytes / 2).write(to: url)
    }
}
