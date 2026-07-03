/// Folder-tab container: a tab bar that selects which content view is shown
/// below it.
///
/// ```text
///   ┌ Files ┐ Edit    View            ← tab bar (row 0); "Files" selected
///   ─────────────────────────         ← separator (row 1)
///   │ the selected tab's content      ← content area (rows 2+)
///   │ view fills this region          │
/// ```
///
/// Each tab owns a content view. Only the selected tab's content is visible
/// and laid out; the others are hidden (so their focusable controls drop out
/// of the Tab order automatically). Left/Right arrows switch tabs when the
/// tab bar has focus, and clicking a tab title selects it.
///
/// ```swift
/// let tabs = TabView()
/// tabs.addTab("Files", content: fileList)
/// tabs.addTab("Edit", content: editor)
/// tabs.onSelectionChanged = { index in print("showing tab \(index)") }
/// ```
@MainActor
public final class TabView: View {
    /// One tab: a title and the content shown when it is selected.
    private struct Tab {
        let title: String
        let content: View
    }

    private var tabs: [Tab] = []

    /// Index of the selected tab.
    public private(set) var selectedIndex = 0

    /// Called when the selected tab changes.
    public var onSelectionChanged: (Int) -> Void = { _ in }

    /// Rows reserved for the tab bar (titles + separator).
    public let tabBarHeight = 2

    // The separator under the titles is a real connected Divider, so an
    // enclosing Panel welds it into its border with ├ ┤ tees.
    private let separator = Divider(axis: .horizontal)

    /// Creates an empty tab view.
    public init() {
        super.init(frame: .zero)
        addSubview(separator)
    }

    /// Number of tabs.
    public var tabCount: Int {
        tabs.count
    }

    /// Adds a tab.
    ///
    /// - Parameters:
    ///   - title: Tab title shown in the bar.
    ///   - content: View shown in the content area when the tab is selected.
    public func addTab(_ title: String, content: View) {
        tabs.append(Tab(title: title, content: content))
        addSubview(content)
        updateVisibility()
        setNeedsLayout()
    }

    /// Title of a tab.
    ///
    /// - Parameter index: Tab index.
    /// - Returns: The title, or `nil` when out of range.
    public func title(at index: Int) -> String? {
        tabs.indices.contains(index) ? tabs[index].title : nil
    }

    /// Selects a tab, showing its content and hiding the others.
    ///
    /// - Parameters:
    ///   - index: Tab to select.
    ///   - notify: Whether `onSelectionChanged` fires. Defaults to silent.
    public func select(_ index: Int, notify: Bool = false) {
        guard tabs.indices.contains(index), index != selectedIndex else {
            return
        }

        selectedIndex = index
        // Visibility is part of selection state, so update it now (a focus
        // query right after select must be correct); the frame is positioned
        // in the deferred layout pass.
        updateVisibility()
        setNeedsLayout()
        setNeedsDisplay()

        if notify {
            onSelectionChanged(index)
        }
    }

    /// Tab views take keyboard focus for tab switching.
    public override var acceptsFirstResponder: Bool {
        !tabs.isEmpty
    }

    /// Positions the separator and the selected content.
    public override func layoutSubviews() {
        updateVisibility()

        separator.frame = Rect(x: 0, y: 1, width: bounds.size.width, height: 1)

        let contentRect = Rect(
            x: 0,
            y: tabBarHeight,
            width: bounds.size.width,
            height: max(0, bounds.size.height - tabBarHeight)
        )

        for (index, tab) in tabs.enumerated() where index == selectedIndex {
            tab.content.frame = contentRect
        }
    }

    // Shows only the selected tab's content. Called eagerly on selection so
    // visibility (and therefore focus order) is always current.
    private func updateVisibility() {
        for (index, tab) in tabs.enumerated() {
            tab.content.isHidden = index != selectedIndex
        }
    }

    /// Draws the tab bar and separator.
    public override func draw(_ painter: Painter) {
        let theme = effectiveTheme
        var x = 0

        for (index, tab) in tabs.enumerated() {
            let label = " \(tab.title) "
            let isSelected = index == selectedIndex
            var style: CellStyle

            if isSelected {
                style = theme.selection

                if isFirstResponder {
                    style.flags.insert(.bold)
                }
            } else {
                style = theme.placeholder
            }

            painter.write(label, at: Point(x: x, y: 0), style: style)
            x += label.count + 1
        }
    }

    /// Left/Right switch tabs.
    public override func keyDown(_ key: KeyInput) -> Bool {
        guard key.modifiers.isEmpty, !tabs.isEmpty else {
            return false
        }

        switch key.key {
        case .left:
            switchTab(by: -1)
            return true

        case .right:
            switchTab(by: 1)
            return true

        default:
            return false
        }
    }

    /// Click on a tab title selects it.
    public override func mouseEvent(_ mouse: MouseInput) -> Bool {
        guard mouse.action == .press, mouse.button == .left, mouse.position.y == 0 else {
            return false
        }

        guard let index = tabIndex(atX: mouse.position.x) else {
            return false
        }

        select(index, notify: true)
        return true
    }

    // MARK: - Geometry

    // Tab whose title x-range contains a local x coordinate. Titles are
    // ` title ` with one trailing gap between tabs.
    private func tabIndex(atX x: Int) -> Int? {
        var start = 0

        for (index, tab) in tabs.enumerated() {
            let width = tab.title.count + 2

            if x >= start, x < start + width {
                return index
            }

            start += width + 1
        }

        return nil
    }

    private func switchTab(by offset: Int) {
        let next = min(max(0, selectedIndex + offset), tabs.count - 1)
        select(next, notify: true)
    }
}
