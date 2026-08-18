import CodeEditorCore
import TUIKit

/// Two revisions of a file, one above the other, aligned row for row.
///
/// ```text
/// ┌ main.swift ── 5361d7e ↔ Working ──────────────────────┐
/// │ 5361d7e                                    -1 +2      │
/// │   19 │ @MainActor                                     │
/// │ - 21 │     private let canvas: SnapBlockCanvasView     │
/// │───────────────────────────────────────────────────────│
/// │ Working                                               │
/// │   19 │ @MainActor                                     │
/// │ + 21 │     private let source: AUISourceEditor         │
/// └───────────────────────────────────────────────────────┘
/// ```
///
/// **Over/under, not side by side**, and for this medium that is arithmetic
/// rather than taste. Side by side halves the WIDTH: with a gutter, a border
/// and a divider, an 83-column document becomes two ~36-column panes, and
/// Swift does not fit in 36 columns — every line wraps or truncates and you
/// end up diffing ellipses. Over/under halves the HEIGHT, which is the cheaper
/// axis: rows are what a terminal has most of, and a diff is read line by line
/// anyway.
///
/// The axis is nonetheless a property, because on a 150-column terminal the
/// arithmetic comes out the other way and side-by-side is worth having. Only
/// the vertical axis is built and tested for now.
///
/// Both halves scroll TOGETHER, and they do it without a mapping table:
/// ``DiffModel`` pads the shorter side of every hunk, so the two halves have
/// the same number of rows and one offset drives both. The alignment is the
/// data structure, not a synchronisation routine that can drift.
@MainActor
public final class DiffView: TUIView, BorderScrollable {
    /// Which way the two halves are stacked.
    public enum Axis: Sendable {
        /// Old above new. The default, and the only tested one.
        case vertical

        /// Old beside new — for wide terminals. Untested; the layout is here
        /// so that adding it later is a change to one function, not a rewrite.
        case horizontal
    }

    /// The aligned diff.
    public var model: DiffModel = DiffModel(old: [], new: [], changedRows: []) {
        didSet {
            verticalOffset = 0
            horizontalOffset = 0
            setNeedsDisplay()
        }
    }

    /// What the top half is called ("5361d7e").
    public var oldTitle = "Old" {
        didSet { setNeedsDisplay() }
    }

    /// What the bottom half is called ("Working").
    public var newTitle = "New" {
        didSet { setNeedsDisplay() }
    }

    /// How the halves are stacked.
    public var axis: Axis = .vertical {
        didSet { setNeedsDisplay() }
    }

    /// First visible row, shared by both halves.
    public private(set) var verticalOffset = 0

    /// First visible column, shared by both halves.
    public private(set) var horizontalOffset = 0

    /// Whether the view draws its own scrollbars (off when a panel embeds them).
    public var showsOwnScrollbars = true {
        didSet { setNeedsDisplay() }
    }

    /// A diff view takes focus so the keyboard can drive it.
    public override var acceptsFirstResponder: Bool {
        true
    }

    // MARK: - Scrolling

    public var verticalScrollSpan: ScrollSpan? {
        ScrollSpan(offset: verticalOffset, viewport: rowsPerHalf, content: model.old.count)
    }

    public var horizontalScrollSpan: ScrollSpan? {
        ScrollSpan(offset: horizontalOffset, viewport: max(1, textWidth), content: widestLine)
    }

    public func setScrollOffset(vertical offset: Int) {
        let limit = max(0, model.old.count - rowsPerHalf)
        verticalOffset = min(max(0, offset), limit)
        setNeedsDisplay()
    }

    public func setScrollOffset(horizontal offset: Int) {
        let limit = max(0, widestLine - max(1, textWidth))
        horizontalOffset = min(max(0, offset), limit)
        setNeedsDisplay()
    }

    /// Scrolls so a row is visible in both halves.
    ///
    /// - Parameter row: Row index in the aligned model.
    public func reveal(row: Int) {
        if row < verticalOffset {
            setScrollOffset(vertical: row)
        } else if row >= verticalOffset + rowsPerHalf {
            setScrollOffset(vertical: row - rowsPerHalf + 1)
        }
    }

    /// Jumps to the next changed row, wrapping.
    public func goToNextChange() {
        model.nextChange(after: verticalOffset).map { reveal(row: $0) }
    }

    /// Jumps to the previous changed row, wrapping.
    public func goToPreviousChange() {
        model.previousChange(before: verticalOffset).map { reveal(row: $0) }
    }

    // MARK: - Input

    public override func keyDown(_ key: KeyInput) -> Bool {
        switch key.key {
        case .down:
            setScrollOffset(vertical: verticalOffset + 1)

        case .up:
            setScrollOffset(vertical: verticalOffset - 1)

        case .pageDown:
            // A page keeps one row of context, the rule every other scrolling
            // surface in the framework follows.
            setScrollOffset(vertical: verticalOffset + max(1, rowsPerHalf - 1))

        case .pageUp:
            setScrollOffset(vertical: verticalOffset - max(1, rowsPerHalf - 1))

        case .home:
            setScrollOffset(vertical: 0)

        case .end:
            setScrollOffset(vertical: model.old.count)

        case .left:
            setScrollOffset(horizontal: horizontalOffset - 1)

        case .right:
            setScrollOffset(horizontal: horizontalOffset + 1)

        case .character("n"):
            goToNextChange()

        case .character("p"):
            goToPreviousChange()

        default:
            return false
        }

        return true
    }

    public override func mouseEvent(_ mouse: MouseInput) -> Bool {
        switch mouse.action {
        case .scrollUp:
            setScrollOffset(vertical: verticalOffset - 3)
            return true

        case .scrollDown:
            setScrollOffset(vertical: verticalOffset + 3)
            return true

        default:
            return false
        }
    }

    // MARK: - Geometry

    // Rows each half gets: the caption line is charged to its own half, so
    // both halves lose exactly one row and the split stays even.
    var rowsPerHalf: Int {
        switch axis {
        case .vertical:
            return max(1, (bounds.size.height - 2) / 2)   // two captions

        case .horizontal:
            return max(1, bounds.size.height - 1)
        }
    }

    // Width of one half.
    private var halfWidth: Int {
        switch axis {
        case .vertical:
            return bounds.size.width

        case .horizontal:
            return max(1, (bounds.size.width - 1) / 2)
        }
    }

    // Marker (1) + space + number column + " │ ".
    private var gutterWidth: Int {
        2 + numberWidth + 3
    }

    private var numberWidth: Int {
        let widest = max(model.old.count, model.new.count)
        return max(2, String(widest).count)
    }

    private var textWidth: Int {
        max(0, halfWidth - gutterWidth)
    }

    private var widestLine: Int {
        (model.old + model.new).reduce(0) { max($0, $1.text.count) }
    }

    // MARK: - Drawing

    public override func draw(_ painter: Painter) {
        let theme = effectiveTheme
        painter.fill(bounds, with: TerminalCell(character: " ", style: theme.base))

        guard !model.old.isEmpty else {
            painter.write("(no differences)", at: Point(x: 1, y: 0), style: theme.placeholder)
            return
        }

        let rows = rowsPerHalf

        switch axis {
        case .vertical:
            drawHalf(model.old, title: oldTitle, origin: Point(x: 0, y: 0),
                     width: halfWidth, rows: rows, painter: painter, theme: theme)
            drawHalf(model.new, title: newTitle, origin: Point(x: 0, y: rows + 1),
                     width: halfWidth, rows: rows, painter: painter, theme: theme)

        case .horizontal:
            drawHalf(model.old, title: oldTitle, origin: .zero,
                     width: halfWidth, rows: rows, painter: painter, theme: theme)
            drawHalf(model.new, title: newTitle, origin: Point(x: halfWidth + 1, y: 0),
                     width: halfWidth, rows: rows, painter: painter, theme: theme)
        }
    }

    // One half: a caption naming the revision, then its rows.
    private func drawHalf(
        _ lines: [DiffModel.Line],
        title: String,
        origin: Point,
        width: Int,
        rows: Int,
        painter: Painter,
        theme: ResolvedTheme
    ) {
        let counts = model.counts
        let tally = "-\(counts.removed) +\(counts.added)"
        let caption = Label.truncated(" " + title, width: max(0, width - tally.count - 1))

        painter.write(
            caption + String(repeating: " ", count: max(0, width - caption.count - tally.count - 1)) + tally + " ",
            at: origin,
            style: theme.header
        )

        for row in 0..<rows {
            let index = verticalOffset + row

            guard index < lines.count else {
                return   // past the end: the fill already left it blank
            }

            drawLine(
                lines[index],
                at: Point(x: origin.x, y: origin.y + 1 + row),
                width: width,
                painter: painter,
                theme: theme
            )
        }
    }

    private func drawLine(
        _ line: DiffModel.Line,
        at point: Point,
        width: Int,
        painter: Painter,
        theme: ResolvedTheme
    ) {
        let number = line.number.map { String($0) } ?? ""
        let gutter = "\(line.marker) "
            + String(repeating: " ", count: max(0, numberWidth - number.count))
            + number
            + " │ "

        // A filler is nothing at all — no number, no text, and a dim ground so
        // the eye reads it as absence rather than as an empty line somebody
        // wrote.
        let text = line.text.isEmpty
            ? ""
            : String(line.text.dropFirst(min(horizontalOffset, line.text.count)))
        let body = Label.truncated(text, width: max(0, width - gutter.count))
        let padded = body + String(repeating: " ", count: max(0, width - gutter.count - body.count))

        painter.write(gutter, at: point, style: gutterStyle(for: line, theme: theme))
        painter.write(padded, at: Point(x: point.x + gutter.count, y: point.y), style: style(for: line, theme: theme))
    }

    private func style(for line: DiffModel.Line, theme: ResolvedTheme) -> CellStyle {
        switch line.kind {
        case .unchanged:
            return theme.base

        case .added:
            // The same green and red the gutter's change ribbon already uses,
            // so a line marked added in the editor is the same colour as the
            // line marked added in the diff.
            var style = theme.base
            style.foreground = .named(.brightGreen)
            return style

        case .removed:
            var style = theme.base
            style.foreground = .named(.brightRed)
            return style

        case .filler:
            return theme.placeholder
        }
    }

    private func gutterStyle(for line: DiffModel.Line, theme: ResolvedTheme) -> CellStyle {
        var style = self.style(for: line, theme: theme)

        if line.kind == .unchanged {
            style = theme.placeholder   // context numbers recede; the marks do not
        }

        return style
    }
}
