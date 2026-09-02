//
//  NTSLiveResponseTests.swift
//  RadioTests
//
//  Decoding the top-level `api/v2/live` payload into `[ChannelData]`.
//

import Foundation
import Testing
@testable import Radio

@Suite("NTSLiveResponse decoding")
struct NTSLiveResponseTests {

    @Test func decodesBothChannelsWithNowAndNext() throws {
        let now1 = Fixture.broadcastDict(title: "Now One")
        let next1 = Fixture.broadcastDict(title: "Next One")
        let now2 = Fixture.broadcastDict(title: "Now Two")

        let payload = Fixture.liveResponseDict(channels: [
            Fixture.channelDict(name: "1", now: now1, next: next1),
            Fixture.channelDict(name: "2", now: now2, next: nil),
        ])

        let decoded = try JSONDecoder().decode(NTSLiveResponse.self, from: Fixture.data(payload))

        #expect(decoded.results.count == 2)
        #expect(decoded.results[0].channelName == "1")
        #expect(decoded.results[0].now.title == "Now One")
        #expect(decoded.results[0].next?.title == "Next One")
        #expect(decoded.results[1].channelName == "2")
        #expect(decoded.results[1].next == nil)
    }

    @Test func missingResultsKeyFailsToDecode() {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(NTSLiveResponse.self, from: Data("{}".utf8))
        }
    }

    @Test func missingRequiredTimestampFailsToDecode() {
        let badBroadcast: [String: Any] = ["broadcast_title": "No Times"]
        let payload = Fixture.liveResponseDict(channels: [Fixture.channelDict(now: badBroadcast)])
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(NTSLiveResponse.self, from: Fixture.data(payload))
        }
    }
}
