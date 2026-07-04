/// One entry in a `Menu`: a title, an optional hot key, and an action.
@MainActor
public final class MenuItem {
    /// Text shown for the item.
    public var title: String

    /// Key that activates the item from anywhere (via the hot-key pass).
    public var keyEquivalent: KeyInput?

    /// Disabled items render dim and cannot be activated.
    public var isEnabled = true

    /// Whether the item is a separator line.
    public let isSeparator: Bool

    /// Called when the item activates.
    public var action: () -> Void

    /// Creates an item.
    ///
    /// - Parameters:
    ///   - title: Text shown for the item.
    ///   - keyEquivalent: Key that activates it from anywhere.
    ///   - action: Called when the item activates.
    public init(_ title: String, keyEquivalent: KeyInput? = nil, action: @escaping () -> Void = {}) {
        self.title = title
        self.keyEquivalent = keyEquivalent
        self.isSeparator = false
        self.action = action
    }

    private init(separator: Bool) {
        self.title = ""
        self.isSeparator = separator
        self.action = {}
    }

    /// Creates a separator line.
    public static func separator() -> MenuItem {
        MenuItem(separator: true)
    }
}

/// A titled list of `MenuItem`s owned by a `MenuBar`.
@MainActor
public final class Menu {
    /// Title shown in the menu bar.
    public var title: String

    /// Items in display order.
    public private(set) var items: [MenuItem] = []

    /// Creates a menu.
    ///
    /// - Parameter title: Title shown in the menu bar.
    public init(_ title: String) {
        self.title = title
    }

    /// Appends an item.
    ///
    /// - Parameters:
    ///   - title: Item text.
    ///   - keyEquivalent: Key that activates it from anywhere.
    ///   - action: Called when the item activates.
    /// - Returns: The created item.
    @discardableResult
    public func addItem(
        _ title: String,
        keyEquivalent: KeyInput? = nil,
        action: @escaping () -> Void = {}
    ) -> MenuItem {
        let item = MenuItem(title, keyEquivalent: keyEquivalent, action: action)
        items.append(item)
        return item
    }

    /// Appends a separator line.
    public func addSeparator() {
        items.append(.separator())
    }
}

/// Horizontal menu bar with dropdown menus.
///
/// ```text
///    File  Edit  TUIView          ← the bar (one row)
///   ┌────────────┐
///   │ Open    ^O │             ← dropdown while a menu is open
///   │ Save    ^S │
///   │ ────────── │
///   │ Quit    ^Q │
///   └────────────┘
/// ```
///
/// Interaction: focus the bar and use `←`/`→` to highlight a menu,
/// Return/`↓` to open it; inside a dropdown `↑`/`↓` move (skipping
/// separators and disabled items), `←`/`→` slide to the neighboring menu,
/// Return activates, Esc closes. Clicking a title toggles its menu and
/// clicking an item activates it. Item `keyEquivalent`s fire from anywhere
/// in the window through the hot-key pass — the menu need not be open.
///
/// Place the bar directly in a window (typically anchored to the top row);
/// the dropdown is attached to the bar's superview, so a deeply nested bar
/// would have its dropdown clipped by that container.
@MainActor
public final class MenuBar: TUIView {
    /// Menus in bar order.
    public private(set) var menus: [Menu] = []

    /// Whether a dropdown is currently open.
    public var isMenuOpen: Bool {
        dropdown != nil
    }

    // Highlighted bar title.
    private var selectedMenuIndex = 0

    // Whether the bar is in active menu navigation. A freshly focused bar
    // (Tab, or a programmatic focus at launch) is idle: no title highlights
    // until the user engages it with an arrow, Return/Down, or a click. The
    // first navigation key enters this mode; losing focus or Esc leaves it.
    private var isActive = false

    // Open dropdown, when any.
    private var dropdown: MenuDropdown?

    /// Creates an empty menu bar.
    public init() {
        super.init(frame: .zero)
    }

    /// Appends a menu.
    ///
    /// - Parameter menu: Menu to append.
    public func addMenu(_ menu: Menu) {
        menus.append(menu)
        superview?.setNeedsLayout()
        setNeedsDisplay()
    }

    /// One row at the width of all titles.
    public override var intrinsicContentSize: Size? {
        Size(width: menus.reduce(0) { $0 + $1.title.count + 2 }, height: 1)
    }

    /// Menu bars take keyboard focus.
    public override var acceptsFirstResponder: Bool {
        true
    }

    /// Draws the bar in the theme's `header` (chrome) slot, then the titles;
    /// the highlighted one lights up while focused or open.
    public override func draw(_ painter: Painter) {
        let theme = effectiveTheme

        // The whole bar wears the header slot (e.g. the Borland gray menu bar),
        // so it reads as one strip of chrome rather than window content.
        painter.fill(bounds, with: TerminalCell(character: " ", style: theme.header))

        var x = 0

        for (index, menu) in menus.enumerated() {
            var style = theme.header

            if index == selectedMenuIndex, (isFirstResponder && isActive) || isMenuOpen {
                style = theme.selection

                if isMenuOpen {
                    style.flags.insert(.bold)
                }
            }

            painter.write(" \(menu.title) ", at: Point(x: x, y: 0), style: style)
            x += menu.title.count + 2
        }
    }

    /// `←`/`→` highlight, Return/`↓` open, Esc leaves menu navigation.
    ///
    /// The first navigation key on a freshly focused bar only enters menu
    /// mode (lighting up the current title); the next one moves.
    public override func keyDown(_ key: KeyInput) -> Bool {
        guard key.modifiers.isEmpty, !menus.isEmpty else {
            return false
        }

        switch key.key {
        case .left:
            if enterMenuModeIfNeeded() {
                return true
            }

            selectMenu(selectedMenuIndex - 1)
            return true

        case .right:
            if enterMenuModeIfNeeded() {
                return true
            }

            selectMenu(selectedMenuIndex + 1)
            return true

        case .enter, .down:
            isActive = true
            openMenu(at: selectedMenuIndex)
            return true

        case .escape where isActive:
            isActive = false
            setNeedsDisplay()
            return true

        default:
            return false
        }
    }

    /// Leaving focus ends menu navigation, so the bar goes idle.
    public override func didResignFirstResponder() {
        if isActive {
            isActive = false
            setNeedsDisplay()
        }
    }

    // Enters menu navigation on the first key; returns whether it just did
    // (so the caller stops rather than also moving the highlight).
    private func enterMenuModeIfNeeded() -> Bool {
        guard !isActive else {
            return false
        }

        isActive = true
        setNeedsDisplay()
        return true
    }

    /// Item key equivalents fire from anywhere in the window.
    public override func handleHotKey(_ key: KeyInput) -> Bool {
        for menu in menus {
            for item in menu.items where item.keyEquivalent == key {
                guard item.isEnabled, !item.isSeparator else {
                    continue
                }

                item.action()
                return true
            }
        }

        return false
    }

    /// Clicking a title toggles its menu.
    public override func mouseEvent(_ mouse: MouseInput) -> Bool {
        guard mouse.action == .press, mouse.button == .left else {
            return false
        }

        guard let index = menuIndex(at: mouse.position.x) else {
            return false
        }

        if isMenuOpen, index == selectedMenuIndex {
            closeMenu()
        } else {
            openMenu(at: index)
        }

        return true
    }

    // MARK: - Dropdown management

    /// Opens one menu's dropdown (closing any other).
    ///
    /// - Parameter index: Menu to open.
    public func openMenu(at index: Int) {
        guard menus.indices.contains(index), let superview else {
            return
        }

        closeMenu()
        selectedMenuIndex = index

        let view = MenuDropdown(menu: menus[index])

        view.onActivate = { [weak self] item in
            self?.isActive = false   // activating an item exits menu mode
            self?.closeMenu()
            item.action()
        }

        view.onClose = { [weak self] in
            self?.closeMenu()
        }

        view.onSwitchMenu = { [weak self] direction in
            guard let self else {
                return
            }

            let count = self.menus.count
            self.openMenu(at: ((self.selectedMenuIndex + direction) % count + count) % count)
        }

        let size = view.intrinsicContentSize ?? Size(width: 10, height: 4)
        view.frame = Rect(
            origin: frame.origin + Point(x: titleStart(of: index), y: 1),
            size: size
        )

        superview.addSubview(view)
        dropdown = view
        owningWindow?.makeFirstResponder(view)
        setNeedsDisplay()
    }

    /// Closes the open dropdown, returning focus to the bar when the
    /// dropdown still held it; an outside click's new focus stands.
    public func closeMenu() {
        guard let dropdown else {
            return
        }

        let window = owningWindow
        let dropdownHadFocus = window?.firstResponder === dropdown

        self.dropdown = nil
        dropdown.removeFromSuperview()

        if dropdownHadFocus {
            window?.makeFirstResponder(self)
        }

        setNeedsDisplay()
    }

    // Wraps and re-highlights (moving the open menu along when open).
    private func selectMenu(_ index: Int) {
        let count = menus.count
        let wrapped = ((index % count) + count) % count

        if isMenuOpen {
            openMenu(at: wrapped)
        } else {
            selectedMenuIndex = wrapped
            setNeedsDisplay()
        }
    }

    // Leading x of a title run.
    private func titleStart(of index: Int) -> Int {
        menus.prefix(index).reduce(0) { $0 + $1.title.count + 2 }
    }

    // Menu whose title run contains an x position.
    private func menuIndex(at x: Int) -> Int? {
        var start = 0

        for (index, menu) in menus.enumerated() {
            let width = menu.title.count + 2

            if x >= start && x < start + width {
                return index
            }

            start += width
        }

        return nil
    }

    // Nearest ancestor window (focus scope).
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
}

/// The open menu's dropdown list (framework-internal).
@MainActor
final class MenuDropdown: TUIView {
    var onActivate: (MenuItem) -> Void = { _ in }
    var onClose: () -> Void = {}
    var onSwitchMenu: (Int) -> Void = { _ in }

    private let menu: Menu
    private var highlightedIndex: Int

    init(menu: Menu) {
        self.menu = menu
        self.highlightedIndex = menu.items.firstIndex { $0.isEnabled && !$0.isSeparator } ?? 0
        super.init(frame: .zero)
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    /// Losing focus closes the menu — so a click anywhere else dismisses
    /// it without the click being lost.
    override func didResignFirstResponder() {
        onClose()
    }

    override var intrinsicContentSize: Size? {
        let widest = menu.items.map { $0.title.count + Self.hint(for: $0.keyEquivalent).count + 2 }.max() ?? 4
        return Size(width: widest + 4, height: menu.items.count + 2)
    }

    override func draw(_ painter: Painter) {
        let theme = effectiveTheme

        painter.fill(bounds, with: .blank)
        painter.drawBox(bounds, style: theme.border, border: theme.borderStyle)

        let innerWidth = max(0, bounds.size.width - 4)

        for (index, item) in menu.items.enumerated() {
            let y = index + 1

            if item.isSeparator {
                // A full-width interior line welded into both side borders with
                // tees (├───┤), so the separator connects to the menu frame.
                let line = theme.dividerStyle.characters?.horizontal ?? "─"
                painter.write(String(repeating: line, count: bounds.size.width), at: Point(x: 0, y: y), style: theme.border)

                if let left = theme.borderStyle.tee(.left, nub: theme.dividerStyle) {
                    painter.set(TerminalCell(character: left, style: theme.border), at: Point(x: 0, y: y))
                }
                if let right = theme.borderStyle.tee(.right, nub: theme.dividerStyle) {
                    painter.set(TerminalCell(character: right, style: theme.border), at: Point(x: bounds.size.width - 1, y: y))
                }
                continue
            }

            var style = CellStyle()

            if !item.isEnabled {
                style = theme.placeholder
            } else if index == highlightedIndex {
                style = theme.selection
            }

            let hint = Self.hint(for: item.keyEquivalent)
            let title = Label.truncated(item.title, width: max(0, innerWidth - hint.count))
            let padding = max(0, innerWidth - title.count - hint.count)
            let line = " " + title + String(repeating: " ", count: padding) + hint + " "

            painter.write(line, at: Point(x: 1, y: y), style: style)
        }
    }

    override func keyDown(_ key: KeyInput) -> Bool {
        guard key.modifiers.isEmpty else {
            return false
        }

        switch key.key {
        case .up:
            moveHighlight(by: -1)
            return true

        case .down:
            moveHighlight(by: 1)
            return true

        case .left:
            onSwitchMenu(-1)
            return true

        case .right:
            onSwitchMenu(1)
            return true

        case .enter:
            activate(at: highlightedIndex)
            return true

        case .escape:
            onClose()
            return true

        default:
            return false
        }
    }

    override func mouseEvent(_ mouse: MouseInput) -> Bool {
        guard mouse.action == .press, mouse.button == .left else {
            return false
        }

        activate(at: mouse.position.y - 1)
        return true
    }

    // MARK: - Internals

    private func activate(at index: Int) {
        guard menu.items.indices.contains(index) else {
            return
        }

        let item = menu.items[index]

        guard item.isEnabled, !item.isSeparator else {
            return
        }

        onActivate(item)
    }

    // Moves the highlight, skipping separators and disabled items.
    private func moveHighlight(by offset: Int) {
        let count = menu.items.count

        guard count > 0 else {
            return
        }

        var index = highlightedIndex

        for _ in 0..<count {
            index = ((index + offset) % count + count) % count
            let item = menu.items[index]

            if item.isEnabled, !item.isSeparator {
                highlightedIndex = index
                setNeedsDisplay()
                return
            }
        }
    }

    // Compact key-equivalent display: ^S, ⌥X, F5, ⇧Tab, plain characters.
    static func hint(for key: KeyInput?) -> String {
        guard let key else {
            return ""
        }

        var text = ""

        if key.modifiers.contains(.control) {
            text += "^"
        }

        if key.modifiers.contains(.alt) {
            text += "⌥"
        }

        if key.modifiers.contains(.shift) {
            text += "⇧"
        }

        switch key.key {
        case .character(let character):
            text += String(character).uppercased()

        case .function(let number):
            text += "F\(number)"

        case .enter:
            text += "↵"

        case .tab:
            text += "⇥"

        case .escape:
            text += "esc"

        default:
            text += ""
        }

        return text
    }
}
