//
//  ChannelDataTests.swift
//  RadioTests
//
//  `effectiveNow` / `effectiveNext` compensate for the NTS API lagging the real
//  schedule: once `now` has ended, `next` is promoted to current.
//

import Foundation
import Testing
@testable import Radio

@Suite("ChannelData schedule promotion")
struct ChannelDataTests {

    private func channel(nowEndsIn offset: TimeInterval, hasNext: Bool, nowEndValid: Bool = true) throws -> ChannelData {
        let now = Fixture.broadcastDict(
            title: "Now Show",
            start: Fixture.iso(.now.addingTimeInterval(-3600)),
            end: nowEndValid ? Fixture.iso(.now.addingTimeInterval(offset)) : "invalid"
        )
        let next = hasNext ? Fixture.broadcastDict(
            title: "Next Show",
            start: Fixture.iso(.now.addingTimeInterval(offset)),
            end: Fixture.iso(.now.addingTimeInterval(offset + 3600))
        ) : nil
        return try Fixture.decodeChannel(Fixture.channelDict(now: now, next: next))
    }

    @Test func whileNowIsRunningNothingIsPromoted() throws {
        let c = try channel(nowEndsIn: 3600, hasNext: true)
        #expect(c.effectiveNow.broadcastTitle == "Now Show")
        #expect(c.effectiveNext?.broadcastTitle == "Next Show")
    }

    @Test func afterNowEndsNextBecomesCurrent() throws {
        let c = try channel(nowEndsIn: -3600, hasNext: true)
        #expect(c.effectiveNow.broadcastTitle == "Next Show")
        #expect(c.effectiveNext == nil)
    }

    @Test func endedNowWithNoNextStaysOnNow() throws {
        let c = try channel(nowEndsIn: -3600, hasNext: false)
        #expect(c.effectiveNow.broadcastTitle == "Now Show")
        #expect(c.effectiveNext == nil)
    }

    @Test func missingEndDateNeverPromotes() throws {
        let c = try channel(nowEndsIn: -3600, hasNext: true, nowEndValid: false)
        #expect(c.effectiveNow.broadcastTitle == "Now Show")
        #expect(c.effectiveNext == nil)
    }
}
