/// One column of a `TableView`: a header title and a width policy.
public struct TableColumn: Sendable {
    /// How a column claims horizontal space.
    public enum Width: Sendable {
        /// Exactly this many cells.
        case fixed(Int)

        /// A weighted share of the space fixed columns leave over.
        case flexible(Int)
    }

    /// Header title.
    public var title: String

    /// Width policy.
    public var width: Width

    /// Creates a column.
    ///
    /// - Parameters:
    ///   - title: Header title.
    ///   - width: Width policy. Defaults to an equal flexible share.
    public init(_ title: String, width: Width = .flexible(1)) {
        self.title = title
        self.width = width
    }
}

/// Multi-column, scrollable table with a header row and row selection.
///
/// `TableView` is the multi-column consumer of the same navigation core as
/// `ListView` (the 6.5/6.10 design decision): one selection, arrows and
/// paging keys, viewport scrolling below a fixed header. The table renders
/// strings; the application owns the data, including sort order — clicking
/// a header emits a semantic sort request instead of mutating anything:
///
/// ```swift
/// let table = TableView(
///     columns: [TableColumn("Name"), TableColumn("Size", width: .fixed(8))],
///     rows: files.map { [$0.name, $0.size] }
/// )
/// table.onSortRequested = { column in files.sort(by: column); table.rows = ... }
/// table.onSelectionChanged = { row in preview(row) }
/// table.onActivate = { row in open(row) }
/// ```
@MainActor
public final class TableView: TUIView {
    /// Column definitions.
    public var columns: [TableColumn] {
        didSet {
            setNeedsDisplay()
        }
    }

    /// Row data: one string per column, outer array is rows.
    public var rows: [[String]] {
        didSet {
            navigation.count = rows.count
            navigation.select(navigation.selectedIndex)
            setNeedsDisplay()
        }
    }

    /// Called when the selected row changes.
    public var onSelectionChanged: (Int?) -> Void = { _ in }

    /// Called when a data row is activated — Return, or a double-click.
    public var onActivate: (Int) -> Void = { _ in }

    /// Called when a header is clicked; the application re-sorts and
    /// reassigns `rows`.
    public var onSortRequested: (Int) -> Void = { _ in }

    // Shared navigation core (same one ListView uses).
    private var navigation = RowNavigationState()

    /// Creates a table.
    ///
    /// - Parameters:
    ///   - columns: Column definitions.
    ///   - rows: Row data, one string per column.
    public init(columns: [TableColumn], rows: [[String]] = []) {
        self.columns = columns
        self.rows = rows
        super.init(frame: .zero)
        navigation.count = rows.count
    }

    /// Index of the selected row, when any.
    public var selectedIndex: Int? {
        navigation.selectedIndex
    }

    /// First visible row.
    public var scrollOffset: Int {
        navigation.scrollOffset
    }

    /// Tables take keyboard focus.
    public override var acceptsFirstResponder: Bool {
        true
    }

    /// Selects the first row on focus so a focused table shows a highlight.
    public override func didBecomeFirstResponder() {
        if navigation.selectedIndex == nil, !rows.isEmpty {
            select(0, notify: true)
        }
    }

    /// Selects a row programmatically.
    ///
    /// - Parameters:
    ///   - index: Row to select, or `nil` to clear.
    ///   - notify: Whether `onSelectionChanged` fires. Defaults to silent.
    public func select(_ index: Int?, notify: Bool = false) {
        guard navigation.select(index) else {
            return
        }

        navigation.ensureSelectionVisible(height: rowViewportHeight)
        setNeedsDisplay()

        if notify {
            onSelectionChanged(navigation.selectedIndex)
        }
    }

    /// Draws the header and the visible slice of rows.
    public override func draw(_ painter: Painter) {
        let width = bounds.size.width

        guard width > 0, bounds.size.height > 0 else {
            return
        }

        let widths = resolvedColumnWidths(total: width)
        let theme = effectiveTheme

        // Header: themed and underlined, never scrolls.
        var headerStyle = theme.header
        headerStyle.flags.insert(.underline)

        painter.write(
            composeLine(cells: columns.map(\.title), widths: widths, total: width),
            at: .zero,
            style: headerStyle
        )

        for viewportRow in 0..<rowViewportHeight {
            let index = navigation.scrollOffset + viewportRow

            guard index < rows.count else {
                break
            }

            var style = CellStyle()

            if index == navigation.selectedIndex {
                style = theme.selection

                if isFirstResponder {
                    style.flags.insert(.bold)
                }
            }

            painter.write(
                composeLine(cells: rows[index], widths: widths, total: width),
                at: Point(x: 0, y: 1 + viewportRow),
                style: style
            )
        }
    }

    /// Navigation and activation keys (identical model to `ListView`).
    public override func keyDown(_ key: KeyInput) -> Bool {
        guard key.modifiers.isEmpty else {
            return false
        }

        switch key.key {
        case .up:
            moveSelection(by: -1)
            return true

        case .down:
            moveSelection(by: 1)
            return true

        case .pageUp:
            moveSelection(by: -max(1, rowViewportHeight - 1))
            return true

        case .pageDown:
            moveSelection(by: max(1, rowViewportHeight - 1))
            return true

        case .home:
            moveSelection(to: 0)
            return true

        case .end:
            moveSelection(to: rows.count - 1)
            return true

        case .enter:
            if let selected = navigation.selectedIndex {
                onActivate(selected)
            }

            return true

        default:
            return false
        }
    }

    /// A settled click on the header sorts; on a data row it selects (and
    /// activates on a double); the wheel scrolls. Nothing acts on the raw
    /// press, so a double-click never runs the single-click action first.
    public override func mouseEvent(_ mouse: MouseInput) -> Bool {
        switch mouse.action {
        case .press where mouse.button == .left:
            return true   // consume; the settled click does the work

        case .click:
            if mouse.position.y == 0 {
                // The header sorts once, whatever the click count.
                if let column = columnIndex(at: mouse.position.x) {
                    onSortRequested(column)
                }

                return true
            }

            let index = navigation.scrollOffset + mouse.position.y - 1

            guard index < rows.count else {
                return false
            }

            if mouse.clickCount >= 2 {
                // A double is ONLY the double action: the highlight moves
                // silently, so the single-click callback never fires alongside
                // the activation.
                select(index)
                onActivate(index)
            } else {
                moveSelection(to: index)
            }

            return true

        case .scrollUp:
            navigation.scroll(by: -1, height: rowViewportHeight)
            setNeedsDisplay()
            return true

        case .scrollDown:
            navigation.scroll(by: 1, height: rowViewportHeight)
            setNeedsDisplay()
            return true

        default:
            return false
        }
    }

    // MARK: - Geometry

    // Rows visible below the header.
    private var rowViewportHeight: Int {
        max(0, bounds.size.height - 1)
    }

    // Resolves column widths: fixed keep their cells, flexible columns share
    // the leftover (minus one separator cell between columns) by weight,
    // deterministic remainders to the earliest flexible columns.
    private func resolvedColumnWidths(total: Int) -> [Int] {
        guard !columns.isEmpty else {
            return []
        }

        let separators = columns.count - 1
        var leftover = total - separators
        var weights = 0

        for column in columns {
            switch column.width {
            case .fixed(let cells):
                leftover -= cells

            case .flexible(let weight):
                weights += max(0, weight)
            }
        }

        leftover = max(0, leftover)
        var remainder = weights > 0 ? leftover % weights : 0

        return columns.map { column in
            switch column.width {
            case .fixed(let cells):
                return max(0, cells)

            case .flexible(let weight):
                let weight = max(0, weight)

                guard weights > 0 else {
                    return 0
                }

                var share = leftover * weight / weights

                if remainder > 0, weight > 0 {
                    let extra = min(weight, remainder)
                    share += extra
                    remainder -= extra
                }

                return share
            }
        }
    }

    // Renders one line: cells truncated/padded to their columns, separated
    // by single spaces, padded to the full width (so selection inverts the
    // entire row).
    private func composeLine(cells: [String], widths: [Int], total: Int) -> String {
        var line = ""

        for (index, width) in widths.enumerated() {
            if index > 0 {
                line += " "
            }

            let cell = index < cells.count ? cells[index] : ""
            let truncated = Label.truncated(cell, width: width)
            line += truncated + String(repeating: " ", count: max(0, width - truncated.count))
        }

        if line.count < total {
            line += String(repeating: " ", count: total - line.count)
        }

        return line
    }

    // The column containing an x position, honoring separator cells.
    private func columnIndex(at x: Int) -> Int? {
        var start = 0

        for (index, width) in resolvedColumnWidths(total: bounds.size.width).enumerated() {
            if x >= start && x < start + width {
                return index
            }

            start += width + 1
        }

        return nil
    }

    private func moveSelection(by offset: Int) {
        guard navigation.move(by: offset) else {
            return
        }

        selectionDidChange()
    }

    private func moveSelection(to index: Int) {
        guard navigation.select(index) else {
            return
        }

        selectionDidChange()
    }

    private func selectionDidChange() {
        navigation.ensureSelectionVisible(height: rowViewportHeight)
        setNeedsDisplay()
        onSelectionChanged(navigation.selectedIndex)
    }
}
