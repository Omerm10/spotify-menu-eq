import Foundation
import AVFoundation

enum EQBand: Int, CaseIterable, Identifiable {
    case bass, lowMid, mid, presence, air
    var id: Int { rawValue }
    var frequency: Float {
        switch self {
        case .bass: 80
        case .lowMid: 250
        case .mid: 1000
        case .presence: 4000
        case .air: 10000
        }
    }
    var label: String {
        switch self {
        case .bass: "Bass · 80 Hz"
        case .lowMid: "Low mids · 250 Hz"
        case .mid: "Mids · 1 kHz"
        case .presence: "Presence · 4 kHz"
        case .air: "Air · 10 kHz"
        }
    }
    var filterType: AVAudioUnitEQFilterType {
        switch self {
        case .bass: .lowShelf
        case .air: .highShelf
        default: .parametric
        }
    }
}

struct EQPreset: Identifiable {
    let name: String
    let gains: [Double]
    var id: String { name }

    static let all: [EQPreset] = [
        .init(name: "Flat", gains: [0, 0, 0, 0, 0]),
        .init(name: "Warm", gains: [3, 1, -1, -1, -2]),
        .init(name: "Bass Boost", gains: [5, 2, -2, 0, 0]),
        .init(name: "Voice Forward", gains: [-2, -1, 2, 3, 0]),
        .init(name: "Clarity", gains: [-2, -1, 0, 2, 3]),
        .init(name: "Soft", gains: [1, 0, 0, -2, -3])
    ]
}

struct EQCommand {
    static func encode(_ gains: [Double]) -> String {
        precondition(gains.count == EQBand.allCases.count)
        return "SET " + gains.map { String($0) }.joined(separator: " ") + "\n"
    }

    static func decode(_ line: String) -> [Double]? {
        let parts = line.split(whereSeparator: \.isWhitespace)
        guard parts.count == EQBand.allCases.count + 1, parts[0] == "SET" else { return nil }
        let values = parts.dropFirst().compactMap { Double($0) }
        guard values.count == EQBand.allCases.count,
              values.allSatisfy({ $0.isFinite && (-9...9).contains($0) }) else { return nil }
        return values
    }
}
