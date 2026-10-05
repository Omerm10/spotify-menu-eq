import AVFoundation
import Foundation

@main struct AudioTransitionTests {
    static func main() throws {
        for rate in [44100.0, 48000.0] {
            let engine = AVAudioEngine()
            let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
            let player = AVAudioPlayerNode()
            let eq = AVAudioUnitEQ(numberOfBands: EQBand.allCases.count)
            configureEqualizer(eq)
            engine.attach(player); engine.attach(eq)
            engine.connect(player, to: eq, format: format)
            engine.connect(eq, to: engine.mainMixerNode, format: format)
            try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 256)
            let count = 256 * 400
            let input = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: UInt32(count))!
            input.frameLength = UInt32(count)
            var seed: UInt64 = 1
            for i in 0..<count {
                seed = seed &* 6364136223846793005 &+ 1
                let noise = (Double(seed >> 32) / Double(UInt32.max) * 2 - 1) * 0.25
                var signal = noise
                for frequency in [80.0, 1000.0, 4000.0, 10000.0] {
                    signal += sin(Double(i) * 2 * Double.pi * frequency / rate) * 0.185
                }
                input.floatChannelData![0][i] = Float(signal)
                input.floatChannelData![1][i] = Float(-signal)
            }
            player.scheduleBuffer(input)
            try engine.start(); player.play()
            let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 256)!
            let settings = EQPreset.all.map(\.gains) + [[9,9,9,9,9],[-9,-9,-9,-9,-9],[9,-9,9,-9,9]]
            var previous = [Double](repeating: 0, count: 5)
            var peak: Float = 0
            for block in 0..<400 {
                let gains = settings[block % settings.count]
                applyEqualizerGains(eq, gains: gains, previous: previous)
                previous = gains
                let status = try engine.renderOffline(256, to: output)
                precondition(status == .success)
                for c in 0..<2 { for i in 0..<256 {
                    let sample = output.floatChannelData![c][i]
                    precondition(sample.isFinite)
                    peak = max(peak, abs(sample))
                }}
            }
            engine.stop()
            print("Preset transitions rate=\(Int(rate)) changes=400 peak=\(peak)")
            precondition(peak < 1, "Preset transition clipping")
        }
    }
}
