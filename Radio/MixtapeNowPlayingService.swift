import Foundation
import Combine
import OSLog

/// Polls NTS's public Firestore `mixtape_titles` collection for the show currently
/// airing on whichever Infinite Mixtape is playing. Owned by `AppDelegate` alongside
/// `RadioPlayer`/`NTSService`; started/stopped as `player.playing` moves in and out of
/// `.mixtape`. See `MixtapeNowPlaying` for the query this replicates.
@MainActor
class MixtapeNowPlayingService: ObservableObject {
    @Published var current: MixtapeNowPlaying?

    private var pollingTask: Task<Void, Never>?
    private var fetchTask: Task<Void, Never>?
    private var currentAlias: String?
    private let session: URLSession
    private let queryURL: URL

    init(session: URLSession = .shared,
         queryURL: URL = URL(string: "https://firestore.googleapis.com/v1/projects/nts-ios-app/databases/(default)/documents:runQuery")!) {
        self.session = session
        self.queryURL = queryURL
    }

    /// Starts polling for `alias`'s current show; a no-op if already polling it.
    func start(alias: String) {
        guard currentAlias != alias else { return }
        currentAlias = alias
        current = nil
        pollingTask?.cancel()
        fetch(alias: alias)
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                guard !Task.isCancelled, let self else { return }
                self.fetch(alias: alias)
            }
        }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
        fetchTask = nil
        currentAlias = nil
        current = nil
    }

    /// Test hook — awaits the in-flight fetch, if any.
    func awaitCurrentFetch() async {
        await fetchTask?.value
    }

    /// Drops the request if one for this alias is already in flight.
    private func fetch(alias: String) {
        guard fetchTask == nil || fetchTask!.isCancelled else { return }
        fetchTask = Task { [weak self] in
            await self?.performFetch(alias: alias)
        }
    }

    private func performFetch(alias: String) async {
        var request = URLRequest(url: queryURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        guard let body = try? JSONSerialization.data(withJSONObject: MixtapeNowPlaying.requestBody(mixtapeAlias: alias)) else { return }
        request.httpBody = body

        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let nowPlaying = try MixtapeNowPlaying.decode(data)
            // The alias may have changed while this request was in flight — don't
            // clobber a newer poll's result with a stale one.
            guard currentAlias == alias else { return }
            current = nowPlaying
            Log.service.debug("Mixtape title for \(alias, privacy: .public): \(nowPlaying?.title ?? "none", privacy: .public) (HTTP \(status))")
        } catch {
            Log.service.error("Mixtape title fetch failed for \(alias, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
