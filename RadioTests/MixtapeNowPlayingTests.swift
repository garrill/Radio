//
//  MixtapeNowPlayingTests.swift
//  RadioTests
//
//  Decoding the Firestore `mixtape_titles` runQuery response, and the polling
//  service that drives `RadioPlayer.currentMixtapeNowPlaying`.
//

import Foundation
import Testing
@testable import Radio

@Suite("MixtapeNowPlaying decoding")
struct MixtapeNowPlayingTests {

    static let json = """
    [{
      "document": {
        "name": "projects/nts-ios-app/databases/(default)/documents/mixtape_titles/abc123",
        "fields": {
          "episode_alias": { "stringValue": "ton-lebbink-22nd-july-2022" },
          "mixtape_alias": { "stringValue": "4-to-the-floor" },
          "show_alias": { "stringValue": "guests" },
          "started_at": { "timestampValue": "2026-09-09T11:10:03Z" },
          "title": { "stringValue": "Ton Lebbink - For You (Heavy House Aerobic Mix), 22 Jul 2022" }
        },
        "createTime": "2026-09-09T11:10:09.001787Z",
        "updateTime": "2026-09-09T11:10:09.001787Z"
      },
      "readTime": "2026-09-09T11:30:50.115775Z"
    }]
    """

    @Test func decodesTitleAndArticlePath() throws {
        let result = try MixtapeNowPlaying.decode(Data(Self.json.utf8))
        #expect(result?.title == "Ton Lebbink - For You (Heavy House Aerobic Mix), 22 Jul 2022")
        #expect(result?.showAlias == "guests")
        #expect(result?.episodeAlias == "ton-lebbink-22nd-july-2022")
        #expect(result?.articlePath == "/shows/guests/episodes/ton-lebbink-22nd-july-2022")
    }

    @Test func decodesNilForEmptyResult() throws {
        // A `runQuery` with no matching row returns a single entry carrying only `readTime`.
        let json = """
        [{ "readTime": "2026-09-09T11:30:50.115775Z" }]
        """
        let result = try MixtapeNowPlaying.decode(Data(json.utf8))
        #expect(result == nil)
    }

    @Test func articlePathOmitsEpisodeWhenAbsent() {
        let nowPlaying = MixtapeNowPlaying(title: "X", showAlias: "guests", episodeAlias: nil)
        #expect(nowPlaying.articlePath == "/shows/guests")
    }

    @Test func articlePathNilWithoutShowAlias() {
        let nowPlaying = MixtapeNowPlaying(title: "X", showAlias: nil, episodeAlias: nil)
        #expect(nowPlaying.articlePath == nil)
    }

    @Test func requestBodyFiltersByMixtapeAlias() throws {
        let body = MixtapeNowPlaying.requestBody(mixtapeAlias: "4-to-the-floor")
        let data = try JSONSerialization.data(withJSONObject: body)
        let roundTripped = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let query = roundTripped?["structuredQuery"] as? [String: Any]
        let from = (query?["from"] as? [[String: Any]])?.first
        #expect(from?["collectionId"] as? String == "mixtape_titles")
        let filter = ((query?["where"] as? [String: Any])?["fieldFilter"] as? [String: Any])
        let value = (filter?["value"] as? [String: Any])?["stringValue"] as? String
        #expect(value == "4-to-the-floor")
    }
}

/// A `StubURLProtocol`-alike with its own static state, so these tests can run
/// concurrently with `NTSServiceTests` (which drives the shared `StubURLProtocol`)
/// without racing on the same global stub.
final class MixtapeTitleStubURLProtocol: URLProtocol {
    struct Stub {
        var statusCode = 200
        var data = Data()
        var error: Error?
    }

    nonisolated(unsafe) static var stub = Stub()

    static func reset() { stub = Stub() }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let client else { return }
        if let error = Self.stub.error {
            client.urlProtocol(self, didFailWithError: error)
            return
        }
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://test.invalid")!,
            statusCode: Self.stub.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client.urlProtocol(self, didLoad: Self.stub.data)
        client.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

extension URLSession {
    static var stubbedMixtapeTitle: URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MixtapeTitleStubURLProtocol.self]
        return URLSession(configuration: config)
    }
}

@MainActor
@Suite("MixtapeNowPlayingService", .serialized)
struct MixtapeNowPlayingServiceTests {

    private func makeService() -> MixtapeNowPlayingService {
        MixtapeNowPlayingService(session: .stubbedMixtapeTitle, queryURL: URL(string: "https://test.invalid/runQuery")!)
    }

    @Test func startsIdle() {
        let s = MixtapeNowPlayingService()
        #expect(s.current == nil)
    }

    @Test func startFetchesAndPublishesCurrent() async throws {
        MixtapeTitleStubURLProtocol.reset()
        MixtapeTitleStubURLProtocol.stub.data = Data(MixtapeNowPlayingTests.json.utf8)

        let s = makeService()
        s.start(alias: "4-to-the-floor")
        await s.awaitCurrentFetch()

        #expect(s.current?.title == "Ton Lebbink - For You (Heavy House Aerobic Mix), 22 Jul 2022")
    }

    @Test func stopClearsCurrent() async throws {
        MixtapeTitleStubURLProtocol.reset()
        MixtapeTitleStubURLProtocol.stub.data = Data(MixtapeNowPlayingTests.json.utf8)

        let s = makeService()
        s.start(alias: "4-to-the-floor")
        await s.awaitCurrentFetch()
        #expect(s.current != nil)

        s.stop()
        #expect(s.current == nil)
    }

    @Test func malformedBodyLeavesCurrentNil() async throws {
        MixtapeTitleStubURLProtocol.reset()
        MixtapeTitleStubURLProtocol.stub.data = Data("{ not json".utf8)

        let s = makeService()
        s.start(alias: "4-to-the-floor")
        await s.awaitCurrentFetch()

        #expect(s.current == nil)
    }

    @Test func startingSameAliasTwiceDoesNotRestart() async throws {
        MixtapeTitleStubURLProtocol.reset()
        MixtapeTitleStubURLProtocol.stub.data = Data(MixtapeNowPlayingTests.json.utf8)

        let s = makeService()
        s.start(alias: "4-to-the-floor")
        await s.awaitCurrentFetch()
        #expect(s.current != nil)

        // Should be a no-op — no new fetch, `current` stays as-is rather than resetting to nil.
        s.start(alias: "4-to-the-floor")
        #expect(s.current != nil)
    }
}
