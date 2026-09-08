//
//  RadioPlayerVolumeTests.swift
//  RadioTests
//
//  App-level output volume: the `speaker.wave.*` glyph steps (matching the macOS
//  Music app) and that a set level is carried into the next `AVPlayer`.
//

import Foundation
import Testing
@testable import Radio

@Suite("RadioPlayer volume")
struct RadioPlayerVolumeTests {

    @Test func symbolIsSlashOnlyAtZero() {
        #expect(RadioPlayer.volumeSymbol(for: 0) == "speaker.slash.fill")
        #expect(RadioPlayer.volumeSymbol(for: 0.0001) == "speaker.wave.1.fill")
    }

    @Test func symbolStepsWithLevel() {
        #expect(RadioPlayer.volumeSymbol(for: 0.1) == "speaker.wave.1.fill")
        #expect(RadioPlayer.volumeSymbol(for: 0.25) == "speaker.wave.1.fill")
        #expect(RadioPlayer.volumeSymbol(for: 0.4) == "speaker.wave.2.fill")
        #expect(RadioPlayer.volumeSymbol(for: 0.5) == "speaker.wave.2.fill")
        #expect(RadioPlayer.volumeSymbol(for: 0.75) == "speaker.wave.3.fill")
        #expect(RadioPlayer.volumeSymbol(for: 1.0) == "speaker.wave.3.fill")
    }

    @MainActor
    @Test func setLevelIsAppliedToNewPlayback() {
        let p = RadioPlayer()
        defer { p.stop() }

        p.volume = 0.3
        p.play(channel: .one)

        // `volume` is the source of truth applied to each fresh AVPlayer in `play()`.
        #expect(p.volume == 0.3)
        #expect(p.volumeSymbol == "speaker.wave.2.fill")
    }
}
