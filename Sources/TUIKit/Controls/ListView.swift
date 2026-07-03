/// Selection and scrolling state shared by row-oriented controls.
///
/// This is the navigation core that `ListView` uses today and `TableView`
/// and `TreeView` reuse later (see the List/TableView design note in
/// PLAN.md): one place owns the arithmetic for moving a selection, paging,
/// and keeping the selected row visible in a viewport. It is a pure value
/// type, so it is testable without any view.
struct RowNavigationState: Equatable {
    /// Number of rows.
    var count = 0

    /// Selected row, when any.
    var selectedIndex: Int?

    /// First visible row (vertical scroll position).
    var scrollOffset = 0

    /// Selects a row, clamping into range; empty content clears selection.
    ///
    /// - Parameter index: Row to select.
    /// - Returns: `true` when the selection changed.
    @discardableResult
    mutating func select(_ index: Int?) -> Bool {
        let clamped: Int?

        if let index, count > 0 {
            clamped = min(max(0, index), count - 1)
        } else {
            clamped = nil
        }

        guard clamped != selectedIndex else {
            return false
        }

        selectedIndex = clamped
        return true
    }

    /// Moves the selection, starting from the nearest edge when empty.
    ///
    /// - Parameter offset: Rows to move by (negative is up).
    /// - Returns: `true` when the selection changed.
    @discardableResult
    mutating func move(by offset: Int) -> Bool {
        guard count > 0 else {
            return select(nil)
        }

        let current = selectedIndex ?? (offset >= 0 ? -1 : count)
        return select(current + offset)
    }

    /// Scrolls so the selected row is inside a viewport.
    ///
    /// - Parameter height: Viewport height in rows.
    mutating func ensureSelectionVisible(height: Int) {
        guard height > 0 else {
            return
        }

        if let selected = selectedIndex {
            if selected < scrollOffset {
                scrollOffset = selected
            }

            if selected > scrollOffset + height - 1 {
                scrollOffset = selected - height + 1
            }
        }

        scrollOffset = max(0, min(scrollOffset, max(0, count - height)))
    }

    /// Scrolls the viewport without moving the selection.
    ///
    /// - Parameters:
    ///   - offset: Rows to scroll by (negative is up).
    ///   - height: Viewport height in rows.
    mutating func scroll(by offset: Int, height: Int) {
        scrollOffset = max(0, min(scrollOffset + offset, max(0, count - height)))
    }
}

/// Scrollable single-column list with keyboard and mouse selection.
///
/// The list owns navigation (arrows, Home/End, PageUp/PageDown), scrolling
/// (selection follows the viewport; the wheel scrolls freely), and selection
/// rendering. Applications receive two semantic events:
///
/// ```swift
/// let files = ListView(items: names)
/// files.onSelectionChanged = { index in preview(index) }
/// files.onActivate = { index in open(index) }   // Return or double action
/// ```
@MainActor
public final class ListView: View {
    /// Row titles.
    public var items: [String] {
        didSet {
            navigation.count = items.count
            navigation.select(navigation.selectedIndex)
            setNeedsDisplay()
        }
    }

    /// Called when the selected row changes.
    public var onSelectionChanged: (Int?) -> Void = { _ in }

    /// Called when a row is activated with Return.
    public var onActivate: (Int) -> Void = { _ in }

    // Shared navigation core.
    private var navigation = RowNavigationState()

    /// Creates a list.
    ///
    /// - Parameter items: Row titles.
    public init(items: [String] = []) {
        self.items = items
        super.init(frame: .zero)
        navigation.count = items.count
    }

    /// Index of the selected row, when any.
    public var selectedIndex: Int? {
        navigation.selectedIndex
    }

    /// First visible row.
    public var scrollOffset: Int {
        navigation.scrollOffset
    }

    /// Lists take keyboard focus.
    public override var acceptsFirstResponder: Bool {
        true
    }

    /// Selects the first row on focus when nothing is selected yet, so a
    /// focused list always shows a highlighted row.
    public override func didBecomeFirstResponder() {
        if navigation.selectedIndex == nil, !items.isEmpty {
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

        navigation.ensureSelectionVisible(height: bounds.size.height)
        setNeedsDisplay()

        if notify {
            onSelectionChanged(navigation.selectedIndex)
        }
    }

    /// Draws the visible rows; the selected row inverts.
    public override func draw(_ painter: Painter) {
        let height = bounds.size.height
        let width = bounds.size.width

        guard height > 0, width > 0 else {
            return
        }

        for row in 0..<height {
            let index = navigation.scrollOffset + row

            guard index < items.count else {
                break
            }

            let isSelected = index == navigation.selectedIndex
            var style = CellStyle()

            if isSelected {
                style.flags = isFirstResponder ? [.inverse, .bold] : .inverse
            }

            let title = Label.truncated(items[index], width: width)
            let padded = title + String(repeating: " ", count: max(0, width - title.count))
            painter.write(padded, at: Point(x: 0, y: row), style: style)
        }
    }

    /// Navigation and activation keys.
    public override func keyDown(_ key: KeyInput) -> Bool {
        guard key.modifiers.isEmpty else {
            return false
        }

        let height = bounds.size.height

        switch key.key {
        case .up:
            moveSelection(by: -1)
            return true

        case .down:
            moveSelection(by: 1)
            return true

        case .pageUp:
            moveSelection(by: -max(1, height - 1))
            return true

        case .pageDown:
            moveSelection(by: max(1, height - 1))
            return true

        case .home:
            moveSelection(to: 0)
            return true

        case .end:
            moveSelection(to: items.count - 1)
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

    /// Click selects; the wheel scrolls without moving the selection.
    public override func mouseEvent(_ mouse: MouseInput) -> Bool {
        switch mouse.action {
        case .press where mouse.button == .left:
            let index = navigation.scrollOffset + mouse.position.y

            guard index < items.count else {
                return false
            }

            moveSelection(to: index)
            return true

        case .scrollUp:
            navigation.scroll(by: -1, height: bounds.size.height)
            setNeedsDisplay()
            return true

        case .scrollDown:
            navigation.scroll(by: 1, height: bounds.size.height)
            setNeedsDisplay()
            return true

        default:
            return false
        }
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
        navigation.ensureSelectionVisible(height: bounds.size.height)
        setNeedsDisplay()
        onSelectionChanged(navigation.selectedIndex)
    }
}
