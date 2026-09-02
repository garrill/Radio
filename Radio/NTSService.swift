import Foundation
import Combine
import Network
import OSLog

@MainActor
class NTSService: ObservableObject {
    @Published var channels: [ChannelData] = []
    @Published var isLoading = false
    @Published var isRefreshing = false
    @Published var isOffline = false

    private var pollingTask: Task<Void, Never>?
    private var fetchTask: Task<Void, Never>?
    private var pathMonitor: NWPathMonitor?
    private var lastFetchDate: Date?
    private let session: URLSession
    private let apiURL: URL

    init(session: URLSession = .shared,
         apiURL: URL = URL(string: "https://www.nts.live/api/v2/live")!) {
        self.session = session
        self.apiURL = apiURL
    }

    /// Awaits the in-flight fetch, if any. Test hook — production code never needs to wait on a fetch.
    func awaitCurrentFetch() async {
        await fetchTask?.value
    }

    /// Starts the network path monitor. Call once at launch; the monitor runs for the app's lifetime.
    func startMonitor() {
        guard pathMonitor == nil else { return }
        let monitor = NWPathMonitor()
        pathMonitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let wasOffline = self.isOffline
                self.isOffline = path.status != .satisfied
                if wasOffline != self.isOffline {
                    Log.service.notice("Network \(self.isOffline ? "offline" : "online", privacy: .public)")
                }
                if wasOffline && !self.isOffline { self.fetch() }
            }
        }
        monitor.start(queue: DispatchQueue(label: "nts.network.monitor", qos: .utility))
    }

    func startPolling() {
        pollingTask?.cancel()
        // Skip the immediate fetch if data is fresh — avoids redundant requests
        // when the panel is closed and quickly reopened.
        if lastFetchDate.map({ Date().timeIntervalSince($0) > 10 }) ?? true {
            fetch()
        }
        pollingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                if !Task.isCancelled { fetch() }
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        // pathMonitor is intentionally kept alive across panel open/close cycles
        Log.service.debug("Polling stopped")
    }

    /// Called by the Refresh button — shows pulsing indicator for at least 1 second.
    func fetchManual() {
        guard !isRefreshing else { return }
        isRefreshing = true
        fetchTask?.cancel()
        fetchTask = nil
        fetch()
        Task {
            try? await Task.sleep(for: .seconds(1.9))
            isRefreshing = false
        }
    }

    func fetch() {
        // Drop the request if one is already in flight to prevent races
        guard fetchTask == nil || fetchTask!.isCancelled else { return }
        if channels.isEmpty { isLoading = true }
        fetchTask = Task {
            defer {
                fetchTask = nil
                isLoading = false
            }
            var request = URLRequest(url: apiURL)
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            do {
                let (data, response) = try await session.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                do {
                    let decoded = try JSONDecoder().decode(NTSLiveResponse.self, from: data)
                    channels = decoded.results
                    lastFetchDate = Date()
                    Log.service.debug("Fetched \(decoded.results.count) channels (HTTP \(status))")
                } catch {
                    // Decoded shape changed. Keep last known data; log a short payload
                    // prefix (NTS schedule data carries no PII) so it's diagnosable.
                    let prefix = String(decoding: data.prefix(400), as: UTF8.self)
                    Log.service.error("Decode failed (HTTP \(status)): \(error.localizedDescription, privacy: .public) — body starts: \(prefix, privacy: .public)")
                }
            } catch {
                Log.service.error("Request failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
