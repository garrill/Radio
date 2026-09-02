//
//  NTSServiceTests.swift
//  RadioTests
//
//  `fetch()` swallows every failure and keeps whatever `channels` it last had.
//  Requests are routed through an injected `URLSession` backed by `StubURLProtocol`.
//

import Foundation
import Testing
@testable import Radio

@MainActor
@Suite("NTSService fetch", .serialized)
struct NTSServiceTests {

    private func makeService() -> NTSService {
        NTSService(session: .stubbed, apiURL: URL(string: "https://test.invalid/live")!)
    }

    private func liveJSON(channelCount: Int, titlePrefix: String = "Show") throws -> Data {
        let channels = (0..<channelCount).map { i in
            Fixture.channelDict(name: "\(i + 1)", now: Fixture.broadcastDict(title: "\(titlePrefix) \(i)"))
        }
        return try Fixture.data(Fixture.liveResponseDict(channels: channels))
    }

    @Test func startsIdle() {
        let s = NTSService()
        #expect(s.channels.isEmpty)
        #expect(s.isLoading == false)
        #expect(s.isRefreshing == false)
        #expect(s.isOffline == false)
    }

    @Test func decodesChannelsOnSuccess() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub.data = try liveJSON(channelCount: 2)

        let s = makeService()
        s.fetch()
        await s.awaitCurrentFetch()

        #expect(s.channels.count == 2)
        #expect(s.channels.first?.channelName == "1")
        #expect(s.isLoading == false)
    }

    @Test func malformedBodyLeavesChannelsEmpty() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub.data = Data("{ not json".utf8)

        let s = makeService()
        s.fetch()
        await s.awaitCurrentFetch()

        #expect(s.channels.isEmpty)
        #expect(s.isLoading == false)
    }

    @Test func serverErrorKeepsLastGoodData() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub.data = try liveJSON(channelCount: 1)

        let s = makeService()
        s.fetch()
        await s.awaitCurrentFetch()
        #expect(s.channels.count == 1)

        StubURLProtocol.stub.statusCode = 500
        StubURLProtocol.stub.data = Data("upstream error".utf8)
        s.fetch()
        await s.awaitCurrentFetch()

        #expect(s.channels.count == 1)
    }

    @Test func transportErrorIsSwallowed() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub.error = URLError(.notConnectedToInternet)

        let s = makeService()
        s.fetch()
        await s.awaitCurrentFetch()

        #expect(s.channels.isEmpty)
        #expect(s.isLoading == false)
    }

    @Test func stopPollingCancelsTheLoop() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub.data = try liveJSON(channelCount: 2)

        let s = makeService()
        s.startPolling()
        await s.awaitCurrentFetch()
        #expect(s.channels.count == 2)

        s.stopPolling()
        // Nothing to assert beyond "does not crash / leak a task"; the poll loop is now cancelled.
        #expect(s.channels.count == 2)
    }
}
