//
//  RadioChannelTests.swift
//  RadioTests
//

import Foundation
import Testing
@testable import Radio

@Suite("RadioChannel")
struct RadioChannelTests {

    @Test func rawValuesAndIdentity() {
        #expect(RadioChannel.one.rawValue == 1)
        #expect(RadioChannel.two.rawValue == 2)
        #expect(RadioChannel(rawValue: 1) == .one)
        #expect(RadioChannel(rawValue: 2) == .two)
        #expect(RadioChannel(rawValue: 3) == nil)
        #expect(RadioChannel.one.id == 1)
        #expect(RadioChannel.allCases.count == 2)
    }

    @Test func streamURLsPointAtTheNTSRelay() {
        #expect(RadioChannel.one.streamURL.absoluteString == "http://stream-relay-geo.ntslive.net/stream")
        #expect(RadioChannel.two.streamURL.absoluteString == "http://stream-relay-geo.ntslive.net/stream2")
    }

    @Test func streamsAreHTTP_matchingTheATSException() {
        // Info.plist grants NSExceptionAllowsInsecureHTTPLoads for this host; keep them in sync.
        for channel in RadioChannel.allCases {
            #expect(channel.streamURL.scheme == "http")
            #expect(channel.streamURL.host == "stream-relay-geo.ntslive.net")
        }
    }

    @Test func labelsAndSymbols() {
        #expect(RadioChannel.one.label == "NTS 1")
        #expect(RadioChannel.two.label == "NTS 2")
        #expect(RadioChannel.one.menuBarSymbol == "1.square.fill")
        #expect(RadioChannel.two.menuBarSymbol == "2.square.fill")
    }

    @Test func nextAndPreviousCycleBetweenTheTwoChannels() {
        #expect(RadioChannel.one.next == .two)
        #expect(RadioChannel.two.next == .one)
        #expect(RadioChannel.one.previous == .two)
        #expect(RadioChannel.two.previous == .one)
    }
}
