import CoreGraphics

// Shape-preserving interpolation of band gains, not a measured frequency response.
enum EqualizerCurve {
    struct Segment {
        let start: CGPoint
        let control1: CGPoint
        let control2: CGPoint
        let end: CGPoint
    }

    static func segments(through points: [CGPoint]) -> [Segment] {
        guard points.count > 1,
              points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return [] }
        let widths = zip(points, points.dropFirst()).map { $1.x - $0.x }
        guard widths.allSatisfy({ $0 > 0 }) else { return [] }
        let slopes = zip(points, points.dropFirst()).enumerated().map { index, pair in
            (pair.1.y - pair.0.y) / widths[index]
        }
        var tangents = [CGFloat](repeating: 0, count: points.count)
        tangents[0] = slopes[0]
        tangents[points.count - 1] = slopes[slopes.count - 1]
        for index in 1..<(points.count - 1) {
            let before = slopes[index - 1]
            let after = slopes[index]
            // A turning point or a flat interval needs a horizontal tangent.
            guard (before > 0 && after > 0) || (before < 0 && after < 0) else { continue }
            let weight1 = 2 * widths[index] + widths[index - 1]
            let weight2 = widths[index] + 2 * widths[index - 1]
            tangents[index] = (weight1 + weight2) / (weight1 / before + weight2 / after)
        }
        return widths.indices.map { index in
            let start = points[index]
            let end = points[index + 1]
            let offset = widths[index] / 3
            return Segment(start: start,
                           control1: CGPoint(x: start.x + offset, y: start.y + tangents[index] * offset),
                           control2: CGPoint(x: end.x - offset, y: end.y - tangents[index + 1] * offset),
                           end: end)
        }
    }
}
