import AVFoundation

// Core Audio's tap can advertise 48 kHz while its aggregate IO callback is
// clocked by a 44.1 kHz output device. The callback buffers must be scheduled
// at the aggregate's actual rate or pitch and timing are wrong.
func makePlaybackFormat(for tap: AVAudioFormat, aggregateSampleRate: Double) -> AVAudioFormat {
    precondition(aggregateSampleRate > 0)
    return AVAudioFormat(commonFormat: .pcmFormatFloat32,
                         sampleRate: aggregateSampleRate,
                         channels: tap.channelCount,
                         interleaved: false)!
}

// Adjacent positive bands can overlap. Reserve headroom for the two largest
// boosts without attenuating all-negative or Flat settings.
func preampGain(gains: [Double]) -> Float {
    -Float(gains.filter { $0 > 0 }.sorted(by: >).prefix(2).reduce(0, +))
}

// Shared by the live graph and offline signal tests.
func configureEqualizer(_ eq: AVAudioUnitEQ) {
    for band in EQBand.allCases {
        let parameter = eq.bands[band.rawValue]
        parameter.filterType = band.filterType
        parameter.frequency = band.frequency
        parameter.bandwidth = 1
        parameter.bypass = false
    }
}

func applyEqualizerGains(_ eq: AVAudioUnitEQ, gains: [Double], previous: [Double]) {
    // Reserve headroom before exposing boosted filters. The intermediate curve can
    // contain positive bands from both presets until all setters have completed.
    let transition = zip(previous, gains).map { max($0, $1) }
    eq.globalGain = min(preampGain(gains: previous), preampGain(gains: transition))
    for band in EQBand.allCases { eq.bands[band.rawValue].gain = Float(gains[band.rawValue]) }
    eq.globalGain = preampGain(gains: gains)
}
