//
//  MixtapeTests.swift
//  RadioTests
//
//  Decoding the `api/v2/mixtapes` shape and the enabled-selection helpers.
//

import Foundation
import Testing
@testable import Radio

@Suite("Mixtape decoding")
struct MixtapeTests {

    /// Trimmed to the fields the app reads, in the real API's shape.
    static let json = """
    {
      "results": [
        {
          "mixtape_alias": "poolside",
          "title": "Poolside",
          "subtitle": "Balearic, boogie, and sophisti-pop.",
          "description": "Long description here.",
          "audio_stream_endpoint": "https://stream-mixtape-geo.ntslive.net/mixtape4",
          "media": {
            "picture_medium_large": "https://media.ntslive.co.uk/resize/800x800/poolside.jpeg",
            "picture_medium": "https://media.ntslive.co.uk/resize/400x400/poolside.jpeg",
            "icon_black": "https://media.ntslive.co.uk/crop/128x128/poolside-black.png",
            "icon_white": "https://media.ntslive.co.uk/crop/128x128/poolside-white.png"
          }
        },
        {
          "mixtape_alias": "no-media",
          "title": "No Media",
          "subtitle": "",
          "description": "",
          "audio_stream_endpoint": "https://stream-mixtape-geo.ntslive.net/mixtape9"
        }
      ]
    }
    """

    private func decoded() throws -> [Mixtape] {
        try JSONDecoder().decode(MixtapesResponse.self, from: Data(Self.json.utf8)).results
    }

    @Test func decodesCoreFields() throws {
        let m = try decoded()[0]
        #expect(m.alias == "poolside")
        #expect(m.id == "poolside")
        #expect(m.title == "Poolside")
        #expect(m.subtitle == "Balearic, boogie, and sophisti-pop.")
        #expect(m.streamURL.absoluteString == "https://stream-mixtape-geo.ntslive.net/mixtape4")
        #expect(m.artworkURL?.absoluteString == "https://media.ntslive.co.uk/resize/800x800/poolside.jpeg")
        #expect(m.iconURL?.absoluteString == "https://media.ntslive.co.uk/crop/128x128/poolside-black.png")
    }

    @Test func toleratesMissingMedia() throws {
        let m = try decoded()[1]
        #expect(m.alias == "no-media")
        #expect(m.artworkURL == nil)
        #expect(m.iconURL == nil)
        #expect(m.streamURL.absoluteString == "https://stream-mixtape-geo.ntslive.net/mixtape9")
    }

    @Test func fallsBackToPictureMediumWhenLargeMissing() throws {
        let json = """
        { "results": [ {
          "mixtape_alias": "x", "title": "X", "subtitle": "", "description": "",
          "audio_stream_endpoint": "https://stream-mixtape-geo.ntslive.net/mixtape1",
          "media": { "picture_medium": "https://media.ntslive.co.uk/m.jpeg" }
        } ] }
        """
        let m = try JSONDecoder().decode(MixtapesResponse.self, from: Data(json.utf8)).results[0]
        #expect(m.artworkURL?.absoluteString == "https://media.ntslive.co.uk/m.jpeg")
    }

    @Test func encodeDecodeRoundTrips() throws {
        let original = try decoded()[0]
        let data = try JSONEncoder().encode(original)
        let again = try JSONDecoder().decode(Mixtape.self, from: data)
        #expect(again == original)
    }
}

@Suite("MixtapeSelection")
struct MixtapeSelectionTests {

    @Test func parsesAndFormats() {
        #expect(MixtapeSelection.aliases(from: "") == [])
        #expect(MixtapeSelection.aliases(from: "a,b,c") == ["a", "b", "c"])
        #expect(MixtapeSelection.aliases(from: "a,,b") == ["a", "b"])
        #expect(MixtapeSelection.raw(from: ["a", "b"]) == "a,b")
    }

    @Test func isEnabledChecksMembership() {
        #expect(MixtapeSelection.isEnabled("b", in: "a,b,c"))
        #expect(!MixtapeSelection.isEnabled("z", in: "a,b,c"))
    }

    @Test func togglingAddsThenRemoves() {
        let added = MixtapeSelection.toggling("poolside", in: "")
        #expect(added == "poolside")
        let removed = MixtapeSelection.toggling("poolside", in: added)
        #expect(removed == "")
    }

    @Test func togglingPreservesOtherEntries() {
        let result = MixtapeSelection.toggling("b", in: "a,b,c")
        #expect(MixtapeSelection.aliases(from: result) == ["a", "c"])
    }
}
