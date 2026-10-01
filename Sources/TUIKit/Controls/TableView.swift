// Copyright (c) 2026 Bobby Skinner
// SPDX-License-Identifier: MIT
// See the LICENSE file at the repository root for the full text.

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
    ///
    /// Ignored while ``rowSource`` is set.
    public var rows: [[String]] {
        didSet {
            navigation.count = rowCount
            navigation.select(navigation.selectedIndex)
            setNeedsDisplay()
        }
    }

    /// Pulls rows on demand instead of holding them.
    ///
    /// **The seam a result set larger than the window needs.** `rows` is an
    /// array, so filling it means building every row — and the draw loop only
    /// ever touches the twenty or so that fit. A database view over ssh is
    /// the case that makes the difference plain: fifty thousand rows returned,
    /// twenty on screen, and the array form builds all fifty thousand to draw
    /// the twenty.
    ///
    /// Set this and `rows` is not consulted. Call ``reloadRows()`` when the
    /// count changes.
    public struct RowSource {
        /// How many rows there are now.
        public let count: @MainActor () -> Int

        /// One row's cells, one string per column.
        public let cells: @MainActor (Int) -> [String]

        /// Creates a source.
        /// - Parameters:
        ///   - count: How many rows there are now.
        ///   - cells: One row's cells, by index.
        public init(count: @escaping @MainActor () -> Int,
                    cells: @escaping @MainActor (Int) -> [String]) {
            self.count = count
            self.cells = cells
        }
    }

    /// Where rows come from, when they are not held in ``rows``.
    public var rowSource: RowSource? {
        didSet {
            reloadRows()
        }
    }

    /// Re-reads the row count from ``rowSource`` and repaints.
    ///
    /// Only the count: the cells themselves are pulled as they are drawn, so
    /// there is nothing else to refresh.
    public func reloadRows() {
        navigation.count = rowCount
        navigation.select(navigation.selectedIndex)
        setNeedsDisplay()
    }

    // How many rows there are, from whichever side is supplying them.
    private var rowCount: Int {
        rowSource?.count() ?? rows.count
    }

    // One row's cells, from whichever side is supplying them.
    private func cells(at index: Int) -> [String]? {
        if let rowSource {
            return index < rowSource.count() ? rowSource.cells(index) : nil
        }

        return index < rows.count ? rows[index] : nil
    }

    /// Called when the selected row changes.
    public var onSelectionChanged: (Int?) -> Void = { _ in }

    /// Called when a data row is activated — Return, or a double-click.
    public var onActivate: (Int) -> Void = { _ in }

    /// Called when a header is clicked; the application re-sorts and
    /// reassigns `rows`.
    public var onSortRequested: (Int) -> Void = { _ in }

    /// Whether rows can be moved: Alt-Up and Alt-Down move the cursor row,
    /// and a row can be dragged to another (ActiveUI's
    /// `AUITable.allowsReordering`). The table reports; the host moves the
    /// row in its model and reloads.
    public var allowsReordering = false

    /// Called with (from, to) when a row is moved; `to` is the row's index
    /// after the move. The cursor follows the row.
    public var onMoveRow: (Int, Int) -> Void = { _, _ in }

    // The row a drag picked up, and the row it would land on now.
    private var dragSource: Int?
    private var dragTarget: Int?

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
        navigation.count = rowCount
    }

    /// Index of the selected row, when any. With multiple selection, the
    /// cursor: the row the keys move from, selected or not.
    public var selectedIndex: Int? {
        navigation.selectedIndex
    }

    /// Whether more than one row can be selected (ActiveUI's
    /// `AUITable.allowsMultipleSelection`). Shift extends from the anchor —
    /// arrows, Page keys, Home/End, a click; Ctrl- or Alt-click and Space add
    /// or remove one row. That is NSTableView's Shift and ⌘, with Ctrl and
    /// Alt standing in for the ⌘ a terminal never sees.
    public var allowsMultipleSelection = false {
        didSet {
            guard !allowsMultipleSelection else {
                return
            }

            selection = []
            setNeedsDisplay()
        }
    }

    /// The selected rows, in order: the cursor row alone, or none, unless
    /// `allowsMultipleSelection`.
    public var selectedIndexes: [Int] {
        guard allowsMultipleSelection else {
            return navigation.selectedIndex.map { [$0] } ?? []
        }

        return selection.filter { $0 < rowCount }.sorted()
    }

    /// Selects these rows from code; the last becomes the cursor. A table
    /// without multiple selection takes the first.
    ///
    /// - Parameters:
    ///   - rows: The rows to select.
    ///   - notify: Whether `onSelectionChanged` fires. Defaults to silent.
    public func selectRows(_ rows: [Int], notify: Bool = false) {
        guard allowsMultipleSelection else {
            select(rows.first, notify: notify)
            return
        }

        let valid = rows.filter { (0..<rowCount).contains($0) }
        navigation.select(valid.last)
        selection = Set(valid)
        anchor = valid.first
        navigation.ensureSelectionVisible(height: rowViewportHeight)
        setNeedsDisplay()

        if notify {
            onSelectionChanged(navigation.selectedIndex)
        }
    }

    // The selected rows with multiple selection on; unused otherwise, where
    // the cursor row is the selection.
    private var selection: Set<Int> = []

    // Where a Shift-extension starts.
    private var anchor: Int?

    private func isSelected(_ index: Int) -> Bool {
        allowsMultipleSelection ? selection.contains(index) : index == navigation.selectedIndex
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
        let moved = navigation.select(index)
        let before = selection
        selection = navigation.selectedIndex.map { [$0] } ?? []
        anchor = navigation.selectedIndex

        guard moved || (allowsMultipleSelection && selection != before) else {
            return
        }

        navigation.ensureSelectionVisible(height: rowViewportHeight)
        setNeedsDisplay()

        if notify {
            onSelectionChanged(navigation.selectedIndex)
        }
    }

    /// Scrolls so a row is on screen, leaving the selection where it is —
    /// AppKit's `scrollRowToVisible`. Selecting the row was the only way to
    /// bring it into view, and revealing a row is not choosing it.
    ///
    /// - Parameter index: The row to show.
    public func scrollRowToVisible(_ index: Int) {
        let height = rowViewportHeight

        guard height > 0, (0..<rowCount).contains(index) else {
            return
        }

        if index < navigation.scrollOffset {
            navigation.scroll(by: index - navigation.scrollOffset, height: height)
        } else if index > navigation.scrollOffset + height - 1 {
            navigation.scroll(by: index - (navigation.scrollOffset + height - 1), height: height)
        }

        setNeedsDisplay()
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

            guard let rowCells = cells(at: index) else {
                break
            }

            var style = CellStyle()

            if isSelected(index) {
                style = theme.selection

                if isFirstResponder, index == navigation.selectedIndex {
                    style.flags.insert(.bold)
                }
            } else if index == dragTarget {
                // Where a dragged row would land.
                style.flags.insert(.underline)
                style.flags.insert(.bold)
            } else if allowsMultipleSelection, isFirstResponder, index == navigation.selectedIndex {
                // The cursor on a row it left unselected: still shown, so the
                // keys have somewhere visible to start from.
                style.flags.insert(.underline)
            }

            painter.write(
                composeLine(cells: rowCells, widths: widths, total: width),
                at: Point(x: 0, y: 1 + viewportRow),
                style: style
            )
        }
    }

    /// A single click landed on a cell (row, column).
    ///
    /// Selection and `onActivate` still behave exactly as before; this is the
    /// hook for a table whose cells DO something — a checkbox column, a row's
    /// delete button — where which column was hit is the whole message.
    public var onCellClicked: (Int, Int) -> Void = { _, _ in }

    /// Which cell a point falls in, or nil for the header and past the rows.
    ///
    /// - Parameter point: In this view's coordinates.
    public func cell(at point: Point) -> (row: Int, column: Int)? {
        guard point.y > 0, let column = columnIndex(at: point.x) else {
            return nil
        }

        let row = scrollOffset + point.y - 1

        guard row < rowCount else {
            return nil
        }

        return (row, column)
    }

    /// Navigation and activation keys (identical model to `ListView`).
    public override func keyDown(_ key: KeyInput) -> Bool {
        if allowsReordering, key.modifiers == .alt, let cursor = navigation.selectedIndex {
            switch key.key {
            case .up where cursor > 0:
                moveRow(cursor, to: cursor - 1)
                return true

            case .down where cursor < rowCount - 1:
                moveRow(cursor, to: cursor + 1)
                return true

            case .up, .down:
                return true   // at the end already: still the move keys

            default:
                break
            }
        }

        let extending = allowsMultipleSelection && key.modifiers == .shift

        guard key.modifiers.isEmpty || extending else {
            return false
        }

        switch key.key {
        case .up:
            moveSelection(by: -1, extending: extending)
            return true

        case .down:
            moveSelection(by: 1, extending: extending)
            return true

        case .pageUp:
            moveSelection(by: -max(1, rowViewportHeight - 1), extending: extending)
            return true

        case .pageDown:
            moveSelection(by: max(1, rowViewportHeight - 1), extending: extending)
            return true

        case .home:
            moveSelection(to: 0, extending: extending)
            return true

        case .end:
            moveSelection(to: rowCount - 1, extending: extending)
            return true

        case .character(" ") where allowsMultipleSelection && !extending:
            if let cursor = navigation.selectedIndex {
                toggleRow(cursor)
            }

            return true

        case .enter where !extending:
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
            // A press on a data row may become a drag that moves it.
            if allowsReordering, mouse.position.y > 0 {
                let index = navigation.scrollOffset + mouse.position.y - 1
                dragSource = index < rowCount ? index : nil
                dragTarget = nil
            }

            return true   // consume; the settled click does the work

        case .drag where dragSource != nil:
            let row = navigation.scrollOffset + mouse.position.y - 1
            let target = Swift.max(0, Swift.min(rowCount - 1, row))
            dragTarget = target == dragSource ? nil : target
            setNeedsDisplay()
            return true

        case .release where dragSource != nil:
            if let source = dragSource, let target = dragTarget {
                moveRow(source, to: target)
            }

            dragSource = nil
            dragTarget = nil
            setNeedsDisplay()
            return true

        case .click:
            if mouse.position.y == 0 {
                // The header sorts once, whatever the click count.
                if let column = columnIndex(at: mouse.position.x) {
                    onSortRequested(column)
                }

                return true
            }

            let index = navigation.scrollOffset + mouse.position.y - 1

            guard index < rowCount else {
                return false
            }

            if mouse.clickCount >= 2 {
                // A double is ONLY the double action: the highlight moves
                // silently, so the single-click callback never fires alongside
                // the activation.
                select(index)
                onActivate(index)
            } else if allowsMultipleSelection, mouse.modifiers.contains(.shift) {
                moveSelection(to: index, extending: true)
            } else if allowsMultipleSelection, !mouse.modifiers.isDisjoint(with: [.control, .alt]) {
                toggleRow(index)
            } else {
                moveSelection(to: index)

                if let column = columnIndex(at: mouse.position.x) {
                    onCellClicked(index, column)
                }
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
            line += truncated + String(repeating: " ", count: max(0, width - DisplayWidth.of(truncated)))
        }

        let lineWidth = DisplayWidth.of(line)

        if lineWidth < total {
            line += String(repeating: " ", count: total - lineWidth)
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

    private func moveSelection(by offset: Int, extending: Bool = false) {
        settleSelection(moved: navigation.move(by: offset), extending: extending)
    }

    private func moveSelection(to index: Int, extending: Bool = false) {
        settleSelection(moved: navigation.select(index), extending: extending)
    }

    // After the cursor moves: the selection is that one row, or — extending —
    // the run from the anchor to it. A plain move onto the cursor's own row
    // still collapses a multiple selection, so it can change without moving.
    private func settleSelection(moved: Bool, extending: Bool) {
        guard allowsMultipleSelection else {
            if moved {
                selectionDidChange()
            }

            return
        }

        let before = selection

        if let cursor = navigation.selectedIndex {
            if extending, let anchor {
                selection = Set(Swift.min(anchor, cursor)...Swift.max(anchor, cursor))
            } else {
                selection = [cursor]
                anchor = cursor
            }
        } else {
            selection = []
            anchor = nil
        }

        if moved || selection != before {
            selectionDidChange()
        }
    }

    // Reports a move and puts the cursor (and the selection) on the row in
    // its new place, which is where the host's reload will draw it.
    private func moveRow(_ source: Int, to target: Int) {
        onMoveRow(source, target)
        navigation.count = rowCount
        select(target, notify: true)
    }

    // Adds a row to the selection or takes it out; the cursor goes there and
    // the next Shift-extension starts from it.
    private func toggleRow(_ index: Int) {
        guard allowsMultipleSelection, (0..<rowCount).contains(index) else {
            return
        }

        navigation.select(index)

        if selection.contains(index) {
            selection.remove(index)
        } else {
            selection.insert(index)
        }

        anchor = index
        selectionDidChange()
    }

    private func selectionDidChange() {
        navigation.ensureSelectionVisible(height: rowViewportHeight)
        setNeedsDisplay()
        onSelectionChanged(navigation.selectedIndex)
    }
}
