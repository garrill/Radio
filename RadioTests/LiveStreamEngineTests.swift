//
//  LiveStreamEngineTests.swift
//  RadioTests
//
//  The app decodes and plays NTS's MP3 streams itself (so the now-playing bars can show the
//  real audio). These cover the decode path and the spectrum analysis against fixtures —
//  a 440 Hz tone and digital silence — without touching the network or an audio device.
//

import AVFoundation
import Accelerate
import Foundation
import Testing
@testable import Radio

private final class BundleToken {}

private func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle(for: BundleToken.self).url(forResource: name, withExtension: "mp3"))
    return try Data(contentsOf: url)
}

/// Feeds `data` to a decoder in `chunkSize` pieces and collects the PCM it produces.
private func decode(_ data: Data, chunkSize: Int) throws -> [AVAudioPCMBuffer] {
    var buffers: [AVAudioPCMBuffer] = []
    let decoder = MP3StreamDecoder { buffers.append($0) }
    var offset = data.startIndex
    while offset < data.endIndex {
        let end = min(offset + chunkSize, data.endIndex)
        try decoder.parse(data[offset..<end])
        offset = end
    }
    return buffers
}

private func peak(of buffers: [AVAudioPCMBuffer]) -> Float {
    buffers.reduce(0) { result, buffer in
        var p: Float = 0
        vDSP_maxmgv(buffer.floatChannelData![0], 1, &p, vDSP_Length(buffer.frameLength))
        return max(result, p)
    }
}

@Suite("MP3 stream decoder")
struct MP3StreamDecoderTests {

    @Test(arguments: [417, 4_096, 65_536])
    func decodesTheToneInAnyChunkSize(chunkSize: Int) throws {
        let buffers = try decode(fixture("tone"), chunkSize: chunkSize)
        let frames = buffers.reduce(0) { $0 + Int($1.frameLength) }
        #expect(frames > 44_100)   // most of the 2 s fixture
        #expect(peak(of: buffers) > 0.01)
        #expect(buffers.first?.format.commonFormat == .pcmFormatFloat32)
    }

    /// A live stream is joined mid-frame; the parser must resync rather than fail.
    @Test func resyncsWhenStartingMidFrame() throws {
        let data = try fixture("tone").dropFirst(1_001)
        let buffers = try decode(Data(data), chunkSize: 4_096)
        #expect(peak(of: buffers) > 0.01)
    }

    @Test func silenceDecodesToSilence() throws {
        let buffers = try decode(fixture("silence"), chunkSize: 4_096)
        #expect(!buffers.isEmpty)
        #expect(peak(of: buffers) < 0.001)
    }
}

@Suite("Audio levels")
struct AudioLevelsTests {

    private func window(from buffers: [AVAudioPCMBuffer]) throws -> [Float] {
        let size = Int(AudioLevels.fftSize)
        let samples = buffers.flatMap { b in
            Array(UnsafeBufferPointer(start: b.floatChannelData![0], count: Int(b.frameLength)))
        }
        try #require(samples.count >= size * 2)
        return Array(samples[size..<(size * 2)])   // skip decoder priming at the start
    }

    @Test func toneLightsUpItsBandOnly() throws {
        let samples = try window(from: decode(fixture("tone"), chunkSize: 4_096))
        let bands = AudioLevels().levels(ofWindow: samples, sampleRate: 44_100)
        // 440 Hz sits in band 1 (150–500 Hz).
        #expect(bands[1] > 0.3)
        #expect(bands.indices.filter { $0 != 1 }.allSatisfy { bands[$0] < bands[1] })
    }

    @Test func silenceIsFlat() throws {
        let samples = try window(from: decode(fixture("silence"), chunkSize: 4_096))
        let bands = AudioLevels().levels(ofWindow: samples, sampleRate: 44_100)
        #expect(bands.allSatisfy { $0 == 0 })
    }

    @Test func disabledLevelsIgnoreAudioAndReadZero() throws {
        let buffers = try decode(fixture("tone"), chunkSize: 65_536)
        let levels = AudioLevels()
        levels.isEnabled = false
        buffers.forEach(levels.process)
        #expect(levels.snapshot().allSatisfy { $0 == 0 })

        levels.isEnabled = true
        buffers.forEach(levels.process)
        #expect(levels.snapshot()[1] > 0)

        levels.isEnabled = false
        #expect(levels.snapshot().allSatisfy { $0 == 0 })
    }
}
