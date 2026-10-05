import CoreGraphics

@main
struct EqualizerCurveTests {
    static func main() {
        let fixtures: [[CGFloat]] = [
            [0, 0, 0, 0, 0], [9, -9, 9, -9, 9], [-9, 9, -9, 9, -9],
            [5, -1.3, -2, 0, 0], [-9, -8.99, 0, 8.99, 9], [9, 9, -9, -9, 9]
        ]
        for gains in fixtures {
            check(gains, positions: [0, 1, 2, 3, 4])
            check(gains, positions: [0, 0.1, 1, 4, 10])
        }
        // Exhaustively cover flat runs, turning points and extreme steps.
        let levels: [CGFloat] = [-9, -8.9, 0, 8.9, 9]
        for a in levels { for b in levels { for c in levels { for d in levels { for e in levels {
            check([a, b, c, d, e], positions: [0, 1, 2, 3, 4])
        } } } } }
        let line = EqualizerCurve.segments(through: [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 2, y: 2)])
        assert(abs(line[0].control2.y - 2 / CGFloat(3)) < 1e-10, "A straight ramp must remain straight")
        assert(EqualizerCurve.segments(through: []).isEmpty)
        assert(EqualizerCurve.segments(through: [CGPoint.zero]).isEmpty)
        print("Equalizer curve tests passed.")
    }

    private static func check(_ gains: [CGFloat], positions: [CGFloat]) {
        let points = zip(positions, gains).map { CGPoint(x: $0, y: $1) }
        let segments = EqualizerCurve.segments(through: points)
        assert(segments.count == points.count - 1)
        for (index, segment) in segments.enumerated() {
            assert(segment.start == points[index] && segment.end == points[index + 1])
            let lower = min(segment.start.y, segment.end.y) - 1e-10
            let upper = max(segment.start.y, segment.end.y) + 1e-10
            for sample in 0...100 {
                let t = CGFloat(sample) / 100
                let u = 1 - t
                let y = u * u * u * segment.start.y + 3 * u * u * t * segment.control1.y
                    + 3 * u * t * t * segment.control2.y + t * t * t * segment.end.y
                assert(y.isFinite && y >= lower && y <= upper, "Curve overshot its band heights")
            }
            if index > 0 {
                let previous = segments[index - 1]
                let incoming = (previous.end.y - previous.control2.y) / (previous.end.x - previous.control2.x)
                let outgoing = (segment.control1.y - segment.start.y) / (segment.control1.x - segment.start.x)
                assert(abs(incoming - outgoing) < 1e-9, "Curve has a corner at a band")
            }
        }
    }
}
