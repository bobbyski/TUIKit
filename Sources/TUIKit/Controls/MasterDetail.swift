/// One sidebar row: an icon, a title, and a wrapping subtitle.
public struct SidebarItem: Sendable {
    /// A glyph before the title.
    public var icon: Character?

    /// The row's title.
    public var title: String

    /// Dimmed text under the title.
    public var subtitle: String?

    /// Creates a row.
    public init(icon: Character? = nil, title: String, subtitle: String? = nil) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
    }
}

/// The sidebar's source list — icon, title, subtitle per row.
///
/// ```text
///   ▸ ✉ Inbox
///       12 unread
///     ★ Starred
///       3 flagged
/// ```
///
/// Rows are two lines when any item has a subtitle, one otherwise. Arrows
/// move, Enter activates, a click selects; the list scrolls to keep the
/// selection visible.
@MainActor
public final class SidebarList: TUIView {
    /// The rows.
    public var items: [SidebarItem] {
        didSet {
            if let selectedIndex, selectedIndex >= items.count {
                self.selectedIndex = items.isEmpty ? nil : items.count - 1
            }

            superview?.setNeedsLayout()
            setNeedsDisplay()
        }
    }

    /// The selected row.
    public private(set) var selectedIndex: Int?

    /// Called when the selection changes through interaction or `select(_:notify:)`.
    public var onSelectionChanged: (Int?) -> Void = { _ in }

    /// Called when Enter or a double-click activates the selected row.
    public var onActivate: (Int) -> Void = { _ in }

    private var scrollOffset = 0

    /// Creates a list.
    ///
    /// - Parameter items: The rows.
    public init(items: [SidebarItem] = []) {
        self.items = items
        selectedIndex = items.isEmpty ? nil : 0
        super.init(frame: .zero)
    }

    /// Lists take keyboard focus.
    public override var acceptsFirstResponder: Bool {
        true
    }

    /// Rows of the widest title.
    public override var intrinsicContentSize: Size? {
        let widest = items.map { $0.title.count + 4 }.max() ?? 10
        return Size(width: max(widest, 16), height: items.count * rowHeight)
    }

    /// Sets the selection programmatically.
    ///
    /// - Parameters:
    ///   - index: The row, or `nil`.
    ///   - notify: Whether `onSelectionChanged` fires. Defaults to silent.
    public func select(_ index: Int?, notify: Bool = false) {
        let target = index.flatMap { items.indices.contains($0) ? $0 : nil }

        guard target != selectedIndex else {
            return
        }

        selectedIndex = target
        revealSelection()
        setNeedsDisplay()

        if notify {
            onSelectionChanged(selectedIndex)
        }
    }

    /// Two lines per row when any subtitle exists.
    public var rowHeight: Int {
        items.contains { $0.subtitle != nil } ? 2 : 1
    }

    /// Draws the rows.
    public override func draw(_ painter: Painter) {
        let theme = effectiveTheme
        painter.fill(bounds, with: .blank)
        let width = bounds.size.width

        for (index, item) in items.enumerated() {
            let y = (index - scrollOffset) * rowHeight

            guard y >= 0, y < bounds.size.height else {
                continue
            }

            let selected = index == selectedIndex
            let style = selected ? theme.selection : theme.base
            let marker = selected && isFirstResponder ? "▸" : " "
            let icon = item.icon.map { "\($0) " } ?? ""
            let title = Label.truncated(marker + icon + item.title, width: width)
            painter.write(title.padding(toLength: width, withPad: " ", startingAt: 0), at: Point(x: 0, y: y), style: style)

            if rowHeight == 2, y + 1 < bounds.size.height {
                var dim = selected ? theme.selection : theme.placeholder
                if !selected { dim.background = theme.background }
                let subtitle = Label.truncated("   " + (item.subtitle ?? ""), width: width)
                painter.write(subtitle.padding(toLength: width, withPad: " ", startingAt: 0), at: Point(x: 0, y: y + 1), style: dim)
            }
        }
    }

    /// Arrows move, Enter activates.
    public override func keyDown(_ key: KeyInput) -> Bool {
        guard key.modifiers.isEmpty, !items.isEmpty else {
            return false
        }

        switch key.key {
        case .up:
            move(by: -1)
            return true

        case .down:
            move(by: 1)
            return true

        case .home:
            select(0, notify: true)
            return true

        case .end:
            select(items.count - 1, notify: true)
            return true

        case .enter:
            if let selectedIndex {
                onActivate(selectedIndex)
            }
            return true

        default:
            return false
        }
    }

    /// A click selects; a double-click activates.
    public override func mouseEvent(_ mouse: MouseInput) -> Bool {
        guard mouse.button == .left else {
            return false
        }

        let index = mouse.position.y / rowHeight + scrollOffset

        switch mouse.action {
        case .press:
            if items.indices.contains(index) {
                select(index, notify: true)
            }
            return true

        case .click where mouse.clickCount >= 2:
            if items.indices.contains(index) {
                onActivate(index)
            }
            return true

        default:
            return false
        }
    }

    private func move(by delta: Int) {
        let current = selectedIndex ?? -1
        select(min(max(0, current + delta), items.count - 1), notify: true)
    }

    private func revealSelection() {
        guard let selectedIndex, rowHeight > 0 else {
            return
        }

        let visibleRows = max(1, bounds.size.height / rowHeight)

        if selectedIndex < scrollOffset {
            scrollOffset = selectedIndex
        } else if selectedIndex >= scrollOffset + visibleRows {
            scrollOffset = selectedIndex - visibleRows + 1
        }
    }
}

/// Master–detail: a source list driving a detail pane, adaptive to width.
///
/// ```text
///   wide:                              narrow (< adaptiveWidth):
///   ▸ ✉ Inbox    │ (detail for Inbox)   ◂ Back   Inbox
///     ★ Starred  │                      (detail for Inbox)
/// ```
///
/// Give it items and a closure that builds the detail for an index. On a
/// wide terminal it tiles the list beside the detail in a `SplitView`; when
/// the width drops below `adaptiveWidth` it becomes a `Navigator` — the list
/// is the root and selecting pushes the detail, with Back to return. The
/// same control, the same items, either way.
///
/// Not to be confused with the TUIKit *sidebar*: that is `SlideOut`, the
/// full-height panel that slides out of a window's edge (OmegaCLIDE's left
/// pane), revealed by shifting the window content aside.
///
/// ```swift
/// let mail = MasterDetail(items: folders) { index in folderView(folders[index]) }
/// mail.onSelectionChanged = { index in status.text = folders[index ?? 0].title }
/// ```
@MainActor
public final class MasterDetail: TUIView {
    /// The list.
    public let list: SidebarList

    /// Builds the detail for a row.
    public var detail: (Int) -> TUIView

    /// Width of the list when tiled.
    public var sidebarWidth = 24 {
        didSet {
            setNeedsLayout()
        }
    }

    /// Below this many columns the sidebar pushes instead of tiling.
    public var adaptiveWidth = 60 {
        didSet {
            setNeedsLayout()
        }
    }

    /// Called when the selection changes.
    public var onSelectionChanged: (Int?) -> Void = { _ in }

    /// Whether the sidebar is currently in its narrow, push mode.
    public private(set) var isCompact = false

    // Two homes for the one list: the split's first pane when tiled, the
    // navigator's root when compact. The hosts stay put; the list moves.
    private let split: SplitView
    private let listHost = TUIView()
    private let detailHost = TUIView()
    private let compactHost = TUIView()
    private let navigator: Navigator
    private var currentDetail: TUIView?

    /// Creates a sidebar.
    ///
    /// - Parameters:
    ///   - items: The rows.
    ///   - detail: Builds the detail for a row.
    public init(items: [SidebarItem], detail: @escaping (Int) -> TUIView) {
        list = SidebarList(items: items)
        self.detail = detail
        split = SplitView(axis: .horizontal, first: listHost, second: detailHost)
        navigator = Navigator(root: compactHost, title: "")
        super.init(frame: .zero)

        split.anchors = .fill()
        navigator.anchors = .fill()
        navigator.isHidden = true
        addSubview(split)
        addSubview(navigator)
        list.anchors = .fill()
        listHost.addSubview(list)

        list.onSelectionChanged = { [weak self] index in
            self?.selectionChanged(index)
        }

        list.onActivate = { [weak self] index in
            guard let self else { return }
            if self.isCompact {
                self.pushDetail(index)
            }
        }

        showDetail(list.selectedIndex)
    }

    /// Tiles or pushes, by width.
    public override func layoutSubviews() {
        super.layoutSubviews()   // the split and navigator are anchored to fill
        let compact = bounds.size.width < adaptiveWidth

        if compact != isCompact {
            isCompact = compact
            rehome()
        }

        if !isCompact {
            split.setDividerPosition(min(sidebarWidth, max(8, bounds.size.width - 8)))
        }
    }

    // Moves the list between the split and the navigator as the mode flips.
    private func rehome() {
        list.removeFromSuperview()
        navigator.popToRoot()

        if isCompact {
            split.isHidden = true
            navigator.isHidden = false
            compactHost.addSubview(list)
        } else {
            navigator.isHidden = true
            split.isHidden = false
            listHost.addSubview(list)
            showDetail(list.selectedIndex)
        }

        setNeedsLayout()
        setNeedsDisplay()
    }

    private func selectionChanged(_ index: Int?) {
        if !isCompact {
            showDetail(index)
        }

        onSelectionChanged(index)
    }

    private func showDetail(_ index: Int?) {
        currentDetail?.removeFromSuperview()
        currentDetail = nil

        guard let index, list.items.indices.contains(index) else {
            return
        }

        let view = detail(index)
        view.anchors = .fill()
        detailHost.addSubview(view)
        currentDetail = view
        detailHost.setNeedsLayout()
        detailHost.setNeedsDisplay()
    }

    private func pushDetail(_ index: Int) {
        guard list.items.indices.contains(index) else {
            return
        }

        navigator.push(detail(index), title: list.items[index].title)
    }
}
