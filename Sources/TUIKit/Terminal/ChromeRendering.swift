import Foundation

// Phase 10 — the driver half of VTG chrome: converting the framework's
// fractional-cell chrome commands into pixel geometry, and keeping the
// terminal's retained vector scene in sync frame to frame. Both pieces are
// pure so they test without a terminal (10.3, 10.7).

/// Converts fractional-cell chrome geometry into VTG canvas pixels.
///
/// The framework never sees a pixel: views emit `ChromeCommand`s in cell
/// coordinates, and the driver that owns the terminal's glyph metrics maps
/// them with one of these. Scalar sizes (corner radius, line width) are
/// fractions of the cell *height*, per the `ChromeCommand` contract.
public struct CellPixelMapper: Hashable, Sendable {
    /// Width of one text cell in canvas pixels (may be fractional).
    public var glyphWidth: Double

    /// Height of one text cell in canvas pixels (may be fractional).
    public var glyphHeight: Double

    /// Creates a mapper from glyph metrics.
    ///
    /// - Parameters:
    ///   - glyphWidth: Cell width in canvas pixels.
    ///   - glyphHeight: Cell height in canvas pixels.
    public init(glyphWidth: Double, glyphHeight: Double) {
        self.glyphWidth = glyphWidth
        self.glyphHeight = glyphHeight
    }

    /// A cell-space point in canvas pixels.
    public func point(_ point: ChromePoint) -> (x: Int, y: Int) {
        (Int((point.x * glyphWidth).rounded()), Int((point.y * glyphHeight).rounded()))
    }

    /// A cell-space rectangle in canvas pixels.
    ///
    /// Edges are rounded independently so adjacent rectangles (gradient
    /// strips) stay seamless — width is the distance between the rounded
    /// edges, not a separately rounded width.
    public func rect(_ rect: ChromeRect) -> (x: Int, y: Int, width: Int, height: Int) {
        let x0 = Int((rect.x * glyphWidth).rounded())
        let y0 = Int((rect.y * glyphHeight).rounded())
        let x1 = Int((rect.maxX * glyphWidth).rounded())
        let y1 = Int((rect.maxY * glyphHeight).rounded())
        return (x0, y0, max(0, x1 - x0), max(0, y1 - y0))
    }

    /// A scalar size (radius, line width — cell-height units) in pixels.
    ///
    /// Non-zero inputs never collapse below one pixel.
    public func scalar(_ value: Double) -> Int {
        guard value > 0 else {
            return 0
        }

        return max(1, Int((value * glyphHeight).rounded()))
    }
}

/// Diffs consecutive chrome frames for the terminal's retained scene.
///
/// Re-sending an id updates a retained object **in place — keeping its
/// original stacking**. That makes in-place updates correct only while the
/// frame's draw order is unchanged; when the order changes (a window was
/// raised, opened, or closed), the scene must be rebuilt or chrome would
/// stack differently than the cells composited on top of it. This planner
/// makes that call — pure, so it tests without a terminal.
public enum ChromeSceneReconciler {
    /// What a driver should send for one chrome frame.
    public enum Plan: Hashable, Sendable {
        /// Nothing changed — write nothing.
        case unchanged

        /// Same ids in the same order: re-send only the commands whose
        /// content changed; stacking is already correct.
        case update(draw: [ChromeCommand])

        /// Structure changed: delete every previously retained id, then
        /// draw the whole current frame so stacking matches draw order.
        case rebuild(delete: [String])
    }

    /// Plans the retained-scene writes for a new frame.
    ///
    /// - Parameters:
    ///   - previous: Commands the terminal currently retains, in draw order.
    ///   - current: Commands about to be drawn, in draw order.
    /// - Returns: The cheapest plan that keeps the scene equal to `current`.
    public static func plan(previous: [ChromeCommand], current: [ChromeCommand]) -> Plan {
        guard previous != current else {
            return .unchanged
        }

        guard previous.map(\.id) == current.map(\.id) else {
            // Deletions follow the previous draw order, each id once.
            var seen = Set<String>()
            var deletions: [String] = []

            for command in previous where seen.insert(command.id).inserted {
                deletions.append(command.id)
            }

            return .rebuild(delete: deletions)
        }

        let changed = zip(current, previous).compactMap { new, old in
            new == old ? nil : new
        }

        return .update(draw: changed)
    }
}

/// Builds VTG path payloads for pie/donut sectors — pure geometry, so the
/// cubic arc approximation tests without a terminal.
///
/// Chart convention throughout: angles in radians, 0 at 12 o'clock,
/// increasing clockwise. VTG paths have no arc command, so arcs become
/// cubic Béziers, one segment per quarter turn (the standard k = 4/3·tan(Δ/4)
/// approximation — under 0.03% radial error at 90°).
public enum ChromeSectorPath {
    /// A point on the circle at `angle` (12 o'clock = 0, clockwise).
    static func point(centerX: Double, centerY: Double, radius: Double, angle: Double) -> (x: Double, y: Double) {
        (centerX + radius * sin(angle), centerY - radius * cos(angle))
    }

    /// Cubic segments approximating the arc from `start` to `end`, as path
    /// text ("C c1x c1y c2x c2y x y" per segment), starting from the arc's
    /// start point (which the caller has already moved/lined to).
    ///
    /// - Parameter clockwise: The direction travelled (an inner donut arc
    ///   walks back anticlockwise).
    static func arcSegments(
        centerX: Double, centerY: Double, radius: Double,
        from start: Double, to end: Double
    ) -> String {
        let total = end - start
        let segments = max(1, Int((abs(total) / (Double.pi / 2)).rounded(.up)))
        let step = total / Double(segments)
        let k = 4.0 / 3.0 * tan(abs(step) / 4) * (step < 0 ? -1 : 1)
        var pieces: [String] = []

        for segment in 0..<segments {
            let a0 = start + step * Double(segment)
            let a1 = a0 + step
            let p0 = point(centerX: centerX, centerY: centerY, radius: radius, angle: a0)
            let p1 = point(centerX: centerX, centerY: centerY, radius: radius, angle: a1)

            // Tangents at the endpoints (clockwise travel: d/dθ of the
            // parameterisation above).
            let t0 = (x: cos(a0), y: sin(a0))
            let t1 = (x: cos(a1), y: sin(a1))

            let c1 = (x: p0.x + k * radius * t0.x, y: p0.y + k * radius * t0.y)
            let c2 = (x: p1.x - k * radius * t1.x, y: p1.y - k * radius * t1.y)

            pieces.append("C \(Int(c1.x.rounded())) \(Int(c1.y.rounded())) \(Int(c2.x.rounded())) \(Int(c2.y.rounded())) \(Int(p1.x.rounded())) \(Int(p1.y.rounded()))")
        }

        return pieces.joined(separator: " ")
    }

    /// The full closed sector path: outer arc clockwise, then either back
    /// along the inner arc (a donut ring) or to the center (a pie slice).
    public static func payload(
        centerX: Double, centerY: Double,
        radius: Double, innerRadius: Double,
        start: Double, end: Double
    ) -> String {
        let outerStart = point(centerX: centerX, centerY: centerY, radius: radius, angle: start)
        var path = "M \(Int(outerStart.x.rounded())) \(Int(outerStart.y.rounded())) "
        path += arcSegments(centerX: centerX, centerY: centerY, radius: radius, from: start, to: end)

        if innerRadius > 0 {
            let innerEnd = point(centerX: centerX, centerY: centerY, radius: innerRadius, angle: end)
            path += " L \(Int(innerEnd.x.rounded())) \(Int(innerEnd.y.rounded())) "
            path += arcSegments(centerX: centerX, centerY: centerY, radius: innerRadius, from: end, to: start)
        } else {
            path += " L \(Int(centerX.rounded())) \(Int(centerY.rounded()))"
        }

        return path + " Z"
    }
}
