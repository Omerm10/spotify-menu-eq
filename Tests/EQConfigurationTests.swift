import Foundation
import AVFoundation

@main struct EQConfigurationTests {
    static func main() {
        precondition(EQBand.allCases.count == 5)
        precondition(EQBand.allCases.map(\.frequency) == [80, 250, 1000, 4000, 10000])
        precondition(EQPreset.all.count == 6)
        for preset in EQPreset.all {
            precondition(preset.gains.count == EQBand.allCases.count)
            precondition(preset.gains.allSatisfy { (-9...9).contains($0) })
        }
        precondition(EQPreset.all.first?.name == "Flat")
        precondition(EQPreset.all.first?.gains == [0, 0, 0, 0, 0])
        precondition(EQPreset.all.first(where: { $0.name == "Voice Forward" })!.gains[2] > 0)
        precondition(preampGain(gains: [0, 0, 0, 0, 0]) == 0)
        precondition(preampGain(gains: [6, 3, 0, 0, 0]) <= -6)
        precondition(preampGain(gains: [-6, -3, -1, -2, -3]) == 0)
        let wire = EQCommand.encode([1, -2, 0, 3, -4])
        precondition(EQCommand.decode(wire) == [1, -2, 0, 3, -4])
        precondition(EQCommand.decode("SET 1 2") == nil)
        precondition(EQCommand.decode("SET 1 2 3 4 NaN") == nil)
        print("Five-band configuration and presets passed")
    }
}
