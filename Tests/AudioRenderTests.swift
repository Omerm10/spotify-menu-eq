import AVFoundation
import Foundation

@main struct AudioRenderTests {
    static func main() throws {
        for rate in [44100.0, 48000.0] {
            let engine = AVAudioEngine()
            let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
            let transport = EQAudioTransportCreate(4096, 1024)!
            let source = AVAudioSourceNode(format: format) { _, _, frames, output in
                EQAudioTransportRender(transport, output, frames)
                return 0
            }
            let eq = AVAudioUnitEQ(numberOfBands: EQBand.allCases.count)
            configureEqualizer(eq)
            applyEqualizerGains(eq, gains: [0,0,0,0,0], previous: [0,0,0,0,0])
            engine.attach(source); engine.attach(eq)
            engine.connect(source, to: eq, format: format)
            engine.connect(eq, to: engine.mainMixerNode, format: format)
            try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 512)
            let input = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 2048)!
            var captured = 0
            func capture(_ count: Int) {
                input.frameLength = UInt32(count)
                for i in 0..<count {
                    let sample = Float(sin(Double(captured+i) * 2 * Double.pi * 997 / rate) * 0.25)
                    input.floatChannelData![0][i] = sample
                    input.floatChannelData![1][i] = -sample
                }
                EQAudioTransportCapture(transport, input.audioBufferList, false)
                captured += count
            }
            capture(2048)
            try engine.start()
            let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512)!
            var maxError: Float = 0
            for block in 0..<200 {
                let status = try engine.renderOffline(512, to: output)
                precondition(status == .success)
                EQAudioTransportObserveOutput(transport, output.audioBufferList)
                for i in 0..<512 {
                    let expected = Float(sin(Double(block*512+i) * 2 * Double.pi * 997 / rate) * 0.25)
                    maxError = max(maxError, abs(output.floatChannelData![0][i]-expected))
                    maxError = max(maxError, abs(output.floatChannelData![1][i]+expected))
                }
                capture(512)
            }
            engine.stop()
            let metrics = EQAudioTransportMetrics(transport)
            print("Render rate=\(Int(rate)) frames=\(metrics.renderedFrames) maxFlatError=\(maxError) underrun=\(metrics.underrunFrames) overflow=\(metrics.overflowFrames)")
            precondition(maxError < 0.000001 && metrics.underrunFrames == 0 && metrics.overflowFrames == 0)
            EQAudioTransportDestroy(transport)
        }
    }
}
