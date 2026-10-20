import AVFoundation
import AudioToolbox
import OSLog

/// Plays one live MP3 stream: `URLSession` → `AudioFileStream` (parse) → `AVAudioConverter`
/// (decode) → `AVAudioEngine` (play). Replaces `AVPlayer` so the app can see the decoded
/// samples — `AVPlayer` exposes none for live progressive streams (an `MTAudioProcessingTap`
/// receives nothing), which the waveform bars need.
///
/// All state lives on `queue`; URLSession delegate callbacks are delivered there too. Events
/// are reported to the main actor in order. One instance per `play()` — `RadioPlayer` throws it
/// away on stop and builds a fresh one for reconnects.
nonisolated final class LiveStreamEngine: NSObject, URLSessionDataDelegate, @unchecked Sendable {

    enum Event: Equatable, Sendable {
        /// Waiting for enough audio to (re)start — initial connect or an underrun.
        case buffering
        case playing
        /// Network error, server closed the stream, or undecodable data. Terminal.
        case failed(String)
    }

    /// Audio queued before playback starts or resumes after an underrun.
    static let startThreshold: Double = 1.5

    private let url: URL
    private let levels: AudioLevels
    private let onEvent: @MainActor (LiveStreamEngine, Event) -> Void
    private let queue = DispatchQueue(label: "com.garrill.Radio.stream", qos: .userInitiated)

    // Everything below is only touched on `queue`.
    private var session: URLSession?
    private var decoder: MP3StreamDecoder?
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    /// Unity-gain mixer between the player and the output. The level tap sits here, before
    /// `mainMixerNode.outputVolume`, so the bars still move when the app volume is muted.
    private let analysisMixer = AVAudioMixerNode()
    private var pcmFormat: AVAudioFormat?
    private var queuedFrames: AVAudioFramePosition = 0
    private var isNodePlaying = false
    private var isStopped = false
    /// Bumped whenever scheduled buffers are discarded, so their late completions are ignored.
    private var generation = 0
    private var volumeLevel: Float
    private var lastEvent: Event?
    private var configObserver: NSObjectProtocol?

    /// `onEvent` receives the engine itself so the owner can drop events from a replaced engine
    /// without capturing it (which would be a retain cycle).
    init(url: URL, volume: Float, levels: AudioLevels,
         onEvent: @escaping @MainActor (LiveStreamEngine, Event) -> Void) {
        self.url = url
        self.volumeLevel = volume
        self.levels = levels
        self.onEvent = onEvent
        super.init()
    }

    /// App-level output volume (0…1). Applied after the level tap.
    var volume: Float {
        get { queue.sync { volumeLevel } }
        set {
            queue.async { [self] in
                volumeLevel = newValue
                engine.mainMixerNode.outputVolume = newValue
            }
        }
    }

    func start() {
        queue.async { [self] in
            guard !isStopped, session == nil else { return }
            decoder = MP3StreamDecoder { [weak self] buffer in self?.schedule(buffer) }
            let delegateQueue = OperationQueue()
            delegateQueue.underlyingQueue = queue
            delegateQueue.maxConcurrentOperationCount = 1
            let config = URLSessionConfiguration.default
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            config.timeoutIntervalForRequest = 15
            let session = URLSession(configuration: config, delegate: self, delegateQueue: delegateQueue)
            self.session = session
            emit(.buffering)
            session.dataTask(with: url).resume()
        }
    }

    /// Tears everything down. Idempotent; no events are emitted afterwards.
    func stop() {
        queue.async { [self] in
            guard !isStopped else { return }
            isStopped = true
            teardown()
        }
    }

    // MARK: - URLSessionDataDelegate (on `queue`)

    func urlSession(
        _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            completionHandler(.cancel)
            fail("HTTP \(http.statusCode)")
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard !isStopped else { return }
        do {
            try decoder?.parse(data)
        } catch {
            fail("decode: \(error.localizedDescription)")
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard !isStopped else { return }
        fail(error?.localizedDescription ?? "stream ended")
    }

    // MARK: - Playback (on `queue`)

    private func schedule(_ buffer: AVAudioPCMBuffer) {
        guard !isStopped else { return }
        if pcmFormat == nil {
            do {
                try configureEngine(format: buffer.format)
            } catch {
                fail("audio engine: \(error.localizedDescription)")
                return
            }
        }
        let frames = AVAudioFramePosition(buffer.frameLength)
        let gen = generation
        queuedFrames += frames
        playerNode.scheduleBuffer(buffer, completionCallbackType: .dataConsumed) { [weak self] _ in
            guard let self else { return }
            self.queue.async { self.bufferConsumed(frames: frames, generation: gen) }
        }
        if !isNodePlaying, queuedSeconds >= Self.startThreshold {
            if !engine.isRunning {
                do { try engine.start() } catch {
                    fail("audio engine: \(error.localizedDescription)")
                    return
                }
            }
            playerNode.play()
            isNodePlaying = true
            emit(.playing)
        }
    }

    private func bufferConsumed(frames: AVAudioFramePosition, generation gen: Int) {
        guard !isStopped, gen == generation else { return }
        queuedFrames -= frames
        if queuedFrames <= 0, isNodePlaying {
            // Underrun — the network fell behind. Hold until the threshold refills.
            queuedFrames = 0
            playerNode.pause()
            isNodePlaying = false
            levels.reset()
            emit(.buffering)
        }
    }

    private var queuedSeconds: Double {
        guard let rate = pcmFormat?.sampleRate, rate > 0 else { return 0 }
        return Double(queuedFrames) / rate
    }

    private func configureEngine(format: AVAudioFormat) throws {
        pcmFormat = format
        engine.attach(playerNode)
        engine.attach(analysisMixer)
        engine.connect(playerNode, to: analysisMixer, format: format)
        engine.connect(analysisMixer, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = volumeLevel
        let levels = self.levels
        analysisMixer.installTap(onBus: 0, bufferSize: AudioLevels.fftSize, format: format) { buffer, _ in
            levels.process(buffer)
        }
        engine.prepare()
        try engine.start()

        // Output device changed (headphones, AirPlay, default device) — the engine stops and
        // drops what was scheduled. Restart it and refill; the network keeps flowing meanwhile.
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            self.queue.async { self.handleConfigurationChange() }
        }
    }

    private func handleConfigurationChange() {
        guard !isStopped, let format = pcmFormat else { return }
        Log.player.notice("Audio configuration changed — restarting engine")
        generation += 1
        queuedFrames = 0
        isNodePlaying = false
        playerNode.stop()
        engine.connect(playerNode, to: analysisMixer, format: format)
        engine.connect(analysisMixer, to: engine.mainMixerNode, format: format)
        engine.prepare()
        do { try engine.start() } catch {
            fail("audio engine restart: \(error.localizedDescription)")
            return
        }
        emit(.buffering)
    }

    private func fail(_ reason: String) {
        guard !isStopped else { return }
        isStopped = true
        teardown()
        emit(.failed(reason), force: true)
    }

    private func teardown() {
        generation += 1
        session?.invalidateAndCancel()   // also releases the session's strong ref to us
        session = nil
        decoder = nil
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = nil
        if pcmFormat != nil {
            analysisMixer.removeTap(onBus: 0)
            playerNode.stop()
            engine.stop()
        }
        queuedFrames = 0
        isNodePlaying = false
        levels.reset()
    }

    private func emit(_ event: Event, force: Bool = false) {
        guard force || !isStopped, event != lastEvent else { return }
        lastEvent = event
        let onEvent = self.onEvent
        DispatchQueue.main.async {
            MainActor.assumeIsolated { onEvent(self, event) }
        }
    }
}

// MARK: - MP3 decoding

/// Incremental MP3 → Float32 PCM decoder. Feed it arbitrary byte chunks (a stream may start
/// mid-frame — `AudioFileStream` resyncs); decoded buffers arrive through `onPCM`, synchronously
/// inside `parse`. Not thread-safe; owned by one queue.
nonisolated final class MP3StreamDecoder {
    private var streamID: AudioFileStreamID?
    private var inputFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private let onPCM: (AVAudioPCMBuffer) -> Void
    private var error: Error?

    init(onPCM: @escaping (AVAudioPCMBuffer) -> Void) {
        self.onPCM = onPCM
    }

    deinit {
        if let streamID { AudioFileStreamClose(streamID) }
    }

    func parse(_ data: Data) throws {
        if streamID == nil {
            let status = AudioFileStreamOpen(
                Unmanaged.passUnretained(self).toOpaque(),
                { clientData, stream, propertyID, _ in
                    Unmanaged<MP3StreamDecoder>.fromOpaque(clientData).takeUnretainedValue()
                        .propertyChanged(stream, propertyID)
                },
                { clientData, byteCount, packetCount, bytes, descriptions in
                    Unmanaged<MP3StreamDecoder>.fromOpaque(clientData).takeUnretainedValue()
                        .packets(byteCount, packetCount, bytes, descriptions)
                },
                kAudioFileMP3Type,
                &streamID
            )
            guard status == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
        }
        guard let streamID else { return }
        let status = data.withUnsafeBytes { raw in
            AudioFileStreamParseBytes(streamID, UInt32(raw.count), raw.baseAddress, [])
        }
        if let error { self.error = nil; throw error }
        guard status == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }

    private func propertyChanged(_ stream: AudioFileStreamID, _ propertyID: AudioFileStreamPropertyID) {
        guard propertyID == kAudioFileStreamProperty_ReadyToProducePackets else { return }
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioFileStreamGetProperty(stream, kAudioFileStreamProperty_DataFormat, &size, &asbd) == noErr,
              let input = AVAudioFormat(streamDescription: &asbd),
              let output = AVAudioFormat(standardFormatWithSampleRate: asbd.mSampleRate,
                                         channels: max(asbd.mChannelsPerFrame, 1)),
              let converter = AVAudioConverter(from: input, to: output) else {
            error = CocoaError(.fileReadCorruptFile)
            return
        }
        inputFormat = input
        self.converter = converter
    }

    private func packets(
        _ byteCount: UInt32, _ packetCount: UInt32, _ bytes: UnsafeRawPointer,
        _ descriptions: UnsafeMutablePointer<AudioStreamPacketDescription>?
    ) {
        guard let inputFormat, let converter, let descriptions, packetCount > 0 else { return }

        var maxPacketSize = 0
        for i in 0..<Int(packetCount) { maxPacketSize = max(maxPacketSize, Int(descriptions[i].mDataByteSize)) }
        let compressed = AVAudioCompressedBuffer(
            format: inputFormat, packetCapacity: AVAudioPacketCount(packetCount), maximumPacketSize: maxPacketSize
        )
        compressed.data.copyMemory(from: bytes, byteCount: Int(byteCount))
        compressed.packetDescriptions?.update(from: descriptions, count: Int(packetCount))
        compressed.packetCount = AVAudioPacketCount(packetCount)
        compressed.byteLength = byteCount

        let framesPerPacket = max(inputFormat.streamDescription.pointee.mFramesPerPacket, 1152)
        guard let pcm = AVAudioPCMBuffer(
            pcmFormat: converter.outputFormat, frameCapacity: framesPerPacket * packetCount
        ) else { return }

        var supplied = false
        var convertError: NSError?
        let status = converter.convert(to: pcm, error: &convertError) { _, inputStatus in
            if supplied {
                inputStatus.pointee = .noDataNow   // keep decoder state for the next chunk
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return compressed
        }
        if status == .error {
            error = convertError ?? CocoaError(.fileReadCorruptFile)
            return
        }
        if pcm.frameLength > 0 { onPCM(pcm) }
    }
}
