/// One node of a `TreeView`: a title, children, and expansion state.
///
/// Children can be provided lazily: give the node a `childProvider` and it
/// is called once, on first expansion — the pattern for file systems and
/// other hierarchies too big to build up front.
///
/// ```swift
/// let root = TreeNode("Sources", childProvider: { listDirectory("Sources") })
/// ```
@MainActor
public final class TreeNode {
    /// Text shown for the node.
    public var title: String

    /// Child nodes loaded so far.
    public private(set) var children: [TreeNode] = []

    /// The owning node, when attached.
    public private(set) weak var parent: TreeNode?

    /// Whether the node shows its children.
    public var isExpanded = false

    /// Arbitrary value the node stands for (a path, a model object, …).
    ///
    /// The tree never touches this; controls built on `TreeView` (like
    /// `DirectoryTree`) use it to map nodes back to their domain.
    public var representedValue: Any?

    // Lazy loader, consumed on first expansion.
    private var childProvider: (() -> [TreeNode])?

    /// Creates a node.
    ///
    /// - Parameters:
    ///   - title: Text shown for the node.
    ///   - children: Eager child nodes.
    ///   - childProvider: Called once on first expansion to load children
    ///     lazily; a node with a provider shows a disclosure triangle even
    ///     before loading.
    public init(
        _ title: String,
        children: [TreeNode] = [],
        childProvider: (() -> [TreeNode])? = nil
    ) {
        self.title = title
        self.childProvider = childProvider

        for child in children {
            addChild(child)
        }
    }

    /// Whether the node can expand (has children, loaded or pending).
    public var isExpandable: Bool {
        !children.isEmpty || childProvider != nil
    }

    /// Appends a child node.
    ///
    /// - Parameter child: Node to append.
    public func addChild(_ child: TreeNode) {
        child.parent = self
        children.append(child)
    }

    // Loads lazy children, once.
    func loadChildrenIfNeeded() {
        guard let provider = childProvider else {
            return
        }

        childProvider = nil

        for child in provider() {
            addChild(child)
        }
    }
}

/// Hierarchical outline with expand/collapse, built on the shared row
/// navigation core.
///
/// The tree flattens its expanded nodes into rows, so navigation is exactly
/// `ListView`'s: arrows, paging, Home/End, wheel scrolling, click to select.
/// The disclosure keys follow the platform convention: `→` expands (then
/// steps into the first child), `←` collapses (then steps to the parent).
/// Clicking a disclosure triangle toggles it; Return — or a double-click —
/// activates a leaf and toggles a branch.
///
/// ```swift
/// let tree = TreeView(roots: [projectRoot])
/// tree.onSelectionChanged = { node in preview(node) }
/// tree.onActivate = { node in open(node) }
/// ```
@MainActor
public final class TreeView: TUIView {
    /// Top-level nodes.
    public var roots: [TreeNode] {
        didSet {
            rebuildVisibleRows()
            setNeedsDisplay()
        }
    }

    /// Called when the selected node changes (`nil` when cleared).
    public var onSelectionChanged: (TreeNode?) -> Void = { _ in }

    /// Called when a leaf node is activated — Return, or a double-click.
    public var onActivate: (TreeNode) -> Void = { _ in }

    // Shared navigation core over the flattened rows.
    private var navigation = RowNavigationState()

    // Expanded nodes flattened depth-first, with their indentation depth.
    private var visibleRows: [(node: TreeNode, depth: Int)] = []

    /// Creates a tree.
    ///
    /// - Parameter roots: Top-level nodes.
    public init(roots: [TreeNode] = []) {
        self.roots = roots
        super.init(frame: .zero)
        rebuildVisibleRows()
    }

    /// The selected node, when any.
    public var selectedNode: TreeNode? {
        navigation.selectedIndex.map { visibleRows[$0].node }
    }

    /// Number of currently visible (flattened) rows.
    public var visibleRowCount: Int {
        visibleRows.count
    }

    /// Trees take keyboard focus.
    public override var acceptsFirstResponder: Bool {
        true
    }

    /// Selects the first row on focus so a focused tree shows a highlight.
    public override func didBecomeFirstResponder() {
        if navigation.selectedIndex == nil, !visibleRows.isEmpty {
            select(visibleRows[0].node, notify: true)
        }
    }

    /// Selects a node programmatically (expanding nothing).
    ///
    /// - Parameters:
    ///   - node: Node to select, or `nil` to clear; a node that is not
    ///     currently visible clears the selection.
    ///   - notify: Whether `onSelectionChanged` fires. Defaults to silent.
    public func select(_ node: TreeNode?, notify: Bool = false) {
        let index = node.flatMap { target in
            visibleRows.firstIndex { $0.node === target }
        }

        guard navigation.select(index) else {
            return
        }

        navigation.ensureSelectionVisible(height: bounds.size.height)
        setNeedsDisplay()

        if notify {
            onSelectionChanged(selectedNode)
        }
    }

    /// Expands a node (loading lazy children on first expansion).
    ///
    /// - Parameter node: Node to expand.
    public func expand(_ node: TreeNode) {
        guard node.isExpandable, !node.isExpanded else {
            return
        }

        node.loadChildrenIfNeeded()
        node.isExpanded = true
        rebuildVisibleRows()
        setNeedsDisplay()
    }

    /// Collapses a node.
    ///
    /// - Parameter node: Node to collapse.
    public func collapse(_ node: TreeNode) {
        guard node.isExpanded else {
            return
        }

        node.isExpanded = false
        rebuildVisibleRows()
        setNeedsDisplay()
    }

    /// Collapses an expanded node, or expands a collapsed one.
    public func toggle(_ node: TreeNode) {
        node.isExpanded ? collapse(node) : expand(node)
    }

    /// Draws the visible rows: indentation, disclosure, title.
    public override func draw(_ painter: Painter) {
        let height = bounds.size.height
        let width = bounds.size.width

        guard height > 0, width > 0 else {
            return
        }

        for viewportRow in 0..<height {
            let index = navigation.scrollOffset + viewportRow

            guard index < visibleRows.count else {
                break
            }

            let (node, depth) = visibleRows[index]
            var style = CellStyle()

            if index == navigation.selectedIndex {
                style = effectiveTheme.selection

                if isFirstResponder {
                    style.flags.insert(.bold)
                }
            }

            let disclosure = node.isExpandable ? (node.isExpanded ? "▾" : "▸") : " "
            let text = String(repeating: " ", count: depth * 2) + disclosure + " " + node.title
            let truncated = Label.truncated(text, width: width)
            let padded = truncated + String(repeating: " ", count: max(0, width - truncated.count))

            painter.write(padded, at: Point(x: 0, y: viewportRow), style: style)
        }
    }

    /// Navigation, disclosure (`←`/`→`), and activation keys.
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
            moveSelection(by: -max(1, bounds.size.height - 1))
            return true

        case .pageDown:
            moveSelection(by: max(1, bounds.size.height - 1))
            return true

        case .home:
            moveSelection(to: 0)
            return true

        case .end:
            moveSelection(to: visibleRows.count - 1)
            return true

        case .right:
            guard let selected = selectedNode else {
                return true
            }

            if selected.isExpandable, !selected.isExpanded {
                expand(selected)
            } else if selected.isExpanded, !selected.children.isEmpty {
                moveSelection(by: 1)   // first child is the next visible row
            }

            return true

        case .left:
            guard let selected = selectedNode else {
                return true
            }

            if selected.isExpanded {
                collapse(selected)
            } else if let parent = selected.parent {
                select(parent, notify: true)
            }

            return true

        case .enter:
            if let selected = selectedNode {
                onActivate(selected)
            }

            return true

        default:
            return false
        }
    }

    /// A settled click selects; the disclosure triangle (or a double-click on a
    /// branch) toggles it, and a double-click on a leaf activates it. Nothing
    /// acts on the raw press, so a double-click never runs the single-click
    /// action first. The wheel scrolls.
    public override func mouseEvent(_ mouse: MouseInput) -> Bool {
        switch mouse.action {
        case .press where mouse.button == .left:
            return true   // consume; the settled click does the work

        case .click:
            let index = navigation.scrollOffset + mouse.position.y

            guard index < visibleRows.count else {
                return false
            }

            let (node, depth) = visibleRows[index]

            if mouse.position.x == depth * 2, node.isExpandable {
                // The disclosure triangle toggles once, whatever the click
                // count; the selection follows the click.
                moveSelection(to: index)
                toggle(node)
            } else if mouse.clickCount >= 2 {
                // A double is ONLY the double action: the highlight moves
                // silently (no `onSelectionChanged`), then a branch toggles or
                // a leaf activates.
                select(node)

                if node.isExpandable {
                    toggle(node)
                } else {
                    onActivate(node)
                }
            } else {
                moveSelection(to: index)
            }

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

    // MARK: - Flattening & selection

    // Rebuilds the flattened rows, keeping the selected node selected when
    // it is still visible (its ancestors are all expanded).
    private func rebuildVisibleRows() {
        let previous = selectedNode

        visibleRows = []
        for root in roots {
            appendVisible(root, depth: 0)
        }

        navigation.count = visibleRows.count

        let index = previous.flatMap { target in
            visibleRows.firstIndex { $0.node === target }
        }

        navigation.select(index)
        navigation.ensureSelectionVisible(height: bounds.size.height)
    }

    private func appendVisible(_ node: TreeNode, depth: Int) {
        visibleRows.append((node, depth))

        guard node.isExpanded else {
            return
        }

        for child in node.children {
            appendVisible(child, depth: depth + 1)
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
        onSelectionChanged(selectedNode)
    }
}
