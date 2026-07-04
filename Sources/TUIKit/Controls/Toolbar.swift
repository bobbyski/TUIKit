/// One command in a `Toolbar`: an optional icon, a title, and an action.
@MainActor
public final class ToolbarItem {
    /// Text shown for the item.
    public var title: String

    /// Optional leading glyph (e.g. `⚙`, `▶`) drawn before the title.
    public var icon: Character?

    /// Disabled items render dim and cannot be activated.
    public var isEnabled: Bool

    /// Called when the item activates.
    public var action: () -> Void

    /// Creates a toolbar item.
    ///
    /// - Parameters:
    ///   - title: Text shown for the item.
    ///   - icon: Optional leading glyph.
    ///   - isEnabled: Whether the item can be activated.
    ///   - action: Called when the item activates.
    public init(
        _ title: String,
        icon: Character? = nil,
        isEnabled: Bool = true,
        action: @escaping () -> Void = {}
    ) {
        self.title = title
        self.icon = icon
        self.isEnabled = isEnabled
        self.action = action
    }

    // Text drawn inside the `[ … ]` segment.
    var label: String {
        switch (icon, title.isEmpty) {
        case (let icon?, false):
            return "\(icon) \(title)"
        case (let icon?, true):
            return String(icon)
        default:
            return title
        }
    }
}

/// Horizontal strip of labeled/icon command buttons, painted on the theme's
/// header slot (so it reads as a title-bar toolbar).
///
/// ```text
///   [ ⚙ Settings ] [ ▶ Run ] [ ■ Stop ]           wide enough
///   [ ⚙ Settings ] [ ▶ Run ] [ » ]                too narrow → overflow
///                            ┌──────────┐
///                            │ ■ Stop   │          hidden items in a menu
///                            └──────────┘
/// ```
///
/// The toolbar is a single focus stop: `←`/`→` move between visible items
/// (skipping disabled ones), Home/End jump to the ends, and Return/Space or
/// a click activates the focused item. When the strip is too narrow to show
/// every item, the trailing ones collapse into a `»` overflow button whose
/// menu lists them; the overflow button is the last focus slot.
///
/// ```swift
/// let bar = Toolbar()
/// bar.addItem("Run", icon: "▶") { session.run() }
/// bar.addItem("Stop", icon: "■") { session.stop() }
/// ```
@MainActor
public final class Toolbar: TUIView {
    /// Commands in display order.
    public private(set) var items: [ToolbarItem] = []

    /// How items signal they are actionable: accent color (`.tinted`, the
    /// default) or bracketed (`.bordered`).
    public var style: ControlStyle = .tinted {
        didSet {
            if style != oldValue {
                superview?.setNeedsLayout()
                setNeedsDisplay()
            }
        }
    }

    // Focused slot: a visible item index, or the overflow slot when it
    // equals the visible-item count.
    private var focusedSlot = 0

    /// Creates an empty toolbar.
    public init() {
        super.init(frame: .zero)
    }

    /// Appends a command.
    ///
    /// - Parameters:
    ///   - title: Text shown for the item.
    ///   - icon: Optional leading glyph.
    ///   - isEnabled: Whether the item can be activated.
    ///   - action: Called when the item activates.
    /// - Returns: The created item.
    @discardableResult
    public func addItem(
        _ title: String,
        icon: Character? = nil,
        isEnabled: Bool = true,
        action: @escaping () -> Void = {}
    ) -> ToolbarItem {
        let item = ToolbarItem(title, icon: icon, isEnabled: isEnabled, action: action)
        items.append(item)
        superview?.setNeedsLayout()
        setNeedsDisplay()
        return item
    }

    /// Toolbars take keyboard focus when they have any item.
    public override var acceptsFirstResponder: Bool {
        !items.isEmpty
    }

    /// One row wide enough to show every item without overflow.
    public override var intrinsicContentSize: Size? {
        Size(width: naturalWidth, height: 1)
    }

    /// Focuses the first enabled item (or the overflow slot) on focus.
    public override func didBecomeFirstResponder() {
        let plan = layout()
        focusedSlot = firstFocusableSlot(in: plan) ?? 0
        setNeedsDisplay()
    }

    /// Draws the header-styled strip, its items, and the overflow button.
    public override func draw(_ painter: Painter) {
        let theme = effectiveTheme
        painter.fill(bounds, with: TerminalCell(character: " ", style: theme.header))

        let plan = layout()

        for slot in 0..<plan.visibleCount {
            let segment = plan.segments[slot]
            drawSegment(
                items[slot].label,
                at: segment.x,
                width: segment.width,
                style: slotStyle(forSlot: slot, item: items[slot], theme: theme),
                painter: painter
            )
        }

        if plan.hasOverflow, let overflowX = plan.overflowX {
            drawSegment(
                "»",
                at: overflowX,
                width: overflowWidth,
                style: slotStyle(forSlot: plan.visibleCount, item: nil, theme: theme),
                painter: painter
            )
        }
    }

    /// Arrows move between slots; Home/End jump; Return/Space activates.
    public override func keyDown(_ key: KeyInput) -> Bool {
        guard key.modifiers.isEmpty else {
            return false
        }

        let plan = layout()

        switch key.key {
        case .left:
            moveFocus(by: -1, in: plan)
            return true

        case .right:
            moveFocus(by: 1, in: plan)
            return true

        case .home:
            focusedSlot = firstFocusableSlot(in: plan) ?? focusedSlot
            setNeedsDisplay()
            return true

        case .end:
            focusedSlot = lastFocusableSlot(in: plan) ?? focusedSlot
            setNeedsDisplay()
            return true

        case .enter, .character(" "):
            activate(slot: min(focusedSlot, plan.slotCount - 1), plan: plan)
            return true

        default:
            return false
        }
    }

    /// Click activates the item (or opens the overflow menu) under the pointer.
    public override func mouseEvent(_ mouse: MouseInput) -> Bool {
        guard mouse.action == .press, mouse.button == .left, mouse.position.y == 0 else {
            return false
        }

        let plan = layout()

        for slot in 0..<plan.visibleCount {
            let segment = plan.segments[slot]

            if mouse.position.x >= segment.x, mouse.position.x < segment.x + segment.width {
                focusedSlot = slot
                activate(slot: slot, plan: plan)
                return true
            }
        }

        if plan.hasOverflow, let overflowX = plan.overflowX,
           mouse.position.x >= overflowX, mouse.position.x < overflowX + overflowWidth {
            focusedSlot = plan.visibleCount
            activate(slot: plan.visibleCount, plan: plan)
            return true
        }

        return false
    }

    // MARK: - Activation

    private func activate(slot: Int, plan: Layout) {
        if plan.hasOverflow, slot == plan.visibleCount {
            openOverflowMenu(plan: plan)
            return
        }

        guard items.indices.contains(slot), items[slot].isEnabled else {
            return
        }

        items[slot].action()
    }

    private func openOverflowMenu(plan: Layout) {
        guard plan.hasOverflow, let window = owningWindow else {
            return
        }

        let menu = Menu("")

        for item in items[plan.visibleCount...] {
            let entry = menu.addItem(item.label, action: item.action)
            entry.isEnabled = item.isEnabled
        }

        let overflowX = plan.overflowX ?? 0
        window.presentContextMenu(menu, at: origin(in: window) + Point(x: overflowX, y: 0))
    }

    // MARK: - Focus helpers

    private func moveFocus(by direction: Int, in plan: Layout) {
        var slot = focusedSlot

        for _ in 0..<max(1, plan.slotCount) {
            slot += direction

            guard slot >= 0, slot < plan.slotCount else {
                return
            }

            if isFocusable(slot: slot, in: plan) {
                focusedSlot = slot
                setNeedsDisplay()
                return
            }
        }
    }

    private func isFocusable(slot: Int, in plan: Layout) -> Bool {
        if plan.hasOverflow, slot == plan.visibleCount {
            return true
        }

        return items.indices.contains(slot) && items[slot].isEnabled
    }

    private func firstFocusableSlot(in plan: Layout) -> Int? {
        (0..<plan.slotCount).first { isFocusable(slot: $0, in: plan) }
    }

    private func lastFocusableSlot(in plan: Layout) -> Int? {
        (0..<plan.slotCount).last { isFocusable(slot: $0, in: plan) }
    }

    // MARK: - Drawing helpers

    private func slotStyle(forSlot slot: Int, item: ToolbarItem?, theme: Theme) -> CellStyle {
        if let item, !item.isEnabled {
            return theme.placeholder
        }

        if isFirstResponder, slot == focusedSlot {
            return theme.selection
        }

        // Resting: the header slot, tinted with the accent (or underlined on
        // a colorless theme) when the tinted style is active.
        var resting = theme.header

        if style == .tinted {
            if theme.accent != .standard {
                resting.foreground = theme.accent
                resting.flags.insert(.bold)
            } else {
                resting.flags.insert(.underline)
            }
        }

        return resting
    }

    private func drawSegment(_ label: String, at x: Int, width: Int, style cellStyle: CellStyle, painter: Painter) {
        let pad = style.horizontalPadding
        let inner = Label.truncated(label, width: max(0, width - pad))
        let content = inner + String(repeating: " ", count: max(0, width - pad - inner.count))
        painter.write(style.decorate(content), at: Point(x: x, y: 0), style: cellStyle)
    }

    // MARK: - Layout

    // A resolved placement: which items are visible, where each sits, and
    // whether the trailing items collapsed into an overflow button.
    private struct Layout {
        var visibleCount: Int
        var hasOverflow: Bool
        var segments: [(x: Int, width: Int)]
        var overflowX: Int?

        // Total focus slots: visible items plus the overflow button.
        var slotCount: Int {
            visibleCount + (hasOverflow ? 1 : 0)
        }
    }

    // Segment width for an item's decorated rendering.
    private func segmentWidth(_ item: ToolbarItem) -> Int {
        item.label.count + style.horizontalPadding
    }

    // Width of the trailing `»` overflow button in the current style.
    private var overflowWidth: Int {
        1 + style.horizontalPadding
    }

    // Width needed to show every item, single-space separated.
    private var naturalWidth: Int {
        guard !items.isEmpty else {
            return 0
        }

        return items.reduce(0) { $0 + segmentWidth($1) } + (items.count - 1)
    }

    // Greedy left-to-right fit; trailing items overflow into a `»` menu.
    private func layout() -> Layout {
        let width = bounds.size.width

        if naturalWidth <= width || items.isEmpty {
            var segments: [(x: Int, width: Int)] = []
            var x = 0

            for item in items {
                let itemWidth = segmentWidth(item)
                segments.append((x: x, width: itemWidth))
                x += itemWidth + 1
            }

            return Layout(visibleCount: items.count, hasOverflow: false, segments: segments, overflowX: nil)
        }

        // Overflow needed: reserve room for the trailing `»` button plus the
        // space before it.
        let overflowReserve = overflowWidth + 1
        var segments: [(x: Int, width: Int)] = []
        var x = 0
        var visible = 0

        for item in items {
            let separator = visible == 0 ? 0 : 1
            let itemWidth = segmentWidth(item)

            if x + separator + itemWidth + overflowReserve <= width {
                x += separator
                segments.append((x: x, width: itemWidth))
                x += itemWidth
                visible += 1
            } else {
                break
            }
        }

        let overflowX = visible == 0 ? 0 : x + 1
        return Layout(visibleCount: visible, hasOverflow: true, segments: segments, overflowX: overflowX)
    }

    // MARK: - Window plumbing

    private var owningWindow: Window? {
        var current: TUIView? = self

        while let view = current {
            if let window = view as? Window {
                return window
            }

            current = view.superview
        }

        return nil
    }

    // This view's origin in the given window's coordinates.
    private func origin(in window: Window) -> Point {
        var origin = Point.zero
        var current: TUIView? = self

        while let view = current, view !== window {
            origin = origin + view.frame.origin
            current = view.superview
        }

        return origin
    }
}
