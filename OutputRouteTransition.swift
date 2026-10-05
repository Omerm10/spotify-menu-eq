import Foundation

struct OutputRoute: Equatable {
    let id: UInt32
    let sampleRate: Double
}

enum OutputRouteTransition {
    enum Action: Equatable { case none, stop, restart }

    static func action(previous: UInt32?, current: UInt32?, eqRequested: Bool) -> Action {
        guard eqRequested, previous != current else { return .none }
        return current == nil ? .stop : .restart
    }

    static func action(previous: OutputRoute?, current: OutputRoute?, eqRequested: Bool) -> Action {
        guard eqRequested, previous != current else { return .none }
        return current == nil ? .stop : .restart
    }
}
