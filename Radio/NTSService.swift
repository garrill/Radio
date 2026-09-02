import Foundation
import Combine
import Network

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
            do {
                var request = URLRequest(url: apiURL)
                request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
                let (data, _) = try await session.data(for: request)
                let response = try JSONDecoder().decode(NTSLiveResponse.self, from: data)
                channels = response.results
                lastFetchDate = Date()
            } catch {
                // Silently fail — keep showing last known data
            }
        }
    }
}
