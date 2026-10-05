import Foundation

@main struct OutputRouteTests {
    static func main() {
        precondition(OutputRouteTransition.action(previous: nil, current: 10, eqRequested: true) == .restart)
        precondition(OutputRouteTransition.action(previous: 10, current: 10, eqRequested: true) == .none)
        precondition(OutputRouteTransition.action(previous: 10, current: 20, eqRequested: false) == .none)
        precondition(OutputRouteTransition.action(previous: 10, current: 20, eqRequested: true) == .restart)
        precondition(OutputRouteTransition.action(previous: 10, current: nil, eqRequested: true) == .stop)
        let original = OutputRoute(id: 10, sampleRate: 44_100)
        let changed = OutputRoute(id: 10, sampleRate: 48_000)
        precondition(OutputRouteTransition.action(previous: original, current: changed, eqRequested: true) == .restart)
        precondition(OutputRouteTransition.action(previous: original, current: nil, eqRequested: true) == .stop)
        precondition(OutputRouteTransition.action(previous: nil, current: original, eqRequested: true) == .restart)
        precondition(OutputRouteTransition.action(previous: nil, current: original, eqRequested: false) == .none)
        print("Output route loss, same-device recovery, format change, and cancellation passed")
    }
}
