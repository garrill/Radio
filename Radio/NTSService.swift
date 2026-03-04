import Foundation
import Combine

@MainActor
class NTSService: ObservableObject {
    @Published var channels: [ChannelData] = []
    @Published var isLoading = false

    private var pollingTask: Task<Void, Never>?
    private let apiURL = URL(string: "https://www.nts.live/api/v2/live")!

    func startPolling() {
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

    func fetch() {
        if channels.isEmpty { isLoading = true }
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: apiURL)
                let response = try JSONDecoder().decode(NTSLiveResponse.self, from: data)
                channels = response.results
            } catch {
                // Silently fail — keep showing last known data
            }
            isLoading = false
        }
    }
}
