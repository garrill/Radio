//
//  BroadcastTests.swift
//  RadioTests
//
//  `Broadcast` does its date parsing and title clean-up once, in `init(from:)`.
//  These cover that decode-time work and the derived accessors.
//

import Foundation
import Testing
@testable import Radio

@Suite("Broadcast decoding")
struct BroadcastTests {

    // MARK: Timestamps

    @Test func parsesISO8601Timestamps() throws {
        let b = try Fixture.decodeBroadcast(Fixture.broadcastDict(
            start: "2026-09-02T12:00:00Z",
            end: "2026-09-02T14:00:00Z"
        ))
        #expect(b.startDate != nil)
        #expect(b.endDate != nil)
        #expect(b.endDate!.timeIntervalSince(b.startDate!) == 7200)
    }

    @Test func unparseableTimestampsBecomeNil() throws {
        let b = try Fixture.decodeBroadcast(Fixture.broadcastDict(start: "not-a-date", end: "also-bad"))
        #expect(b.startDate == nil)
        #expect(b.endDate == nil)
    }

    // MARK: Title clean-up

    @Test func allCapsTitleIsTitleCased() throws {
        let b = try Fixture.decodeBroadcast(Fixture.broadcastDict(title: "FLOATING POINTS"))
        #expect(b.title == "Floating Points")
    }

    @Test func mixedCaseTitleIsLeftAlone() throws {
        let b = try Fixture.decodeBroadcast(Fixture.broadcastDict(title: "Bradley Zero's Worldwide FM"))
        #expect(b.title == "Bradley Zero's Worldwide FM")
    }

    @Test func ntsAcronymIsRestoredAfterTitleCasing() throws {
        let b = try Fixture.decodeBroadcast(Fixture.broadcastDict(title: "NTS BREAKFAST SHOW"))
        #expect(b.title == "NTS Breakfast Show")
    }

    @Test func htmlEntitiesAreDecoded() throws {
        let b = try Fixture.decodeBroadcast(Fixture.broadcastDict(title: "MARY ANNE HOBBS &amp; GUESTS"))
        #expect(b.title == "Mary Anne Hobbs & Guests")
    }

    @Test func numericApostropheEntityIsDecoded() throws {
        let b = try Fixture.decodeBroadcast(Fixture.broadcastDict(title: "Bradley Zero&#39;s Show"))
        #expect(b.title == "Bradley Zero's Show")
    }

    @Test func repeatSuffixSetsIsRepeat() throws {
        let repeated = try Fixture.decodeBroadcast(Fixture.broadcastDict(title: "SOME SHOW (R)"))
        let live = try Fixture.decodeBroadcast(Fixture.broadcastDict(title: "SOME SHOW"))
        #expect(repeated.isRepeat == true)
        #expect(live.isRepeat == false)
        #expect(repeated.title.hasPrefix("Some Show"))
    }

    // MARK: Artwork URL fallback chain

    @Test func artworkPrefersMediumLarge() throws {
        let b = try Fixture.decodeBroadcast(Fixture.broadcastDict(
            pictureMediumLarge: "https://media.invalid/ml.jpg",
            pictureMedium: "https://media.invalid/m.jpg",
            pictureSmall: "https://media.invalid/s.jpg"
        ))
        #expect(b.artworkURL?.absoluteString == "https://media.invalid/ml.jpg")
    }

    @Test func artworkFallsBackToMediumThenSmall() throws {
        let medium = try Fixture.decodeBroadcast(Fixture.broadcastDict(
            pictureMedium: "https://media.invalid/m.jpg",
            pictureSmall: "https://media.invalid/s.jpg"
        ))
        let small = try Fixture.decodeBroadcast(Fixture.broadcastDict(
            pictureSmall: "https://media.invalid/s.jpg"
        ))
        #expect(medium.artworkURL?.absoluteString == "https://media.invalid/m.jpg")
        #expect(small.artworkURL?.absoluteString == "https://media.invalid/s.jpg")
    }

    @Test func artworkIsNilWithoutMedia() throws {
        let noEmbeds = try Fixture.decodeBroadcast(Fixture.broadcastDict(includeEmbeds: false))
        let noMedia = try Fixture.decodeBroadcast(Fixture.broadcastDict())
        #expect(noEmbeds.artworkURL == nil)
        #expect(noMedia.artworkURL == nil)
    }

    // MARK: Location

    @Test func locationComesFromEmbeds() throws {
        let withLocation = try Fixture.decodeBroadcast(Fixture.broadcastDict(locationLong: "Manchester"))
        let withoutLocation = try Fixture.decodeBroadcast(Fixture.broadcastDict(locationLong: nil,
                                                                               pictureSmall: "https://media.invalid/s.jpg"))
        #expect(withLocation.location == "Manchester")
        #expect(withoutLocation.location == nil)
    }

    // MARK: Progress

    @Test func progressIsHalfwayThroughTheBroadcast() throws {
        let b = try Fixture.decodeBroadcast(Fixture.broadcastDict(
            start: Fixture.iso(.now.addingTimeInterval(-1800)),
            end: Fixture.iso(.now.addingTimeInterval(1800))
        ))
        #expect(abs(b.progress - 0.5) < 0.02)
    }

    @Test func progressClampsToZeroAndOne() throws {
        let finished = try Fixture.decodeBroadcast(Fixture.broadcastDict(
            start: Fixture.iso(.now.addingTimeInterval(-7200)),
            end: Fixture.iso(.now.addingTimeInterval(-3600))
        ))
        let future = try Fixture.decodeBroadcast(Fixture.broadcastDict(
            start: Fixture.iso(.now.addingTimeInterval(3600)),
            end: Fixture.iso(.now.addingTimeInterval(7200))
        ))
        let undated = try Fixture.decodeBroadcast(Fixture.broadcastDict(start: "x", end: "y"))
        #expect(finished.progress == 1)
        #expect(future.progress == 0)
        #expect(undated.progress == 0)
    }

    // MARK: Formatted time

    @Test func formattedTimeIsHoursAndMinutesOrEmpty() throws {
        let b = try Fixture.decodeBroadcast(Fixture.broadcastDict())
        #expect(b.formattedTime(nil) == "")

        let formatted = b.formattedTime(Date())
        #expect(formatted.count == 5)
        #expect(formatted.dropFirst(2).first == ":")
        #expect(formatted.filter(\.isNumber).count == 4)
    }

    // MARK: Round-trip

    @Test func encodeThenDecodeIsStable() throws {
        let original = try Fixture.decodeBroadcast(Fixture.broadcastDict(
            title: "Charlie Bones",
            start: "2026-09-02T07:00:00Z",
            end: "2026-09-02T10:00:00Z"
        ))
        let reEncoded = try JSONEncoder().encode(original)
        let roundTripped = try JSONDecoder().decode(Broadcast.self, from: reEncoded)
        #expect(roundTripped.title == original.title)
        #expect(roundTripped.startDate == original.startDate)
        #expect(roundTripped.endDate == original.endDate)
    }
}
