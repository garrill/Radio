//
//  ArtworkSizeTests.swift
//  RadioTests
//
//  `ArtworkSize` is the single source of truth for row artwork dimensions,
//  shared by `ChannelRow`, the Settings picker, and `AppDelegate.panelSize`.
//  If these numbers move, the hand-computed panel height must move with them.
//

import Foundation
import Testing
@testable import Radio

@Suite("ArtworkSize")
struct ArtworkSizeTests {

    @Test func rawValuesRoundTrip() {
        for size in ArtworkSize.allCases {
            #expect(ArtworkSize(rawValue: size.rawValue) == size)
        }
    }

    @Test func hasExactlyThreeCasesInOrder() {
        #expect(ArtworkSize.allCases == [.small, .medium, .large])
    }

    @Test func unknownRawValueIsNil() {
        #expect(ArtworkSize(rawValue: "extra-large") == nil)
        #expect(ArtworkSize(rawValue: "") == nil)
    }

    @Test func dimensionsAreTheDocumentedValues() {
        #expect(ArtworkSize.small.dimension == 66)
        #expect(ArtworkSize.medium.dimension == 80)
        #expect(ArtworkSize.large.dimension == 120)
    }

    @Test func dimensionsIncreaseWithSize() {
        #expect(ArtworkSize.small.dimension < ArtworkSize.medium.dimension)
        #expect(ArtworkSize.medium.dimension < ArtworkSize.large.dimension)
    }

    @Test func labelsAreCapitalisedForTheSettingsPicker() {
        #expect(ArtworkSize.small.label == "Small")
        #expect(ArtworkSize.medium.label == "Medium")
        #expect(ArtworkSize.large.label == "Large")
    }
}
