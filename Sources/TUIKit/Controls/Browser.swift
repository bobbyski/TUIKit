/// One row in a `Browser` column.
public struct BrowserItem {
    /// Text shown for the row.
    public var title: String

    /// Whether selecting the row opens a further column of children.
    public var isExpandable: Bool

    /// Caller-defined payload (e.g. a file-system path).
    public var representedValue: Any?

    /// Creates a browser item.
    ///
    /// - Parameters:
    ///   - title: Text shown for the row.
    ///   - isExpandable: Whether it opens a child column.
    ///   - representedValue: Caller-defined payload.
    public init(_ title: String, isExpandable: Bool = false, representedValue: Any? = nil) {
        self.title = title
        self.isExpandable = isExpandable
        self.representedValue = representedValue
    }
}

/// Supplies a `Browser`'s columns on demand.
///
/// The browser asks for the root once, then for each expandable item's
/// children the first time that item is selected — so a large or lazy tree
/// (a file system, an API) only materializes the path the user walks.
@MainActor
public protocol BrowserDataSource: AnyObject {
    /// Rows for the leftmost column.
    ///
    /// - Parameter browser: The requesting browser.
    /// - Returns: The root rows.
    func browserRootItems(_ browser: Browser) -> [BrowserItem]

    /// Rows for the column revealed by selecting an expandable item.
    ///
    /// - Parameters:
    ///   - browser: The requesting browser.
    ///   - item: The selected expandable item.
    /// - Returns: The item's child rows.
    func browser(_ browser: Browser, childrenOf item: BrowserItem) -> [BrowserItem]
}

/// Miller-column browser: side-by-side lists where selecting a row reveals
/// its children in the next column.
///
/// ```text
///   Projects  │ TUIKit    │ Sources    │
///   Music    ›│▸Docs     ›│ Controls  ›│
///  ▸Photos   ›│ README    │▸Terminal  ›│
/// ```
///
/// `↑`/`↓` move within the focused column, `←`/`→` step between columns
/// (right descends into the selected item's children), and Return activates
/// the focused row. It is the third consumer of `RowNavigationState` (after
/// `ListView` and `TableView`), one instance per column. Feed it any
/// `BrowserDataSource`, or point it at a file system:
///
/// ```swift
/// let browser = Browser(fileSystemRoot: "/Users/bobby", provider: LocalFileSystem())
/// browser.onSelectionChanged = { item in preview(item) }
/// ```
@MainActor
public final class Browser: View {
    /// Width of each column in cells.
    public var columnWidth: Int {
        didSet {
            if columnWidth != oldValue {
                setNeedsDisplay()
            }
        }
    }

    /// Called when the focused selection changes.
    public var onSelectionChanged: (BrowserItem?) -> Void = { _ in }

    /// Called when the focused row is activated with Return.
    public var onActivate: (BrowserItem) -> Void = { _ in }

    private let dataSource: any BrowserDataSource
    private var columns: [Column] = []
    private var focusedColumn = 0

    // One column: its rows plus the shared row-navigation core.
    private struct Column {
        var items: [BrowserItem]
        var nav: RowNavigationState

        init(items: [BrowserItem]) {
            self.items = items
            var nav = RowNavigationState()
            nav.count = items.count
            self.nav = nav
        }
    }

    /// Creates a browser over a data source.
    ///
    /// - Parameters:
    ///   - dataSource: Supplies columns on demand.
    ///   - columnWidth: Width of each column.
    public init(dataSource: any BrowserDataSource, columnWidth: Int = 18) {
        self.dataSource = dataSource
        self.columnWidth = max(4, columnWidth)
        super.init(frame: .zero)
        reload()
    }

    /// Creates a browser over a file system.
    ///
    /// - Parameters:
    ///   - fileSystemRoot: Absolute path of the root directory.
    ///   - provider: File-system source (defaults to the real disk).
    ///   - showsFiles: Whether files appear (directories always do).
    ///   - columnWidth: Width of each column.
    public convenience init(
        fileSystemRoot: String,
        provider: FileSystemProvider = LocalFileSystem(),
        showsFiles: Bool = true,
        columnWidth: Int = 18
    ) {
        self.init(
            dataSource: FileSystemBrowserDataSource(root: fileSystemRoot, provider: provider, showsFiles: showsFiles),
            columnWidth: columnWidth
        )
    }

    /// Browsers take keyboard focus.
    public override var acceptsFirstResponder: Bool {
        true
    }

    /// A default three-column footprint; usually given an explicit frame.
    public override var intrinsicContentSize: Size? {
        Size(width: columnWidth * 3 + 2, height: 10)
    }

    /// The focused column's selected item, when any.
    public var selectedItem: BrowserItem? {
        guard columns.indices.contains(focusedColumn),
              let index = columns[focusedColumn].nav.selectedIndex else {
            return nil
        }

        return columns[focusedColumn].items[index]
    }

    /// Rebuilds from the root, discarding all navigation.
    public func reload() {
        columns = [Column(items: dataSource.browserRootItems(self))]
        focusedColumn = 0
        setNeedsDisplay()
    }

    /// Selects the first root row on focus, so a focused browser shows a
    /// highlight.
    public override func didBecomeFirstResponder() {
        if columns.indices.contains(0), columns[0].nav.selectedIndex == nil, !columns[0].items.isEmpty {
            setSelection(0, inColumn: 0, notify: true)
        }
    }

    /// Draws the visible columns and their dividers.
    public override func draw(_ painter: Painter) {
        let theme = effectiveTheme
        let height = bounds.size.height

        guard height > 0, columnWidth > 0 else {
            return
        }

        let vertical = (theme.borderStyle.characters ?? BorderStyle.single.characters!).vertical
        let start = firstVisibleColumn
        let end = min(columns.count, start + columnsThatFit)

        for slot in 0..<(end - start) {
            let columnIndex = start + slot
            let x0 = slot * (columnWidth + 1)
            drawColumn(columnIndex, atX: x0, painter: painter, theme: theme)

            let dividerX = x0 + columnWidth

            if dividerX < bounds.size.width {
                for y in 0..<height {
                    painter.set(TerminalCell(character: vertical, style: theme.border), at: Point(x: dividerX, y: y))
                }
            }
        }
    }

    /// Arrows navigate; Return activates.
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
            moveSelection(to: columnItemCount(focusedColumn) - 1)
            return true

        case .left:
            focusColumn(focusedColumn - 1)
            return true

        case .right:
            descend()
            return true

        case .enter:
            if let item = selectedItem {
                onActivate(item)
            }

            return true

        default:
            return false
        }
    }

    /// Click focuses a column and selects the row under the pointer.
    public override func mouseEvent(_ mouse: MouseInput) -> Bool {
        guard mouse.action == .press, mouse.button == .left else {
            return false
        }

        let start = firstVisibleColumn
        let end = min(columns.count, start + columnsThatFit)

        for slot in 0..<(end - start) {
            let x0 = slot * (columnWidth + 1)

            guard mouse.position.x >= x0, mouse.position.x < x0 + columnWidth else {
                continue
            }

            let columnIndex = start + slot
            let row = columns[columnIndex].nav.scrollOffset + mouse.position.y

            guard columns[columnIndex].items.indices.contains(row) else {
                return false
            }

            focusedColumn = columnIndex
            setSelection(row, inColumn: columnIndex, notify: true)
            return true
        }

        return false
    }

    // MARK: - Navigation

    private func moveSelection(by offset: Int) {
        guard columns.indices.contains(focusedColumn) else {
            return
        }

        var nav = columns[focusedColumn].nav

        guard nav.move(by: offset) else {
            return
        }

        setSelection(nav.selectedIndex, inColumn: focusedColumn, notify: true)
    }

    private func moveSelection(to index: Int) {
        guard columns.indices.contains(focusedColumn), index >= 0 else {
            return
        }

        setSelection(index, inColumn: focusedColumn, notify: true)
    }

    // Steps into the selected item's child column, if it has one.
    private func descend() {
        guard columns.indices.contains(focusedColumn + 1), !columns[focusedColumn + 1].items.isEmpty else {
            return
        }

        focusedColumn += 1

        if columns[focusedColumn].nav.selectedIndex == nil {
            setSelection(0, inColumn: focusedColumn, notify: true)
        } else {
            setNeedsDisplay()
            onSelectionChanged(selectedItem)
        }
    }

    private func focusColumn(_ column: Int) {
        guard column >= 0, column < columns.count, column != focusedColumn else {
            return
        }

        focusedColumn = column
        setNeedsDisplay()
        onSelectionChanged(selectedItem)
    }

    // Selects a row in a column, rebuilding the child column beneath it.
    private func setSelection(_ index: Int?, inColumn column: Int, notify: Bool) {
        guard columns.indices.contains(column), columns[column].nav.select(index) else {
            return
        }

        columns[column].nav.ensureSelectionVisible(height: bounds.size.height)

        // Discard now-stale deeper columns.
        if columns.count > column + 1 {
            columns.removeSubrange((column + 1)...)
        }

        // Reveal the selected item's children in a fresh column.
        if let selected = columns[column].nav.selectedIndex {
            let item = columns[column].items[selected]

            if item.isExpandable {
                let children = dataSource.browser(self, childrenOf: item)
                columns.append(Column(items: children))
            }
        }

        setNeedsDisplay()

        if notify {
            onSelectionChanged(selectedItem)
        }
    }

    // MARK: - Drawing

    private func drawColumn(_ columnIndex: Int, atX x0: Int, painter: Painter, theme: Theme) {
        let column = columns[columnIndex]
        let isFocused = columnIndex == focusedColumn

        for row in 0..<bounds.size.height {
            let index = column.nav.scrollOffset + row

            guard index < column.items.count else {
                break
            }

            let item = column.items[index]
            let isSelected = index == column.nav.selectedIndex
            var style = CellStyle()

            if isSelected {
                style = theme.selection

                if isFocused, isFirstResponder {
                    style.flags.insert(.bold)
                }
            }

            let markerWidth = item.isExpandable ? 1 : 0
            let title = Label.truncated(item.title, width: max(0, columnWidth - markerWidth))
            var text = title + String(repeating: " ", count: max(0, columnWidth - markerWidth - title.count))

            if item.isExpandable {
                text += "›"
            }

            painter.write(text, at: Point(x: x0, y: row), style: style)
        }
    }

    // MARK: - Layout helpers

    private func columnItemCount(_ column: Int) -> Int {
        columns.indices.contains(column) ? columns[column].items.count : 0
    }

    // How many columns fit side by side (with 1-cell dividers).
    private var columnsThatFit: Int {
        let width = bounds.size.width

        guard width > 0 else {
            return 1
        }

        return max(1, (width + 1) / (columnWidth + 1))
    }

    // Leftmost visible column, scrolled so the focused column shows.
    private var firstVisibleColumn: Int {
        max(0, focusedColumn - columnsThatFit + 1)
    }
}

/// `BrowserDataSource` backed by a `FileSystemProvider`.
///
/// Directories are expandable; each item carries its absolute path as its
/// represented value, so children load by listing that path. Entries sort
/// directories-first, then case-insensitively by name.
@MainActor
public final class FileSystemBrowserDataSource: BrowserDataSource {
    private let root: String
    private let provider: FileSystemProvider
    private let showsFiles: Bool

    /// Creates a file-system data source.
    ///
    /// - Parameters:
    ///   - root: Absolute path of the root directory.
    ///   - provider: File-system source.
    ///   - showsFiles: Whether files appear.
    public init(root: String, provider: FileSystemProvider, showsFiles: Bool = true) {
        self.root = root
        self.provider = provider
        self.showsFiles = showsFiles
    }

    /// Rows for the root directory.
    public func browserRootItems(_ browser: Browser) -> [BrowserItem] {
        items(at: root)
    }

    /// Rows for a directory item's contents.
    public func browser(_ browser: Browser, childrenOf item: BrowserItem) -> [BrowserItem] {
        guard let path = item.representedValue as? String else {
            return []
        }

        return items(at: path)
    }

    private func items(at path: String) -> [BrowserItem] {
        provider.entries(at: path)
            .filter { showsFiles || $0.isDirectory }
            .sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory {
                    return lhs.isDirectory
                }

                return lhs.name.lowercased() < rhs.name.lowercased()
            }
            .map { entry in
                let childPath = path.hasSuffix("/") ? path + entry.name : path + "/" + entry.name
                return BrowserItem(entry.name, isExpandable: entry.isDirectory, representedValue: childPath)
            }
    }
}
