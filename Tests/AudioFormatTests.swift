import Foundation
import AVFoundation

@main struct AudioFormatTests {
    static func main() {
        let mismatched = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 2, interleaved: true)!
        let output = makePlaybackFormat(for: mismatched, aggregateSampleRate: 44100)
        precondition(output.sampleRate == 44100, "The callback clock, not the tap's advertised rate, controls playback")
        precondition(output.channelCount == 2 && !output.isInterleaved)

        let matched = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 2, interleaved: true)!
        precondition(makePlaybackFormat(for: matched, aggregateSampleRate: 48000).sampleRate == 48000)
        precondition(preampGain(gains: [0, 0, 0, 0, 0]) == 0)
        precondition(preampGain(gains: [12, -12, 0, 0, 0]) == -12)
        precondition(preampGain(gains: [-6, -3, 0, 0, 0]) == 0)
        precondition(preampGain(gains: [3, 6, 0, 0, 0]) <= -6)
        print("Audio format and headroom tests passed")
    }
}
