#if os(macOS)
import Foundation
import MetricKit
import OSLog

/// Subscribes to MetricKit. Crash / hang / CPU-exception reports get summarised in the
/// log and the full payload saved under Application Support, so a tester's "Report a
/// Problem" has something concrete to attach. Payloads arrive up to ~24 h after the
/// incident (typically on the next launch), so this is a safety net, not live telemetry.
final class DiagnosticsMonitor: NSObject, MXMetricManagerSubscriber {
    static let shared = DiagnosticsMonitor()

    func start() {
        MXMetricManager.shared.add(self)
    }

    private var diagnosticsDirectory: URL? {
        guard let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("Radio/Diagnostics", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: MXMetricManagerSubscriber

    func didReceive(_ payloads: [MXMetricPayload]) {
        Log.diagnostics.debug("Received \(payloads.count) metric payload(s)")
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            for crash in payload.crashDiagnostics ?? [] {
                Log.diagnostics.fault("""
                CRASH exceptionType=\(crash.exceptionType?.stringValue ?? "?", privacy: .public) \
                code=\(crash.exceptionCode?.stringValue ?? "?", privacy: .public) \
                signal=\(crash.signal?.stringValue ?? "?", privacy: .public) \
                reason=\(crash.terminationReason ?? "—", privacy: .public) \
                build=\(crash.metaData.applicationBuildVersion, privacy: .public)
                """)
            }
            for hang in payload.hangDiagnostics ?? [] {
                Log.diagnostics.error("HANG \(hang.hangDuration.description, privacy: .public) build=\(hang.metaData.applicationBuildVersion, privacy: .public)")
            }
            for cpu in payload.cpuExceptionDiagnostics ?? [] {
                Log.diagnostics.error("CPU exception totalCPUTime=\(cpu.totalCPUTime.description, privacy: .public)")
            }
            save(payload)
        }
    }

    private func save(_ payload: MXDiagnosticPayload) {
        guard let dir = diagnosticsDirectory else { return }
        let stamp = ISO8601DateFormatter().string(from: payload.timeStampEnd)
            .replacingOccurrences(of: ":", with: "-")
        let url = dir.appendingPathComponent("diagnostic-\(stamp).json")
        do {
            try payload.jsonRepresentation().write(to: url)
            Log.diagnostics.notice("Saved diagnostic payload to \(url.path, privacy: .public)")
        } catch {
            Log.diagnostics.error("Could not save diagnostic payload: \(error.localizedDescription, privacy: .public)")
        }
    }
}
#endif
