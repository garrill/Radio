import AVFoundation
import Accelerate
import os

/// Five-band spectrum levels (0…1) of whatever is playing, for the now-playing bars.
///
/// Written from `LiveStreamEngine`'s level tap, read by `CoreAnimationWaveform`'s display link.
/// Deliberately **not** observable: publishing ~20 updates a second would re-render SwiftUI
/// and recommit the glass panel (see the CPU note on `CoreAnimationWaveform`).
nonisolated final class AudioLevels: Sendable {
    static let bandCount = 5
    static let fftSize: AVAudioFrameCount = 2048
    /// Band edges in Hz — roughly sub/bass, low-mid, mid, presence, air.
    static let bandEdges: [Float] = [40, 150, 500, 1_500, 5_000, 14_000]
    /// dBFS mapped to 0 and 1. NTS dead air (≈ −66 dBFS) sits below the floor, so it's flat.
    static let floorDB: Float = -60
    static let ceilingDB: Float = -6
    /// Per-band trim in dB: music carries far more energy low down, so lift the upper bands.
    static let bandTrimDB: [Float] = [-4, 0, 3, 6, 10]
    /// Fraction of the previous level kept per analysed window (~23 ms) — a ~150 ms release.
    static let release: Float = 0.85

    private struct State {
        var bands = [Float](repeating: 0, count: AudioLevels.bandCount)
        var isEnabled = false
    }
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let analyser = OSAllocatedUnfairLock(initialState: SpectrumAnalyser(size: Int(AudioLevels.fftSize)))

    /// Off while the panel is hidden, so no FFT work is done when the bars aren't on screen.
    var isEnabled: Bool {
        get { state.withLock { $0.isEnabled } }
        set {
            state.withLock {
                $0.isEnabled = newValue
                if !newValue { $0.bands = [Float](repeating: 0, count: Self.bandCount) }
            }
        }
    }

    func snapshot() -> [Float] {
        state.withLock { $0.bands }
    }

    func reset() {
        state.withLock { $0.bands = [Float](repeating: 0, count: Self.bandCount) }
    }

    /// Tap thread. Analyses the buffer in hops of `fftSize / 2` and folds each into the levels.
    func process(_ buffer: AVAudioPCMBuffer) {
        guard isEnabled, let channels = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        let size = Int(Self.fftSize)
        guard frames >= size else { return }
        let channelCount = Int(buffer.format.channelCount)
        let sampleRate = Float(buffer.format.sampleRate)

        var mono = [Float](repeating: 0, count: frames)
        for c in 0..<channelCount {
            vDSP.add(mono, UnsafeBufferPointer(start: channels[c], count: frames), result: &mono)
        }
        vDSP.multiply(1 / Float(channelCount), mono, result: &mono)

        var start = 0
        while start + size <= frames {
            let window = Array(mono[start..<(start + size)])
            let bands = analyser.withLock { $0.bandLevels(of: window, sampleRate: sampleRate) }
            fold(bands)
            start += size / 2
        }
    }

    /// Analyses one window directly (tests). Returns 0…1 per band without smoothing.
    func levels(ofWindow samples: [Float], sampleRate: Float) -> [Float] {
        analyser.withLock { $0.bandLevels(of: samples, sampleRate: sampleRate) }
    }

    private func fold(_ bands: [Float]) {
        state.withLock { s in
            guard s.isEnabled else { return }
            for i in 0..<Self.bandCount {
                s.bands[i] = max(bands[i], s.bands[i] * Self.release)   // instant attack
            }
        }
    }
}

/// Hann-windowed real FFT → peak magnitude per band → 0…1.
nonisolated struct SpectrumAnalyser: @unchecked Sendable {
    private let size: Int
    private let log2n: vDSP_Length
    private let setup: FFTSetup
    private let window: [Float]
    private var real: [Float]
    private var imag: [Float]

    init(size: Int) {
        self.size = size
        log2n = vDSP_Length(log2(Float(size)))
        setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: size, isHalfWindow: false)
        real = [Float](repeating: 0, count: size / 2)
        imag = [Float](repeating: 0, count: size / 2)
    }

    mutating func bandLevels(of samples: [Float], sampleRate: Float) -> [Float] {
        precondition(samples.count == size)
        let windowed = vDSP.multiply(samples, window)
        let half = size / 2
        var magnitudes = [Float](repeating: 0, count: half)

        real.withUnsafeMutableBufferPointer { re in
            imag.withUnsafeMutableBufferPointer { im in
                var split = DSPSplitComplex(realp: re.baseAddress!, imagp: im.baseAddress!)
                windowed.withUnsafeBufferPointer { w in
                    w.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvabs(&split, 1, &magnitudes, 1, vDSP_Length(half))
            }
        }
        // zrip output is 2× the DFT; a Hann window halves a sine's peak. Scale so a full-scale
        // sine reads ≈ 1.0 (0 dBFS) at its bin.
        vDSP.multiply(2 / Float(size), magnitudes, result: &magnitudes)

        let binHz = sampleRate / Float(size)
        var result = [Float](repeating: 0, count: AudioLevels.bandCount)
        for b in 0..<AudioLevels.bandCount {
            let lo = max(1, Int(AudioLevels.bandEdges[b] / binHz))
            let hi = min(half - 1, Int(AudioLevels.bandEdges[b + 1] / binHz))
            guard hi > lo else { continue }
            let peak = vDSP.maximum(magnitudes[lo...hi])
            let db = 20 * log10(max(peak, 1e-9)) + AudioLevels.bandTrimDB[b]
            let normalised = (db - AudioLevels.floorDB) / (AudioLevels.ceilingDB - AudioLevels.floorDB)
            result[b] = min(max(normalised, 0), 1)
        }
        return result
    }
}
