/// A view you draw yourself — cells, vector chrome, or both — without a
/// subclass.
///
/// ```swift
/// let dial = Canvas()
/// dial.drawChrome = { chrome, bounds in
///     chrome.circle("face", center: ChromePoint(x: 6, y: 2.5), radius: 2.4, fill: ink)
/// }
/// dial.drawCells = { painter, bounds in painter.write("42%", at: Point(x: 5, y: 2)) }
/// ```
///
/// Cells first: `drawCells` runs on every terminal. On a VectorTerminal
/// `drawChrome` runs too, in the same frame, with the cells cleared to the
/// terminal's default background so the chrome shows through wherever
/// `drawCells` leaves a cell blank — the same rule the charts follow. A
/// canvas with only a chrome closure renders an honest placeholder on a
/// plain terminal: a framed "VTG graphics required" notice, never a blank.
///
/// Vector chrome is all-or-nothing per view (retained shapes cannot be
/// cropped by the terminal): a canvas scrolled partly out of view falls back
/// to its cells — or its placeholder — until it is wholly visible again.
@MainActor
public final class Canvas: TUIView {
    /// Draws with cells; runs on every terminal. The rect is the bounds.
    public var drawCells: ((Painter, Rect) -> Void)? {
        didSet {
            setNeedsDisplay()
        }
    }

    /// Draws vector chrome; runs on a VectorTerminal. The rect is the bounds.
    public var drawChrome: ((ChromeSurface, Rect) -> Void)? {
        didSet {
            setNeedsDisplay()
        }
    }

    /// What the placeholder says when only chrome is drawn and none is
    /// available.
    public var placeholderText = "VTG graphics required" {
        didSet {
            setNeedsDisplay()
        }
    }

    /// A natural size, when the canvas should ask for one; `nil` (the
    /// default) leaves it flexible.
    public var naturalSize: Size? {
        didSet {
            if naturalSize != oldValue {
                superview?.setNeedsLayout()
            }
        }
    }

    /// Creates a canvas.
    ///
    /// - Parameters:
    ///   - cells: Cell drawing, for every terminal.
    ///   - chrome: Vector drawing, for a VectorTerminal.
    public init(cells: ((Painter, Rect) -> Void)? = nil, chrome: ((ChromeSurface, Rect) -> Void)? = nil) {
        drawCells = cells
        drawChrome = chrome
        super.init(frame: .zero)
    }

    /// `naturalSize`, when set.
    public override var intrinsicContentSize: Size? {
        naturalSize
    }

    /// Asks for a repaint — call after the data the closures draw changes.
    public func redraw() {
        setNeedsDisplay()
    }

    /// Chrome with cells over it, cells alone, or the placeholder.
    public override func draw(_ painter: Painter) {
        if let drawChrome, let chrome = painter.chrome, chrome.covers(bounds) {
            painter.withBase(CellStyle()).fill(bounds, with: .blank)   // let the chrome show through
            drawChrome(chrome, bounds)
            drawCells?(painter, bounds)
            return
        }

        painter.fill(bounds, with: .blank)

        if let drawCells {
            drawCells(painter, bounds)
        } else if drawChrome != nil {
            drawPlaceholder(painter)
        }
    }

    // The framed notice: this view has a vector rendering this terminal
    // cannot show.
    private func drawPlaceholder(_ painter: Painter) {
        let theme = effectiveTheme

        guard bounds.size.width >= 3, bounds.size.height >= 1 else {
            return
        }

        if bounds.size.height >= 3 {
            painter.drawBox(bounds, style: theme.border, border: theme.borderStyle)
        }

        let text = Label.truncated(placeholderText, width: max(0, bounds.size.width - 2))
        let x = max(1, (bounds.size.width - text.count) / 2)
        let y = bounds.size.height / 2
        painter.write(text, at: Point(x: x, y: y), style: theme.placeholder)
    }
}
