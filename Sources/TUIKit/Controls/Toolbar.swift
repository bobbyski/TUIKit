import Foundation

/// A toolbar/ribbon icon: a glyph for a text terminal, a picture for a
/// vector one.
///
/// Both, ideally. A VTG terminal draws the image; every other terminal draws
/// the glyph. Supplying only a glyph is the common case and perfectly fine —
/// supplying only an image is not, because it would leave a blank cell on the
/// terminals most people run, so the glyph is the required half.
public struct ToolbarIcon: Hashable, Sendable {
    /// Drawn on a text terminal, and as the fallback everywhere.
    public var glyph: Character

    /// PNG/JPEG bytes drawn instead on a VTG terminal.
    public var imageData: Data?

    /// Which format ``imageData`` is.
    public var imageFormat: ChromeCommand.ImageFormat

    /// Creates an icon.
    ///
    /// - Parameters:
    ///   - glyph: The character a text terminal shows. Required — see above.
    ///   - imageData: Optional raster drawn on a VTG terminal.
    ///   - imageFormat: Format of `imageData`.
    public init(
        glyph: Character,
        imageData: Data? = nil,
        imageFormat: ChromeCommand.ImageFormat = .png
    ) {
        self.glyph = glyph
        self.imageData = imageData
        self.imageFormat = imageFormat
    }
}

/// How a bar shows its buttons.
public enum ToolbarDisplayMode: Hashable, Sendable {
    /// Glyphs only, one row. The cheapest a bar can be.
    case iconOnly

    /// Titles only, one row — and the mode hosted controls live in happily,
    /// since a search field has no icon to show.
    case textOnly

    /// Glyph above title: the icon row plus ONE row for labels.
    ///
    /// The extra row is what makes this mode cost double, and it is the whole
    /// reason the mode is a choice rather than a default.
    case both
}

/// One entry in a `Toolbar` or `Ribbon`.
///
/// ```text
///   [ ▶ Run ] [ ■ Stop ] │ [ Config ▾ ]        ⇥        [ ⚙ ]
///   └── button ────────┘ │ └─ view ───┘  └ flexible ┘  └ icon ┘
///                    divider
/// ```
///
/// Five kinds, because a real toolbar is not a row of buttons — it is a row
/// of buttons with a search field in it, a separator or two, and something
/// pinned to the right-hand end.
/// A toolbar is **always across the top of a window**. Hand it over with
/// `window.setToolbar(_:)` and the window places it, sizes it, and shrinks
/// the document and the slide-outs to fit around it. For the same bar
/// somewhere else — inside a pane, above a list, split into named groups —
/// use a ``Ribbon``, which is a view you position yourself.
///
@MainActor
public final class ToolbarItem {
    /// What this entry is.
    public enum Kind {
        /// A command: an icon and/or a title, or any control standing in for
        /// one.
        case button(ToolbarIcon?)

        /// A hosted control — a pop-up, a search field, a segmented picker.
        ///
        /// The toolbar gives it its natural width and otherwise leaves it
        /// alone; it keeps its own focus, keys and mouse handling.
        case view(TUIView)

        /// A `│` rule between groups.
        case divider

        /// A fixed gap.
        case space(Int)

        /// A gap that absorbs leftover width, split evenly with every other
        /// flexible space.
        ///
        /// This is how something gets pinned to the right-hand end: put one
        /// before it. With none, leftover width simply goes unused at the
        /// end, which is the old behaviour and still the default.
        case flexibleSpace
    }

    /// What this entry is.
    public let kind: Kind

    /// The bar this item belongs to, so a change to the item repaints it.
    ///
    /// Without it, `item.isEnabled = false` left the bar showing the old
    /// state until something else happened to force a repaint — which worked
    /// for whoever held the toolbar and called `setNeedsDisplay` themselves,
    /// and silently did not for anyone holding only the item.
    weak var owner: Toolbar?

    /// Text shown for a button. Empty for an icon-only button, and unused by
    /// the other kinds.
    public var title: String {
        didSet {
            if title != oldValue {
                owner?.itemChanged(resized: true)
            }
        }
    }

    /// Disabled items render dim and cannot be activated.
    public var isEnabled: Bool {
        didSet {
            if isEnabled != oldValue {
                owner?.itemChanged(resized: false)
            }
        }
    }

    /// Hidden items take no width and cannot be reached.
    ///
    /// Different from disabled on purpose. Disabled says *"this command
    /// exists but not right now"* — Stop while nothing is running — and
    /// keeping it in place means the buttons around it do not shuffle
    /// sideways the moment a build starts. Hidden says *"this command does
    /// not apply to this window at all"* — a git button in a folder that is
    /// not a repository — and there a permanently dim button is just clutter.
    public var isVisible = true {
        didSet {
            if isVisible != oldValue {
                owner?.itemChanged(resized: true)
            }
        }
    }

    /// Called when a button activates.
    ///
    /// Settable after the fact, so a toolbar can be built once and rewired as
    /// the thing it acts on changes.
    public var action: () -> Void

    /// Creates an item.
    ///
    /// - Parameters:
    ///   - kind: What the entry is.
    ///   - title: Text for a button.
    ///   - isEnabled: Whether it can be activated.
    ///   - isVisible: Whether it appears at all.
    ///   - action: Called on activation.
    public init(
        kind: Kind,
        title: String = "",
        isEnabled: Bool = true,
        isVisible: Bool = true,
        action: @escaping () -> Void = {}
    ) {
        self.kind = kind
        self.title = title
        self.isEnabled = isEnabled
        self.isVisible = isVisible
        self.action = action
    }

    /// Creates a command button.
    ///
    /// - Parameters:
    ///   - title: Text shown for the item.
    ///   - icon: Optional icon drawn before the title.
    ///   - isEnabled: Whether the item can be activated.
    ///   - isVisible: Whether the item appears at all.
    ///   - action: Called when the item activates.
    public convenience init(
        _ title: String,
        icon: ToolbarIcon? = nil,
        isEnabled: Bool = true,
        isVisible: Bool = true,
        action: @escaping () -> Void = {}
    ) {
        self.init(
            kind: .button(icon),
            title: title,
            isEnabled: isEnabled,
            isVisible: isVisible,
            action: action
        )
    }

    /// A divider.
    public static func divider() -> ToolbarItem {
        ToolbarItem(kind: .divider)
    }

    /// A fixed gap.
    ///
    /// - Parameter width: Cells. Defaults to two — enough to read as a gap
    ///   without reading as a missing item.
    public static func space(_ width: Int = 2) -> ToolbarItem {
        ToolbarItem(kind: .space(max(0, width)))
    }

    /// A gap that shares out the leftover width.
    public static func flexibleSpace() -> ToolbarItem {
        ToolbarItem(kind: .flexibleSpace)
    }

    /// A hosted control.
    ///
    /// - Parameters:
    ///   - view: The control.
    ///   - title: A name, for the overflow menu and for tests.
    public static func view(_ view: TUIView, title: String = "") -> ToolbarItem {
        ToolbarItem(kind: .view(view), title: title)
    }

    /// Whether this entry can take focus or be clicked.
    ///
    /// Dividers and spaces cannot: they are punctuation, and stepping the
    /// keyboard focus onto punctuation is how a toolbar feels broken.
    public var isInteractive: Bool {
        guard isVisible else {
            return false
        }

        switch kind {
        case .button:
            return isEnabled

        case .view:
            return true

        case .divider, .space, .flexibleSpace:
            return false
        }
    }

    /// The icon a button carries, when any.
    public var icon: ToolbarIcon? {
        if case .button(let icon) = kind {
            return icon
        }

        return nil
    }

    // Text drawn inside a button's segment.
    var label: String {
        switch (icon?.glyph, title.isEmpty) {
        case (let glyph?, false):
            return "\(glyph) \(title)"

        case (let glyph?, true):
            return String(glyph)

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

    /// Whether buttons show glyphs, titles, or both stacked.
    ///
    /// Defaults to ``ToolbarDisplayMode/textOnly`` — one row. In a terminal a
    /// row is not free, and a bar that silently doubled its height the moment
    /// someone set an icon would be a surprise; `.both` is worth asking for.
    public var displayMode: ToolbarDisplayMode = .textOnly {
        didSet {
            if displayMode != oldValue {
                superview?.setNeedsLayout()
                setNeedsLayout()
                setNeedsDisplay()
            }
        }
    }

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
    ///   - isVisible: Whether the item appears at all.
    ///   - action: Called when the item activates.
    /// - Returns: The created item.
    @discardableResult
    public func addItem(
        _ title: String,
        icon: ToolbarIcon? = nil,
        isEnabled: Bool = true,
        action: @escaping () -> Void = {}
    ) -> ToolbarItem {
        add(ToolbarItem(title, icon: icon, isEnabled: isEnabled, action: action))
    }

    /// Appends a command with a plain glyph icon — the common case.
    @discardableResult
    public func addItem(
        _ title: String,
        glyph: Character,
        isEnabled: Bool = true,
        action: @escaping () -> Void = {}
    ) -> ToolbarItem {
        add(ToolbarItem(title, icon: ToolbarIcon(glyph: glyph), isEnabled: isEnabled, action: action))
    }

    /// Appends any item — a divider, a space, a hosted control.
    ///
    /// ```swift
    /// bar.addItem("Run", glyph: "▶") { session.run() }
    /// bar.add(.divider())
    /// bar.add(.view(searchField, title: "Search"))
    /// bar.add(.flexibleSpace())
    /// bar.addItem("Settings", glyph: "⚙") { showSettings() }
    /// ```
    @discardableResult
    public func add(_ item: ToolbarItem) -> ToolbarItem {
        insert(item, at: items.count)
    }

    /// Inserts an item at a position.
    ///
    /// With `remove(at:)` and `move(from:to:)` this is the whole of what a
    /// customisable toolbar needs: adding, removing and reordering ARE
    /// customisation. A bar that could only be built once left
    /// `insertItem(withItemIdentifier:at:)`, `removeItem(at:)` and
    /// `allowsUserCustomization` unimplementable by anything sitting on top
    /// of it.
    ///
    /// - Parameters:
    ///   - item: The item.
    ///   - index: Where it goes; clamped to the ends.
    /// - Returns: The item, for chaining.
    @discardableResult
    public func insert(_ item: ToolbarItem, at index: Int) -> ToolbarItem {
        item.owner = self
        items.insert(item, at: min(max(0, index), items.count))

        // A hosted control is a real subview: it draws itself, takes its own
        // focus, and handles its own mouse. The toolbar only places it.
        if case .view(let view) = item.kind {
            addSubview(view)
        }

        itemsChanged()
        return item
    }

    /// Removes the item at a position.
    ///
    /// - Parameter index: Which one. Out of range is a no-op, not a crash: a
    ///   customisation palette works from a list that may be one edit behind.
    /// - Returns: The removed item, or nil.
    @discardableResult
    public func remove(at index: Int) -> ToolbarItem? {
        guard items.indices.contains(index) else {
            return nil
        }

        let item = items.remove(at: index)
        item.owner = nil

        // A hosted control belongs to the bar only while the bar holds it;
        // left as a subview it would keep drawing where nothing places it.
        if case .view(let view) = item.kind {
            view.removeFromSuperview()
        }

        if focusedSlot >= items.count {
            focusedSlot = max(0, items.count - 1)
        }

        itemsChanged()
        return item
    }

    /// Removes every item.
    public func removeAllItems() {
        while !items.isEmpty {
            _ = remove(at: items.count - 1)
        }
    }

    /// Moves an item, which is the third of the three things customising a
    /// toolbar means.
    ///
    /// - Parameters:
    ///   - source: Where it is.
    ///   - destination: Where it should go, in the list AFTER the removal —
    ///     the same convention as `Array.move`.
    public func move(from source: Int, to destination: Int) {
        guard items.indices.contains(source) else {
            return
        }

        let item = items.remove(at: source)
        items.insert(item, at: min(max(0, destination), items.count))
        itemsChanged()
    }

    /// The item at a position, or nil.
    ///
    /// - Parameter index: Which one.
    public func item(at index: Int) -> ToolbarItem? {
        items.indices.contains(index) ? items[index] : nil
    }

    // One item changed in place: repaint, and re-measure when its width could
    // have moved (a title, or an item appearing).
    func itemChanged(resized: Bool) {
        if resized {
            superview?.setNeedsLayout()
            setNeedsLayout()
        }

        setNeedsDisplay()
    }

    private func itemsChanged() {
        superview?.setNeedsLayout()
        setNeedsLayout()
        setNeedsDisplay()
    }

    /// Toolbars take keyboard focus when they have any item.
    public override var acceptsFirstResponder: Bool {
        !items.isEmpty
    }

    /// Wide enough for every item, and as tall as the mode needs.
    public override var intrinsicContentSize: Size? {
        Size(width: naturalWidth, height: rowCount)
    }

    /// Overrides the bar's resting colours.
    ///
    /// A toolbar defaults to the theme's header style, which inside a window
    /// is the window's TITLE colour — and a bar wearing the title bar's paint
    /// reads as part of the frame rather than as a strip of commands. Setting
    /// this lets a host dress the bar as chrome instead: in OmegaCLIDE's Turbo
    /// themes it takes the menu bar's grey, so menu strip, toolbar and status
    /// strip are visibly one family and the document is the only blue.
    ///
    /// Disabled items keep their dimmed foreground but borrow this
    /// background, so a greyed-out Save still sits ON the bar.
    public var chromeStyle: CellStyle? {
        didSet {
            setNeedsDisplay()
        }
    }

    /// Overrides the colour of items that cannot be used.
    ///
    /// The theme's placeholder style is the default and is right inside a
    /// document, where it means "nothing here yet". On a command bar it has
    /// to mean "this command exists but not now", and a host that has already
    /// dressed the bar (see ``chromeStyle``) is the only thing that knows
    /// which grey reads as off against it.
    public var disabledStyle: CellStyle? {
        didSet {
            setNeedsDisplay()
        }
    }

    /// Rows the bar needs.
    ///
    /// One, except in `.both` — where the label sits on its own row under the
    /// glyph — or when a hosted control asks for more. A search field that
    /// wants two rows gets two rows and the buttons live alongside; the bar
    /// never hands a control less height than it asked for.
    public var rowCount: Int {
        let controlRows = items.compactMap { item -> Int? in
            guard case .view(let view) = item.kind, item.isVisible else {
                return nil
            }

            return view.intrinsicContentSize?.height
        }.max() ?? 1

        switch displayMode {
        case .iconOnly, .textOnly:
            return max(1, controlRows)

        case .both:
            return max(2, controlRows + 1)
        }
    }

    // The row a button's glyph sits on, and the row its label sits on.
    private var glyphRow: Int { 0 }
    private var labelRow: Int { 1 }

    /// Places hosted control subviews into their segments.
    ///
    /// Hidden when they overflow: a control the plan says is not visible must
    /// not keep drawing where the plan no longer reserves room for it.
    public override func layoutSubviews() {
        let plan = layout()

        for (index, item) in items.enumerated() {
            guard case .view(let view) = item.kind else {
                continue
            }

            if index < plan.visibleCount, item.isVisible {
                let segment = plan.segments[index]
                view.isHidden = false
                view.frame = Rect(x: segment.x, y: 0, width: segment.width, height: max(1, bounds.size.height))
            } else {
                view.isHidden = true
            }
        }
    }

    // A VTG terminal draws the icon's picture over the glyph cell; every
    // other terminal keeps the glyph, which is why the glyph is required.
    private func drawIconImage(_ item: ToolbarItem, at segment: (x: Int, width: Int), painter: Painter) {
        guard let chrome = painter.chrome,
              let icon = item.icon,
              let data = icon.imageData else {
            return
        }

        chrome.image(
            "icon\(segment.x)",
            ChromeRect(
                x: Double(segment.x + style.horizontalPadding / 2),
                y: 0,
                width: 1,
                height: 1
            ),
            data: data,
            format: icon.imageFormat,
            layer: .overlay
        )
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
        painter.fill(bounds, with: TerminalCell(character: " ", style: barStyle(theme)))

        let plan = layout()

        for slot in 0..<plan.visibleCount {
            let segment = plan.segments[slot]
            let item = items[slot]

            guard item.isVisible else {
                continue
            }

            switch item.kind {
            case .button:
                let style = slotStyle(forSlot: slot, item: item, theme: theme)

                switch displayMode {
                case .iconOnly, .textOnly:
                    drawSegment(
                        buttonLabel(item),
                        at: segment.x,
                        row: glyphRow,
                        width: segment.width,
                        style: style,
                        painter: painter
                    )

                case .both:
                    // Glyph over label. Both rows carry the segment style, so
                    // focus and disabled read as one button rather than two
                    // half-highlighted lines.
                    drawSegment(
                        item.icon.map { String($0.glyph) } ?? "",
                        at: segment.x,
                        row: glyphRow,
                        width: segment.width,
                        style: style,
                        painter: painter
                    )
                    drawSegment(
                        item.title,
                        at: segment.x,
                        row: labelRow,
                        width: segment.width,
                        style: style,
                        painter: painter
                    )
                }

                drawIconImage(item, at: segment, painter: painter)

            case .divider:
                // In the border slot, not the header's, so it reads as a rule
                // rather than as dimmed text — and down every row, so it
                // separates a two-row bar as well as a one-row one.
                for row in 0..<max(1, bounds.size.height) {
                    painter.set(
                        TerminalCell(character: "│", style: theme.border),
                        at: Point(x: segment.x + segment.width / 2, y: row)
                    )
                }

            case .space, .flexibleSpace:
                break   // the fill already painted them

            case .view:
                break   // it is a subview and draws itself
            }
        }

        if plan.hasOverflow, let overflowX = plan.overflowX {
            drawSegment(
                "»",
                at: overflowX,
                row: glyphRow,
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
        guard mouse.action == .press, mouse.button == .left,
              mouse.position.y >= 0, mouse.position.y < max(1, bounds.size.height) else {
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

        guard items.indices.contains(slot), items[slot].isInteractive else {
            return
        }

        // A hosted control is not a command: activating its slot hands it the
        // keyboard instead of firing an action it does not have.
        if case .view(let view) = items[slot].kind {
            owningWindow?.makeFirstResponder(view)
            return
        }

        items[slot].action()
    }

    private func openOverflowMenu(plan: Layout) {
        guard plan.hasOverflow, let window = owningWindow else {
            return
        }

        let menu = Menu("")

        // Commands only: a divider or a gap has nothing to offer a menu, and
        // a hosted control cannot live in one.
        for item in items[plan.visibleCount...] {
            guard item.isVisible, case .button = item.kind else {
                continue
            }

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

        return items.indices.contains(slot) && items[slot].isInteractive
    }

    private func firstFocusableSlot(in plan: Layout) -> Int? {
        (0..<plan.slotCount).first { isFocusable(slot: $0, in: plan) }
    }

    private func lastFocusableSlot(in plan: Layout) -> Int? {
        (0..<plan.slotCount).last { isFocusable(slot: $0, in: plan) }
    }

    // MARK: - Drawing helpers

    // The bar's own paint: whatever the host asked for, else the theme's.
    private func barStyle(_ theme: ResolvedTheme) -> CellStyle {
        chromeStyle ?? theme.header
    }

    private func slotStyle(forSlot slot: Int, item: ToolbarItem?, theme: ResolvedTheme) -> CellStyle {
        if let item, !item.isEnabled {
            var dimmed = disabledStyle ?? theme.placeholder
            dimmed.background = barStyle(theme).background
            return dimmed
        }

        if isFirstResponder, slot == focusedSlot {
            return theme.selection
        }

        // A host that named the bar's colours has already said what the
        // resting items should look like; tinting over it would overrule it.
        guard chromeStyle == nil else {
            return barStyle(theme)
        }

        // Resting: the bar's slot, tinted with the accent (or underlined on
        // a colorless theme) when the tinted style is active.
        var resting = barStyle(theme)

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

    private func drawSegment(
        _ label: String,
        at x: Int,
        row: Int,
        width: Int,
        style cellStyle: CellStyle,
        painter: Painter
    ) {
        let pad = style.horizontalPadding
        let inner = Label.truncated(label, width: max(0, width - pad))
        let content = inner + String(repeating: " ", count: max(0, width - pad - inner.count))
        painter.write(style.decorate(content), at: Point(x: x, y: row), style: cellStyle)
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

    // Segment width for one item. Flexible space measures zero here and is
    // grown afterwards, out of whatever the fixed items left.
    private func segmentWidth(_ item: ToolbarItem) -> Int {
        guard item.isVisible else {
            return 0
        }

        switch item.kind {
        case .button:
            return buttonLabel(item).count + style.horizontalPadding

        case .view(let view):
            return max(1, view.intrinsicContentSize?.width ?? 8)

        case .divider:
            return 3      // " │ "

        case .space(let width):
            return width

        case .flexibleSpace:
            return 0
        }
    }

    // What a button's widest row shows, which is what it must be sized for.
    private func buttonLabel(_ item: ToolbarItem) -> String {
        switch displayMode {
        case .iconOnly:
            return item.icon.map { String($0.glyph) } ?? item.title

        case .textOnly:
            return item.title.isEmpty ? (item.icon.map { String($0.glyph) } ?? "") : item.title

        case .both:
            // The wider of the two stacked rows.
            let glyph = item.icon.map { String($0.glyph) } ?? ""
            return glyph.count > item.title.count ? glyph : item.title
        }
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

        var width = 0
        var placed = false

        for item in items {
            width += (placed ? separatorWidth(before: item) : 0) + segmentWidth(item)
            placed = placed || item.isVisible
        }

        return width
    }

    // Greedy left-to-right fit; trailing items overflow into a `»` menu.
    //
    // Two passes, because flexible space can only be sized once the fixed
    // items are known: measure and place everything at its natural width,
    // then hand the leftover to the flexible spaces and shift what follows.
    private func layout() -> Layout {
        let width = bounds.size.width

        guard !items.isEmpty else {
            return Layout(visibleCount: 0, hasOverflow: false, segments: [], overflowX: nil)
        }

        let fits = naturalWidth <= width
        let overflowReserve = fits ? 0 : overflowWidth + 1

        var segments: [(x: Int, width: Int)] = []
        var x = 0
        var visible = 0
        var placed = false   // NOT `visible > 0`: a hidden item occupies a slot

        for item in items {
            let separator = placed ? separatorWidth(before: item) : 0
            let itemWidth = segmentWidth(item)

            guard fits || x + separator + itemWidth + overflowReserve <= width else {
                break
            }

            x += separator
            segments.append((x: x, width: itemWidth))
            x += itemWidth
            visible += 1
            placed = placed || item.isVisible
        }

        if fits {
            distributeFlexibleSpace(in: &segments, visibleCount: visible, within: width)
            return Layout(visibleCount: visible, hasOverflow: false, segments: segments, overflowX: nil)
        }

        let overflowX = visible == 0 ? 0 : x + 1
        return Layout(visibleCount: visible, hasOverflow: true, segments: segments, overflowX: overflowX)
    }

    // Splits the unused width evenly among the flexible spaces, giving the
    // remainder to the earliest — the same rule `StackView` uses, so a
    // toolbar and a stack put a stray cell in the same place.
    //
    // Only when everything fits: an overflowing toolbar has no leftover to
    // share, and growing a gap while items are being hidden behind a `»`
    // would be actively perverse.
    private func distributeFlexibleSpace(in segments: inout [(x: Int, width: Int)], visibleCount: Int, within width: Int) {
        let flexible = (0..<visibleCount).filter {
            if case .flexibleSpace = items[$0].kind { return true } else { return false }
        }

        guard !flexible.isEmpty, let last = segments.last else {
            return
        }

        let used = last.x + last.width
        let leftover = width - used

        guard leftover > 0 else {
            return
        }

        let each = leftover / flexible.count
        var remainder = leftover % flexible.count
        var shift = 0

        for index in 0..<visibleCount {
            segments[index].x += shift

            if flexible.contains(index) {
                let extra = each + (remainder > 0 ? 1 : 0)
                remainder -= remainder > 0 ? 1 : 0
                segments[index].width += extra
                shift += extra
            }
        }
    }

    // A space of its own needs no separator before it, and neither does the
    // item after one — punctuation should not be padded like a button.
    private func separatorWidth(before item: ToolbarItem) -> Int {
        guard item.isVisible else {
            return 0
        }

        switch item.kind {
        case .space, .flexibleSpace, .divider:
            return 0

        case .button, .view:
            return 1
        }
    }

    /// The horizontal span a range of items occupies, or nil when none of
    /// them are visible.
    ///
    /// `Ribbon` uses it to centre a caption under the group it names, and it
    /// has to come from the toolbar because the toolbar owns the layout — a
    /// ribbon computing its own would be a second implementation of the
    /// arithmetic that the flexible-space pass just made non-obvious.
    public func span(ofItems range: Range<Int>) -> (x: Int, width: Int)? {
        let plan = layout()
        let visible = range.clamped(to: 0..<plan.visibleCount)

        guard !visible.isEmpty else {
            return nil
        }

        let first = plan.segments[visible.lowerBound]
        let last = plan.segments[visible.upperBound - 1]
        return (x: first.x, width: last.x + last.width - first.x)
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
