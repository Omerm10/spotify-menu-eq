import AVFoundation
import Foundation

@main struct AudioDSPTests {
    static func main() throws {
        var largest: Float = 0
        for rate in [44100.0, 48000.0] {
            for gains in EQPreset.all.map(\.gains) + [[9,9,9,9,9],[-9,-9,-9,-9,-9]] {
                let engine = AVAudioEngine()
                let player = AVAudioPlayerNode()
                let eq = AVAudioUnitEQ(numberOfBands: EQBand.allCases.count)
                let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
                configureEqualizer(eq)
                applyEqualizerGains(eq, gains: gains, previous: [0,0,0,0,0])
                engine.attach(player); engine.attach(eq)
                engine.connect(player, to: eq, format: format)
                engine.connect(eq, to: engine.mainMixerNode, format: format)
                try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 1024)
                let count = Int(rate)
                let input = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: UInt32(count))!
                input.frameLength = UInt32(count)
                for i in 0..<count {
                    // Full-scale logarithmic sweep checks overlap throughout the band.
                    let t = Double(i) / rate
                    let phase = 2 * Double.pi * 20 * (pow(1000,t) - 1) / log(1000)
                    let value = Float(0.99 * sin(phase))
                    input.floatChannelData![0][i] = value
                    input.floatChannelData![1][i] = -value
                }
                player.scheduleBuffer(input)
                try engine.start(); player.play()
                let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
                var remaining = count
                var peak: Float = 0
                while remaining > 0 {
                    let frames = min(remaining, 1024)
                    let status = try engine.renderOffline(UInt32(frames), to: output)
                    precondition(status == .success)
                    for channel in 0..<2 { for i in 0..<frames {
                        let value = output.floatChannelData![channel][i]
                        precondition(value.isFinite)
                        peak = max(peak, abs(value))
                    }}
                    remaining -= frames
                }
                largest = max(largest, peak)
                print("DSP rate=\(Int(rate)) gains=\(gains) peak=\(peak)")
                engine.stop()
            }
        }
        precondition(largest < 1, "Sweep clips")
        print("DSP sweep maximum=\(largest)")
    }
}
