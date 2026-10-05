import AppKit
import CoreAudio
import AudioToolbox
import AVFoundation

// Setup, parameter changes, and stop are serialized by the worker command loop.
// Audio callbacks capture only the preallocated C transport, whose lifetime extends
// until both Core Audio and the engine have stopped.
final class SpotifyAudio: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode?
    private let eq = AVAudioUnitEQ(numberOfBands: EQBand.allCases.count)
    private var tap: AudioObjectID = 0
    private var aggregate: AudioObjectID = 0
    private var io: AudioDeviceIOProcID?
    private var transport: OpaquePointer?
    private var outputTapInstalled = false
    private var started = false
    private var appliedGains = [Double](repeating: 0, count: EQBand.allCases.count)
    private let queue = DispatchQueue(label: "spotify.eq.audio", qos: .userInteractive)
    func metrics() -> EQAudioMetrics? { transport.map(EQAudioTransportMetrics) }

    func diagnostics() -> String {
        guard let transport else { return "audio=stopped" }
        let m = EQAudioTransportMetrics(transport)
        return "capturedFrames=\(m.capturedFrames) renderedFrames=\(m.renderedFrames) inputPeak=\(m.inputPeak) outputPeak=\(m.outputPeak) queuedFrames=\(m.queuedFrames) highWaterFrames=\(m.highWaterFrames) overflowFrames=\(m.overflowFrames) underrunFrames=\(m.underrunFrames) invalidBuffers=\(m.invalidBuffers) nonfiniteSamples=\(m.nonfiniteSamples) clippedOutputSamples=\(m.clippedOutputSamples)"
    }
    init() throws {
        configureEqualizer(eq)
    }
    func setEQ(gains: [Double]) {
        guard gains.count == EQBand.allCases.count,
              gains.allSatisfy({ $0.isFinite && (-9...9).contains($0) }) else { return }
        applyEqualizerGains(eq, gains: gains, previous: appliedGains)
        appliedGains = gains
    }
    private func read(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) throws -> UInt32 {
        var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var result: UInt32 = 0; var size: UInt32 = 4
        try check(AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &result), "Read audio property")
        return result
    }
    private func check(_ status: OSStatus, _ context: String) throws {
        if status != noErr { throw NSError(domain: context, code: Int(status), userInfo: [NSLocalizedDescriptionKey: "\(context) (Core Audio \(status))"]) }
    }
    func start(onStage: (String) -> Void = { _ in }) throws {
        guard !started else { throw NSError(domain: "Audio session already used", code: 1) }
        started = true
        onStage("Looking up Spotify audio process")
        let system = AudioObjectID(kAudioObjectSystemObject)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size), "List audio processes")
        guard size >= 4, size % 4 == 0 else { throw NSError(domain: "No audio processes", code: 1) }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / 4)
        try ids.withUnsafeMutableBufferPointer { ptr in try check(AudioObjectGetPropertyData(system, &addr, 0, nil, &size, ptr.baseAddress!), "List audio processes") }
        guard let spotifyPID = NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").first?.processIdentifier,
              let process = ids.first(where: { (try? read($0, kAudioProcessPropertyPID)) == UInt32(spotifyPID) }) else {
            throw NSError(domain: "Spotify is not running", code: 1, userInfo: [NSLocalizedDescriptionKey: "Spotify audio process not found"])
        }
        let output = try read(system, kAudioHardwarePropertyDefaultOutputDevice)
        var uidAddr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var uid: CFString = "" as CFString; var uidSize = UInt32(MemoryLayout<CFString>.size)
        let uidStatus = withUnsafeMutablePointer(to: &uid) { ptr in
            AudioObjectGetPropertyData(output, &uidAddr, 0, nil, &uidSize, ptr)
        }
        try check(uidStatus, "Read output device")
        let desc = CATapDescription(stereoMixdownOfProcesses: [process])
        desc.uuid = UUID(); desc.muteBehavior = .mutedWhenTapped
        onStage("Creating process tap")
        try check(AudioHardwareCreateProcessTap(desc, &tap), "Capture Spotify")
        do {
            var fmtAddr = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var asbd = AudioStreamBasicDescription(); var fmtSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            try check(AudioObjectGetPropertyData(tap, &fmtAddr, 0, nil, &fmtSize, &asbd), "Read Spotify format")
            guard let format = AVAudioFormat(streamDescription: &asbd), format.commonFormat == .pcmFormatFloat32 else {
                throw NSError(domain: "Unsupported tap format", code: 1)
            }
            guard format.channelCount == 2 else {
                throw NSError(domain: "Unsupported Spotify channel layout", code: 1)
            }
            let description: [String: Any] = [
                kAudioAggregateDeviceNameKey: "Spotify EQ temporary tap", kAudioAggregateDeviceUIDKey: UUID().uuidString,
                kAudioAggregateDeviceMainSubDeviceKey: uid as String, kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: uid as String]],
                kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: desc.uuid.uuidString, kAudioSubTapDriftCompensationKey: true]]
            ]
            onStage("Creating aggregate audio device")
            try check(AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregate), "Create audio tap device")
            var rateAddr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyNominalSampleRate, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var rate: Double = 0
            var rateSize = UInt32(MemoryLayout<Double>.size)
            try check(AudioObjectGetPropertyData(aggregate, &rateAddr, 0, nil, &rateSize, &rate), "Read aggregate sample rate")
            guard rate.isFinite, rate > 0 else { throw NSError(domain: "Invalid aggregate sample rate", code: 1) }
            let planar = makePlaybackFormat(for: format, aggregateSampleRate: rate)
            NSLog("Spotify EQ tap format %.0f Hz, callback device %.0f Hz", format.sampleRate, rate)
            var frameAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyBufferFrameSize,
                mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var frames: UInt32 = 512
            var frameSize = UInt32(MemoryLayout<UInt32>.size)
            try check(AudioObjectGetPropertyData(aggregate, &frameAddress, 0, nil, &frameSize, &frames), "Read callback frame size")
            guard frames > 0, frames <= 16384 else { throw NSError(domain: "Unsupported callback size", code: 1) }
            // Two hardware blocks absorb scheduling jitter. Four blocks is a strict
            // upper bound; overflow is counted rather than growing playback latency.
            guard let ring = EQAudioTransportCreate(frames * 4, frames * 2) else {
                throw NSError(domain: "Cannot allocate lock-free audio transport", code: 1)
            }
            transport = ring
            let inputInterleaved = format.isInterleaved
            let source = AVAudioSourceNode(format: planar) { _, _, frameCount, output in
                EQAudioTransportRender(ring, output, frameCount)
                return noErr
            }
            self.source = source
            engine.attach(source); engine.attach(eq)
            engine.connect(source, to: eq, format: planar)
            engine.connect(eq, to: engine.mainMixerNode, format: planar)
            // This framework tap is diagnostics only; it does not feed playback.
            engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { buffer, _ in
                EQAudioTransportObserveOutput(ring, buffer.audioBufferList)
            }
            outputTapInstalled = true
            onStage("Starting playback engine")
            // Bind both capture clock and playback to the same device snapshot.
            // A default-route change is handled by rebuilding the worker session.
            guard let outputUnit = engine.outputNode.audioUnit else {
                throw NSError(domain: "Missing output audio unit", code: 1)
            }
            var playbackDevice = output
            try check(AudioUnitSetProperty(outputUnit, kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global, 0, &playbackDevice, UInt32(MemoryLayout<AudioObjectID>.size)),
                "Select playback device")
            engine.prepare(); try engine.start()
            onStage("Creating capture callback")
            try check(AudioDeviceCreateIOProcIDWithBlock(&io, aggregate, queue) { _, input, _, _, _ in
                EQAudioTransportCapture(ring, input, inputInterleaved)
            }, "Start audio callback")
            onStage("Starting capture")
            try check(AudioDeviceStart(aggregate, io), "Start Spotify capture")
        } catch { stop(); throw error }
    }
    func stop() {
        // Stop processed playback before destroying the muting tap and restoring Spotify.
        engine.stop()
        if aggregate != 0 {
            if let io { _ = AudioDeviceStop(aggregate, io); _ = AudioDeviceDestroyIOProcID(aggregate, io) }
            io = nil; _ = AudioHardwareDestroyAggregateDevice(aggregate); aggregate = 0
        }
        if tap != 0 { _ = AudioHardwareDestroyProcessTap(tap); tap = 0 }
        if outputTapInstalled { engine.mainMixerNode.removeTap(onBus: 0); outputTapInstalled = false }
        // The source block remains retained by the engine. Free the transport only
        // at deinit, after callback delivery has stopped, so diagnostic reads remain safe.

    }
    deinit { stop(); EQAudioTransportDestroy(transport) }
}
