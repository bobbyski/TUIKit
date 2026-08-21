/// A grid of uniform items, in sections with headers, with a selection.
///
/// ```text
///   Recent ─────────────────────
///   ▸ report.pdf    notes.md     photo.png
///     deck.key      todo.txt
///   Shared ─────────────────────
///     budget.xlsx   plan.md
/// ```
///
/// Give it sections and a closure that builds the view for an item; the
/// collection lays items out in as many columns as fit `itemWidth`, one row
/// per `itemHeight`, with a header row per section. Arrows move the
/// selection, Enter activates, a click selects, a double-click activates.
/// Its natural height is the whole grid — put it in a `ScrollView` to
/// scroll. Items are built once per `reload()` (no recycling; Phase 16
/// basics).
///
/// ```swift
/// let files = CollectionView(sections: [.init(title: "Recent", items: recent)]) { name in Label(name) }
/// files.onActivate = { section, item in open(files.sections[section].items[item]) }
/// ```
@MainActor
public final class CollectionView: TUIView {
    /// One titled run of items.
    public struct Section {
        /// Header text; empty draws no header row.
        public var title: String

        /// The items, as strings the builder turns into views.
        public var items: [String]

        /// Creates a section.
        public init(title: String = "", items: [String]) {
            self.title = title
            self.items = items
        }
    }

    /// An item's position.
    public struct IndexPath: Hashable, Sendable {
        /// The section.
        public var section: Int

        /// The item within it.
        public var item: Int

        /// Creates an index path.
        public init(section: Int, item: Int) {
            self.section = section
            self.item = item
        }
    }

    /// The sections.
    public var sections: [Section] {
        didSet {
            reload()
        }
    }

    /// Builds the view for an item string.
    public var builder: (String) -> TUIView

    /// Width of every item cell, marker column included.
    public var itemWidth = 16 {
        didSet {
            superview?.setNeedsLayout()
            setNeedsLayout()
        }
    }

    /// Height of every item cell.
    public var itemHeight = 1 {
        didSet {
            superview?.setNeedsLayout()
            setNeedsLayout()
        }
    }

    /// The selected item.
    public private(set) var selection: IndexPath?

    /// Called when the selection changes through interaction or `select(_:notify:)`.
    public var onSelectionChanged: (IndexPath?) -> Void = { _ in }

    /// Called when Enter or a double-click activates the selection.
    public var onActivate: (IndexPath) -> Void = { _ in }

    // One host per item: draws the selection marker, holds the built view.
    private var cells: [IndexPath: ItemCell] = [:]
    private var headers: [Label] = []

    /// Creates a collection.
    ///
    /// - Parameters:
    ///   - sections: The sections.
    ///   - builder: Builds the view for an item.
    public init(sections: [Section], builder: @escaping (String) -> TUIView) {
        self.sections = sections
        self.builder = builder
        super.init(frame: .zero)
        reload()
    }

    /// Collections take keyboard focus.
    public override var acceptsFirstResponder: Bool {
        true
    }

    /// Rebuilds every item view from the builder.
    public func reload() {
        for cell in cells.values {
            cell.removeFromSuperview()
        }

        for header in headers {
            header.removeFromSuperview()
        }

        cells = [:]
        headers = []

        for (sectionIndex, section) in sections.enumerated() {
            let header = Label(section.title)
            header.style.flags.insert(.bold)
            header.isHidden = section.title.isEmpty
            headers.append(header)
            addSubview(header)

            for (itemIndex, item) in section.items.enumerated() {
                let cell = ItemCell(content: builder(item))
                cells[IndexPath(section: sectionIndex, item: itemIndex)] = cell
                addSubview(cell)
            }
        }

        if let selection, !exists(selection) {
            self.selection = nil
        }

        if selection == nil, let first = firstIndexPath {
            selection = first
        }

        superview?.setNeedsLayout()
        setNeedsLayout()
        setNeedsDisplay()
    }

    /// Selects an item programmatically.
    ///
    /// - Parameters:
    ///   - indexPath: The item, or `nil`.
    ///   - notify: Whether `onSelectionChanged` fires. Defaults to silent.
    public func select(_ indexPath: IndexPath?, notify: Bool = false) {
        let target = indexPath.flatMap { exists($0) ? $0 : nil }

        guard target != selection else {
            return
        }

        selection = target
        refreshMarkers()

        if notify {
            onSelectionChanged(selection)
        }
    }

    /// Columns that fit the current width (at least one).
    public var columns: Int {
        max(1, bounds.size.width / max(1, itemWidth))
    }

    /// The whole grid at the current width (one column when unmeasured).
    public override var intrinsicContentSize: Size? {
        Size(width: max(bounds.size.width, itemWidth), height: totalHeight(columns: columns))
    }

    /// Headers, then rows of items.
    public override func layoutSubviews() {
        let columns = self.columns
        var y = 0

        for (sectionIndex, section) in sections.enumerated() {
            if !section.title.isEmpty {
                headers[sectionIndex].frame = Rect(x: 0, y: y, width: bounds.size.width, height: 1)
                y += 1
            }

            for itemIndex in section.items.indices {
                let column = itemIndex % columns
                let row = itemIndex / columns
                cells[IndexPath(section: sectionIndex, item: itemIndex)]?.frame = Rect(
                    x: column * itemWidth,
                    y: y + row * itemHeight,
                    width: itemWidth,
                    height: itemHeight
                )
            }

            y += ((section.items.count + columns - 1) / columns) * itemHeight
        }

        refreshMarkers()
    }

    /// Arrows move the selection; Enter activates.
    public override func keyDown(_ key: KeyInput) -> Bool {
        guard key.modifiers.isEmpty, let selection else {
            return false
        }

        switch key.key {
        case .left:
            move(from: selection, by: -1)
            return true

        case .right:
            move(from: selection, by: 1)
            return true

        case .up:
            moveVertically(from: selection, by: -1)
            return true

        case .down:
            moveVertically(from: selection, by: 1)
            return true

        case .enter:
            onActivate(selection)
            return true

        default:
            return false
        }
    }

    /// A click selects; a double-click activates.
    public override func mouseEvent(_ mouse: MouseInput) -> Bool {
        guard mouse.button == .left, let hit = cells.first(where: { $0.value.frame.contains(mouse.position) })?.key else {
            return false
        }

        switch mouse.action {
        case .press:
            select(hit, notify: true)
            return true

        case .click where mouse.clickCount >= 2:
            onActivate(hit)
            return true

        default:
            return false
        }
    }

    // MARK: - Selection walking

    private var flatOrder: [IndexPath] {
        sections.enumerated().flatMap { sectionIndex, section in
            section.items.indices.map { IndexPath(section: sectionIndex, item: $0) }
        }
    }

    private var firstIndexPath: IndexPath? {
        flatOrder.first
    }

    private func exists(_ indexPath: IndexPath) -> Bool {
        sections.indices.contains(indexPath.section) && sections[indexPath.section].items.indices.contains(indexPath.item)
    }

    private func move(from current: IndexPath, by delta: Int) {
        let order = flatOrder

        guard let position = order.firstIndex(of: current) else {
            return
        }

        let target = min(max(0, position + delta), order.count - 1)
        select(order[target], notify: true)
    }

    private func moveVertically(from current: IndexPath, by delta: Int) {
        let columns = self.columns
        let candidate = IndexPath(section: current.section, item: current.item + delta * columns)

        if exists(candidate) {
            select(candidate, notify: true)
            return
        }

        // Past the section's rows: the neighbouring section, same column.
        let sectionIndex = current.section + delta

        guard sections.indices.contains(sectionIndex), !sections[sectionIndex].items.isEmpty else {
            return
        }

        let column = current.item % columns
        let count = sections[sectionIndex].items.count
        let item = delta > 0 ? min(column, count - 1) : min(((count - 1) / columns) * columns + column, count - 1)
        select(IndexPath(section: sectionIndex, item: item), notify: true)
    }

    private func refreshMarkers() {
        for (indexPath, cell) in cells {
            cell.isSelected = indexPath == selection
        }
    }

    private func totalHeight(columns: Int) -> Int {
        sections.reduce(0) { total, section in
            total + (section.title.isEmpty ? 0 : 1) + ((section.items.count + columns - 1) / columns) * itemHeight
        }
    }

    // The host for one item: a two-cell marker column, then the item view.
    private final class ItemCell: TUIView {
        let content: TUIView

        var isSelected = false {
            didSet {
                if isSelected != oldValue {
                    setNeedsDisplay()
                }
            }
        }

        init(content: TUIView) {
            self.content = content
            super.init(frame: .zero)
            addSubview(content)
        }

        override func layoutSubviews() {
            content.frame = Rect(x: 2, y: 0, width: max(0, bounds.size.width - 2), height: bounds.size.height)
        }

        override func draw(_ painter: Painter) {
            let theme = effectiveTheme
            painter.fill(bounds, with: .blank)

            guard isSelected else {
                return
            }

            var style = theme.base

            if let cue = theme.cueAccent(over: theme.background) {
                style.foreground = cue
            }

            painter.write("▸", at: .zero, style: style)
        }
    }
}
