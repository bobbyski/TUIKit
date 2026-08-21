/// A grid of cells behaving as one control — radio or highlight.
///
/// ```text
///   ┌ Mon ┐  Tue    Wed          .radio: one cell selected
///    Thu    Fri   ┌ Sat ┐ Sun
///
///   [Mon] [Tue]  Wed  [Thu]      .highlight: any number
/// ```
///
/// Arrows move a cursor through the cells, Space toggles (or selects, in
/// radio mode), Enter activates; clicking does the same. Cells are plain
/// titles laid out in `columns`; the matrix owns selection, so the app
/// gets one `onSelectionChanged` rather than a grid of buttons to wire.
///
/// ```swift
/// let days = Matrix(titles: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"], columns: 4, mode: .highlight)
/// days.onSelectionChanged = { picked in schedule.days = picked }
/// ```
@MainActor
public final class Matrix: TUIView {
    /// How cells select.
    public enum Mode: Hashable, Sendable {
        /// Exactly one cell selected (or none before the first pick).
        case radio

        /// Any number of cells selected.
        case highlight
    }

    /// Cell titles, row-major.
    public var titles: [String] {
        didSet {
            selected = selected.filter { $0 < titles.count }
            cursor = min(cursor, max(0, titles.count - 1))
            superview?.setNeedsLayout()
            setNeedsDisplay()
        }
    }

    /// Cells per row.
    public var columns: Int {
        didSet {
            columns = max(1, columns)
            superview?.setNeedsLayout()
            setNeedsDisplay()
        }
    }

    /// Radio or highlight.
    public let mode: Mode

    /// Indices of the selected cells.
    public private(set) var selected: Set<Int> = []

    /// The cell the keyboard cursor is on.
    public private(set) var cursor = 0

    /// Called with the selected indices after a change.
    public var onSelectionChanged: (Set<Int>) -> Void = { _ in }

    /// Called when Enter or a double-click activates the cursor cell.
    public var onActivate: (Int) -> Void = { _ in }

    /// Creates a matrix.
    ///
    /// - Parameters:
    ///   - titles: Cell titles, row-major.
    ///   - columns: Cells per row.
    ///   - mode: Radio (the default) or highlight.
    public init(titles: [String], columns: Int, mode: Mode = .radio) {
        self.titles = titles
        self.columns = max(1, columns)
        self.mode = mode
        super.init(frame: .zero)
    }

    /// Matrices take keyboard focus.
    public override var acceptsFirstResponder: Bool {
        true
    }

    /// Rows of the widest title plus brackets.
    public override var intrinsicContentSize: Size? {
        Size(width: columns * cellWidth + max(0, columns - 1), height: rowCount)
    }

    /// The selected index in radio mode.
    public var selectedIndex: Int? {
        selected.first
    }

    /// Sets the selection programmatically (radio mode keeps one).
    ///
    /// - Parameters:
    ///   - indices: The cells to select.
    ///   - notify: Whether `onSelectionChanged` fires. Defaults to silent.
    public func select(_ indices: Set<Int>, notify: Bool = false) {
        var next = indices.filter { $0 < titles.count }

        if mode == .radio, next.count > 1, let first = next.min() {
            next = [first]
        }

        guard next != selected else {
            return
        }

        selected = next
        setNeedsDisplay()

        if notify {
            onSelectionChanged(selected)
        }
    }

    /// Draws the cells; the cursor cell wears brackets, selected cells the
    /// selection style.
    public override func draw(_ painter: Painter) {
        let theme = effectiveTheme
        painter.fill(bounds, with: .blank)

        for (index, title) in titles.enumerated() {
            let origin = cellOrigin(index)

            guard origin.y < bounds.size.height else {
                break
            }

            let isSelected = selected.contains(index)
            let isCursor = index == cursor && isFirstResponder
            var style = isSelected ? theme.selection : theme.base

            if isCursor, !isSelected, let cue = theme.cueAccent(over: style.background) {
                style.foreground = cue
            }

            let text = Label.truncated(title, width: cellWidth - 2)
            let padded = text.padding(toLength: cellWidth - 2, withPad: " ", startingAt: 0)
            let cell = (isCursor ? "[" : " ") + padded + (isCursor ? "]" : " ")
            painter.write(cell, at: origin, style: style)
        }
    }

    /// Arrows move the cursor, Space selects/toggles, Enter activates.
    public override func keyDown(_ key: KeyInput) -> Bool {
        guard key.modifiers.isEmpty, !titles.isEmpty else {
            return false
        }

        switch key.key {
        case .left:
            moveCursor(to: cursor - 1)
            return true

        case .right:
            moveCursor(to: cursor + 1)
            return true

        case .up:
            moveCursor(to: cursor - columns)
            return true

        case .down:
            moveCursor(to: cursor + columns)
            return true

        case .home:
            moveCursor(to: 0)
            return true

        case .end:
            moveCursor(to: titles.count - 1)
            return true

        case .character(" "):
            toggle(cursor)
            return true

        case .enter:
            onActivate(cursor)
            return true

        default:
            return false
        }
    }

    /// A click moves the cursor there and toggles; a double-click activates.
    public override func mouseEvent(_ mouse: MouseInput) -> Bool {
        guard mouse.button == .left, let index = cellIndex(at: mouse.position) else {
            return false
        }

        switch mouse.action {
        case .press:
            moveCursor(to: index)
            toggle(index)
            return true

        case .click where mouse.clickCount >= 2:
            onActivate(index)
            return true

        default:
            return false
        }
    }

    // MARK: - Geometry

    private var cellWidth: Int {
        (titles.map(\.count).max() ?? 1) + 2
    }

    private var rowCount: Int {
        titles.isEmpty ? 0 : (titles.count + columns - 1) / columns
    }

    private func cellOrigin(_ index: Int) -> Point {
        Point(x: (index % columns) * (cellWidth + 1), y: index / columns)
    }

    private func cellIndex(at point: Point) -> Int? {
        guard point.y >= 0, point.x >= 0 else {
            return nil
        }

        let column = point.x / (cellWidth + 1)

        guard column < columns, point.x % (cellWidth + 1) < cellWidth else {
            return nil
        }

        let index = point.y * columns + column
        return index < titles.count ? index : nil
    }

    // MARK: - State

    private func moveCursor(to index: Int) {
        let clamped = min(max(0, index), titles.count - 1)

        guard clamped != cursor else {
            return
        }

        cursor = clamped
        setNeedsDisplay()
    }

    private func toggle(_ index: Int) {
        var next = selected

        switch mode {
        case .radio:
            next = [index]

        case .highlight:
            if next.contains(index) {
                next.remove(index)
            } else {
                next.insert(index)
            }
        }

        guard next != selected else {
            return
        }

        selected = next
        setNeedsDisplay()
        onSelectionChanged(selected)
    }
}
