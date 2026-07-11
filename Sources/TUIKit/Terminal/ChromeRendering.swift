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
