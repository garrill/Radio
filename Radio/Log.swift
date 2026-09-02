import OSLog

/// Central `os.Logger` categories. Read a tester's dump with:
///   log show --predicate 'subsystem == "com.garrill.Radio"' --last 1h --info --debug
///
/// Interpolated values are `.public` only where they carry no user content — NTS data
/// is public anyway, but keep payload dumps to a truncated prefix.
enum Log {
    private static let subsystem = "com.garrill.Radio"

    static let lifecycle = Logger(subsystem: subsystem, category: "lifecycle")
    static let player = Logger(subsystem: subsystem, category: "player")
    static let service = Logger(subsystem: subsystem, category: "service")
    static let tracklist = Logger(subsystem: subsystem, category: "tracklist")
    static let updates = Logger(subsystem: subsystem, category: "updates")
    static let loginItem = Logger(subsystem: subsystem, category: "loginitem")
    static let diagnostics = Logger(subsystem: subsystem, category: "diagnostics")
}
