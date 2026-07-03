/// Shared mutable render destination for one frame.
///
/// A frame render creates one target; every `Painter` handed to the view
/// tree writes into it. Views never see the target directly — only painters.
@MainActor
final class RenderTarget {
    /// Cells composed so far this frame.
    var buffer: CellBuffer

    /// Creates a target of the given size filled with blank cells.
    ///
    /// - Parameter size: Frame size in cells.
    init(size: Size) {
        self.buffer = CellBuffer(size: size)
    }
}

/// Drawing surface handed to a view's `draw(_:)`.
///
/// The painter is where two framework contracts are enforced mechanically
/// rather than by convention:
///
/// - **Local coordinates:** a view draws at its own (0, 0); the painter's
///   `origin` translates every write into buffer coordinates. Views never
///   see, or need, their absolute position.
/// - **Clipping:** every write is clipped against `clip`, which is the
///   intersection of every ancestor's frame. A child cannot draw outside its
///   parent's viewport no matter what coordinates it uses.
///
/// ```text
///   view-local point ──(+ origin)──> buffer point ──(∩ clip)──> cell write
/// ```
///
/// Painters for subviews are derived with `forSubview(frame:)`, which
/// composes the translation and narrows the clip.
@MainActor
public struct Painter {
    private let target: RenderTarget

    /// Translation from view-local to buffer coordinates.
    public let origin: Point

    /// Writable region in buffer coordinates.
    public let clip: Rect

    /// Theme base colors substituted for `.standard` in written cells.
    ///
    /// This is how a `Theme` cascades mechanically: views draw with
    /// `.standard` colors as always, and the painter resolves them against
    /// the active theme's palette. Explicit colors pass through untouched.
    public let base: CellStyle

    /// Creates a painter.
    ///
    /// - Parameters:
    ///   - target: Frame render destination.
    ///   - origin: Translation from view-local to buffer coordinates.
    ///   - clip: Writable region in buffer coordinates.
    ///   - base: Theme base colors for `.standard` substitution.
    init(target: RenderTarget, origin: Point, clip: Rect, base: CellStyle = CellStyle()) {
        self.target = target
        self.origin = origin
        self.clip = clip
        self.base = base
    }

    /// Writes one cell at a view-local point, subject to clipping.
    ///
    /// - Parameters:
    ///   - cell: Cell to write.
    ///   - point: View-local position.
    public func set(_ cell: TerminalCell, at point: Point) {
        let destination = point + origin

        guard clip.contains(destination) else {
            return
        }

        var resolved = cell

        if resolved.style.foreground == .standard {
            resolved.style.foreground = base.foreground
        }

        if resolved.style.background == .standard {
            resolved.style.background = base.background
        }

        target.buffer[destination] = resolved
    }

    /// Writes text starting at a view-local point, subject to clipping.
    ///
    /// Text never wraps; clipped characters are dropped.
    ///
    /// - Parameters:
    ///   - text: Text to write.
    ///   - point: View-local position of the first character.
    ///   - style: Style applied to every written cell.
    public func write(_ text: String, at point: Point, style: CellStyle = .default) {
        var x = point.x

        for character in text {
            set(TerminalCell(character: character, style: style), at: Point(x: x, y: point.y))
            x += 1
        }
    }

    /// Fills a view-local rectangle, subject to clipping.
    ///
    /// - Parameters:
    ///   - rect: View-local rectangle to fill.
    ///   - cell: Cell to fill with.
    public func fill(_ rect: Rect, with cell: TerminalCell) {
        for y in rect.minY..<rect.maxY {
            for x in rect.minX..<rect.maxX {
                set(cell, at: Point(x: x, y: y))
            }
        }
    }

    /// Draws a single-line box on a view-local rectangle, subject to clipping.
    ///
    /// - Parameters:
    ///   - rect: View-local rectangle to outline.
    ///   - style: Style for the border cells.
    public func drawBox(_ rect: Rect, style: CellStyle = .default) {
        guard rect.size.width >= 2, rect.size.height >= 2 else {
            return
        }

        let x0 = rect.minX
        let x1 = rect.maxX - 1
        let y0 = rect.minY
        let y1 = rect.maxY - 1

        set(TerminalCell(character: "┌", style: style), at: Point(x: x0, y: y0))
        set(TerminalCell(character: "┐", style: style), at: Point(x: x1, y: y0))
        set(TerminalCell(character: "└", style: style), at: Point(x: x0, y: y1))
        set(TerminalCell(character: "┘", style: style), at: Point(x: x1, y: y1))

        for x in (x0 + 1)..<x1 {
            set(TerminalCell(character: "─", style: style), at: Point(x: x, y: y0))
            set(TerminalCell(character: "─", style: style), at: Point(x: x, y: y1))
        }

        for y in (y0 + 1)..<y1 {
            set(TerminalCell(character: "│", style: style), at: Point(x: x0, y: y))
            set(TerminalCell(character: "│", style: style), at: Point(x: x1, y: y))
        }
    }

    /// Derives the painter for a subview.
    ///
    /// The subview's origin composes with this painter's translation, and
    /// the clip narrows to the subview's frame — this is the mechanical
    /// enforcement of the clipping contract.
    ///
    /// - Parameter frame: Subview frame in this painter's local coordinates.
    /// - Returns: Painter for the subview's local coordinate space.
    public func forSubview(frame: Rect) -> Painter {
        let subviewOrigin = origin + frame.origin
        let frameInBuffer = Rect(origin: subviewOrigin, size: frame.size)

        return Painter(
            target: target,
            origin: subviewOrigin,
            clip: clip.intersection(frameInBuffer),
            base: base
        )
    }

    /// Derives a painter whose `.standard` colors resolve to a new base.
    ///
    /// - Parameter newBase: Theme base colors for the subtree.
    /// - Returns: Painter with the same translation and clip.
    func withBase(_ newBase: CellStyle) -> Painter {
        Painter(target: target, origin: origin, clip: clip, base: newBase)
    }
}
