//
//  RadioPlayerTests.swift
//  RadioTests
//
//  State transitions around the single `AVPlayer`. `play()` always tears down the
//  previous player first; `toggle` fades out before switching or stopping.
//

import Foundation
import Testing
@testable import Radio

@MainActor
@Suite("RadioPlayer state")
struct RadioPlayerTests {

    @Test func startsStopped() {
        let p = RadioPlayer()
        #expect(p.playingChannel == nil)
        #expect(p.isBuffering == false)
        #expect(p.isPanelVisible == false)
    }

    @Test func playSetsChannelAndEntersBuffering() {
        let p = RadioPlayer()
        defer { p.stop() }

        p.play(channel: .one)

        #expect(p.playingChannel == .one)
        #expect(p.isBuffering == true)
    }

    @Test func stopClearsEverything() {
        let p = RadioPlayer()
        p.play(channel: .one)

        p.stop()

        #expect(p.playingChannel == nil)
        #expect(p.isBuffering == false)
    }

    @Test func playingASecondChannelReplacesTheFirst() {
        let p = RadioPlayer()
        defer { p.stop() }

        p.play(channel: .one)
        p.play(channel: .two)

        #expect(p.playingChannel == .two)
    }

    @Test func toggleFromStoppedStartsPlayback() {
        let p = RadioPlayer()
        defer { p.stop() }

        // No existing player -> fadeOutAndStop invokes its completion synchronously.
        p.toggle(channel: .one)

        #expect(p.playingChannel == .one)
    }

    @Test func toggleThePlayingChannelStopsIt() async throws {
        let p = RadioPlayer()
        p.play(channel: .one)

        p.toggle(channel: .one)

        try await waitUntil { p.playingChannel == nil }
    }

    @Test func toggleAnotherChannelSwitchesToIt() async throws {
        let p = RadioPlayer()
        defer { p.stop() }

        p.play(channel: .one)
        p.toggle(channel: .two)

        try await waitUntil { p.playingChannel == .two }
    }

    @Test func retryLastStreamResumesTheLastChannel() {
        let p = RadioPlayer()
        defer { p.stop() }

        p.play(channel: .two)
        p.stop()
        #expect(p.playingChannel == nil)

        p.retryLastStream()
        #expect(p.playingChannel == .two)
    }

    @Test func startingPlaybackClearsStreamFailed() {
        let p = RadioPlayer()
        defer { p.stop() }

        p.streamFailed = true
        p.play(channel: .one)

        #expect(p.streamFailed == false)
    }
}
