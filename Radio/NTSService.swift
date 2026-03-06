import Foundation
import Combine

@MainActor
class NTSService: ObservableObject {
    @Published var channels: [ChannelData] = []
    @Published var isLoading = false
    @Published var isRefreshing = false

    private var pollingTask: Task<Void, Never>?
    private var fetchTask: Task<Void, Never>?
    private let apiURL = URL(string: "https://www.nts.live/api/v2/live")!

    func startPolling() {
        pollingTask?.cancel() // guard against duplicate calls
        fetch()
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
    }

    /// Called by the Refresh button — shows pulsing indicator.
    func fetchManual() {
        isRefreshing = true
        fetch()
    }

    func fetch() {
        // Drop the request if one is already in flight to prevent races
        guard fetchTask == nil || fetchTask!.isCancelled else { return }
        if channels.isEmpty { isLoading = true }
        fetchTask = Task {
            defer {
                fetchTask = nil
                isLoading = false
                isRefreshing = false
            }
            do {
                var request = URLRequest(url: apiURL)
                request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
                let (data, _) = try await URLSession.shared.data(for: request)
                let response = try JSONDecoder().decode(NTSLiveResponse.self, from: data)
                channels = response.results
            } catch {
                // Silently fail — keep showing last known data
            }
        }
    }
}
