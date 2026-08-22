/// Shared mutable render destination for one frame.
///
/// A frame render creates one target; every `Painter` handed to the view
/// tree writes into it. Views never see the target directly — only painters.
@MainActor
final class RenderTarget {
    /// Cells composed so far this frame.
    var buffer: CellBuffer

    /// Whether views may emit vector chrome this frame (Phase 10). Off, the
    /// painter carries no `ChromeSurface` and rendering is exactly rev 1.
    let chromeEnabled: Bool

    /// Vector chrome commands composed so far this frame, in draw order
    /// (back to front, like cells).
    private(set) var chrome: [ChromeCommand] = []

    /// Creates a target of the given size filled with blank cells.
    ///
    /// - Parameters:
    ///   - size: Frame size in cells.
    ///   - chromeEnabled: Whether views may emit vector chrome.
    init(size: Size, chromeEnabled: Bool = false) {
        self.buffer = CellBuffer(size: size)
        self.chromeEnabled = chromeEnabled
    }

    /// Collects one chrome command (called by `ChromeSurface`).
    func appendChrome(_ command: ChromeCommand) {
        chrome.append(command)
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

    // Retained-scene id prefix for the view currently drawing (stamped by
    // `renderTree`), so chrome object ids are view-scoped.
    private let chromeOwnerID: String

    // Whether a view up the chain opted its subtree out of vector chrome
    // (`TUIView.suppressesVectorChrome`) — the painter then reports no
    // surface even on a VTG terminal.
    private let chromeSuppressed: Bool

    /// The vector chrome surface, when the frame is chrome-enabled.
    ///
    /// `nil` on plain terminals — and inside subtrees that set
    /// ``TUIView/suppressesVectorChrome``. Views guard chrome drawing with
    /// `if let chrome = painter.chrome`, and the cell path stays the
    /// universal fallback (Phase 10 contract), so suppression needs nothing
    /// from the view: it simply takes its own fallback branch.
    public var chrome: ChromeSurface? {
        guard target.chromeEnabled, !chromeSuppressed else {
            return nil
        }

        return ChromeSurface(target: target, origin: origin, clip: clip, ownerID: chromeOwnerID)
    }

    /// Creates a painter.
    ///
    /// - Parameters:
    ///   - target: Frame render destination.
    ///   - origin: Translation from view-local to buffer coordinates.
    ///   - clip: Writable region in buffer coordinates.
    ///   - base: Theme base colors for `.standard` substitution.
    ///   - chromeOwnerID: Retained-scene id prefix for chrome commands.
    ///   - chromeSuppressed: Whether the subtree opted out of chrome.
    init(
        target: RenderTarget,
        origin: Point,
        clip: Rect,
        base: CellStyle = CellStyle(),
        chromeOwnerID: String = "root",
        chromeSuppressed: Bool = false
    ) {
        self.target = target
        self.origin = origin
        self.clip = clip
        self.base = base
        self.chromeOwnerID = chromeOwnerID
        self.chromeSuppressed = chromeSuppressed
    }

    /// Writes one cell at a view-local point, subject to clipping.
    ///
    /// - Parameters:
    ///   - cell: Cell to write.
    ///   - point: TUIView-local position.
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
    ///   - point: TUIView-local position of the first character.
    ///   - style: Style applied to every written cell.
    public func write(_ text: String, at point: Point, style: CellStyle = .default) {
        var x = point.x

        for character in text {
            let width = DisplayWidth.of(character)

            // Zero-width marks ride along in the cell they modify rather than
            // claiming one of their own — a combining accent is part of the
            // letter before it, not a column after it.
            guard width > 0 else {
                continue
            }

            set(TerminalCell(character: character, style: style), at: Point(x: x, y: point.y))

            // A wide glyph OWNS the next column. Saying so is what stops the
            // rest of the row being pushed one column right by a terminal
            // whose cursor advanced two.
            if width == 2 {
                set(
                    TerminalCell(character: " ", style: style, isContinuation: true),
                    at: Point(x: x + 1, y: point.y)
                )
            }

            x += width
        }
    }

    /// Fills a view-local rectangle, subject to clipping.
    ///
    /// - Parameters:
    ///   - rect: TUIView-local rectangle to fill.
    ///   - cell: Cell to fill with.
    public func fill(_ rect: Rect, with cell: TerminalCell) {
        for y in rect.minY..<rect.maxY {
            for x in rect.minX..<rect.maxX {
                set(cell, at: Point(x: x, y: y))
            }
        }
    }

    /// Draws a box on a view-local rectangle, subject to clipping.
    ///
    /// - Parameters:
    ///   - rect: TUIView-local rectangle to outline.
    ///   - style: Style for the border cells.
    ///   - border: Box-drawing variant; `.none` draws nothing.
    public func drawBox(_ rect: Rect, style: CellStyle = .default, border: BorderStyle = .single) {
        guard rect.size.width >= 2, rect.size.height >= 2,
              let characters = border.characters else {
            return
        }

        let x0 = rect.minX
        let x1 = rect.maxX - 1
        let y0 = rect.minY
        let y1 = rect.maxY - 1

        set(TerminalCell(character: characters.topLeft, style: style), at: Point(x: x0, y: y0))
        set(TerminalCell(character: characters.topRight, style: style), at: Point(x: x1, y: y0))
        set(TerminalCell(character: characters.bottomLeft, style: style), at: Point(x: x0, y: y1))
        set(TerminalCell(character: characters.bottomRight, style: style), at: Point(x: x1, y: y1))

        for x in (x0 + 1)..<x1 {
            set(TerminalCell(character: characters.horizontal, style: style), at: Point(x: x, y: y0))
            set(TerminalCell(character: characters.horizontal, style: style), at: Point(x: x, y: y1))
        }

        for y in (y0 + 1)..<y1 {
            set(TerminalCell(character: characters.vertical, style: style), at: Point(x: x0, y: y))
            set(TerminalCell(character: characters.vertical, style: style), at: Point(x: x1, y: y))
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
            base: base,
            chromeOwnerID: chromeOwnerID,
            chromeSuppressed: chromeSuppressed
        )
    }

    /// A painter writing over the terminal's DEFAULT background instead of
    /// the theme's — the door vector chrome shows through.
    ///
    /// Chrome on a VectorTerminal renders *under* the text and is visible
    /// only where a cell keeps the terminal's default background. A view
    /// that draws chrome fills the region it wants transparent with
    /// `withBase(CellStyle()).fill(rect, with: .blank)` first, then draws its
    /// text on top; the charts, `Canvas`, and the sibling packages (diagrams)
    /// all do exactly this.
    ///
    /// - Parameter base: The base style the new painter substitutes for
    ///   `.standard`; `CellStyle()` means the terminal's own colours.
    /// - Returns: A painter over the same target with that base.
    public func withBase(_ newBase: CellStyle) -> Painter {
        Painter(
            target: target,
            origin: origin,
            clip: clip,
            base: newBase,
            chromeOwnerID: chromeOwnerID,
            chromeSuppressed: chromeSuppressed
        )
    }

    /// Derives a painter whose chrome object ids are scoped to a view.
    ///
    /// `renderTree` stamps each view's identity before its `draw(_:)`, so
    /// two views using the same chrome key never collide in the terminal's
    /// retained scene.
    ///
    /// - Parameter ownerID: The drawing view's stable id prefix.
    /// - Returns: Painter with the same translation, clip, and base.
    func withChromeOwner(_ ownerID: String) -> Painter {
        Painter(
            target: target,
            origin: origin,
            clip: clip,
            base: base,
            chromeOwnerID: ownerID,
            chromeSuppressed: chromeSuppressed
        )
    }

    /// Derives a painter that reports no chrome surface, for a subtree that
    /// opted out (`TUIView.suppressesVectorChrome`).
    ///
    /// - Returns: Painter with the same translation, clip, and base.
    func withoutChrome() -> Painter {
        Painter(
            target: target,
            origin: origin,
            clip: clip,
            base: base,
            chromeOwnerID: chromeOwnerID,
            chromeSuppressed: true
        )
    }
}
