/// Value chooser: shows the selection, pops a menu to change it.
///
/// ```text
///   [ Balanced ▾ ]        closed — shows the selected value
///
///   [ Balanced ▾ ]        pressed — the menu pops *below*, or above
///   ┌──────────┐          when there is more room there
///   │ Fast     │
///   │▸Balanced │
///   │ Accurate │
///   └──────────┘
/// ```
///
/// Space/Return/`↓` (or a click) opens; in the popup `↑`/`↓` move,
/// Return/click choose, and Esc — or focusing anything else — cancels.
/// Placement is automatic: below the button when it fits, above when the
/// space below is too tight.
///
/// ```swift
/// let mode = PopUpButton(items: ["Fast", "Balanced", "Accurate"], selectedIndex: 1)
/// mode.onSelectionChanged = { index in engine.mode = index }
/// ```
@MainActor
public final class PopUpButton: TUIView {
    /// Choices shown in the popup.
    public var items: [String] {
        didSet {
            if let selected = selectedIndex, selected >= items.count {
                selectedIndex = items.isEmpty ? nil : items.count - 1
            }

            superview?.setNeedsLayout()
            setNeedsDisplay()
        }
    }

    /// Index of the chosen item, when any.
    public private(set) var selectedIndex: Int?

    /// How the button signals it is actionable: accent color (`.tinted`,
    /// the default) or bracketed (`.bordered`).
    public var style: ControlStyle = .tinted {
        didSet {
            if style != oldValue {
                superview?.setNeedsLayout()
                setNeedsDisplay()
            }
        }
    }

    /// Called when the chosen item changes.
    public var onSelectionChanged: (Int) -> Void = { _ in }

    /// Whether the popup is open.
    public var isOpen: Bool {
        popup != nil
    }

    // Open popup, when any.
    private var popup: PopUpList?

    /// Creates a pop-up button.
    ///
    /// - Parameters:
    ///   - items: Choices shown in the popup.
    ///   - selectedIndex: Initially chosen item.
    public init(items: [String] = [], selectedIndex: Int? = nil) {
        self.items = items

        if let selectedIndex, items.indices.contains(selectedIndex) {
            self.selectedIndex = selectedIndex
        }

        super.init(frame: .zero)
    }

    /// Pop-up buttons take keyboard focus.
    public override var acceptsFirstResponder: Bool {
        true
    }

    /// One row wide enough for the longest item plus the `▾` and decoration.
    public override var intrinsicContentSize: Size? {
        let widest = items.map(\.count).max() ?? 0
        return Size(width: widest + style.horizontalPadding + 2, height: 1)   // + " ▾"
    }

    /// Selects an item programmatically.
    ///
    /// - Parameters:
    ///   - index: Item to choose, or `nil` to clear.
    ///   - notify: Whether `onSelectionChanged` fires. Defaults to silent.
    public func select(_ index: Int?, notify: Bool = false) {
        let clamped = index.flatMap { items.indices.contains($0) ? $0 : nil }

        guard clamped != selectedIndex else {
            return
        }

        selectedIndex = clamped
        setNeedsDisplay()

        if notify, let clamped {
            onSelectionChanged(clamped)
        }
    }

    /// Draws the selected value and `▾`, accent-tinted (or bracketed) at rest
    /// and in the selection style while focused or open.
    public override func draw(_ painter: Painter) {
        let theme = effectiveTheme
        var cellStyle: CellStyle

        if isOpen {
            cellStyle = theme.selection
            cellStyle.flags.insert(.bold)
        } else if isFirstResponder {
            cellStyle = theme.selection
        } else {
            cellStyle = style.restingStyle(theme: theme)
        }

        let (lead, trail) = style == .bordered ? ("[ ", " ▾ ]") : (" ", " ▾ ")
        let reserved = lead.count + trail.count
        let value = selectedIndex.map { items[$0] } ?? ""
        let inner = Label.truncated(value, width: max(0, bounds.size.width - reserved))
        let padding = max(0, bounds.size.width - reserved - inner.count)
        let text = lead + inner + String(repeating: " ", count: padding) + trail
        painter.write(text, at: .zero, style: cellStyle)
    }

    /// Space/Return/Down opens the popup.
    public override func keyDown(_ key: KeyInput) -> Bool {
        guard key.modifiers.isEmpty else {
            return false
        }

        switch key.key {
        case .enter, .character(" "), .down:
            openPopup()
            return true

        default:
            return false
        }
    }

    /// Click toggles the popup.
    public override func mouseEvent(_ mouse: MouseInput) -> Bool {
        guard mouse.action == .press, mouse.button == .left else {
            return false
        }

        if isOpen {
            closePopup()
        } else {
            openPopup()
        }

        return true
    }

    // MARK: - Popup management

    /// Opens the popup (above or below, by available space).
    public func openPopup() {
        guard popup == nil, !items.isEmpty,
              let list = PopUpList.present(
                  items: items,
                  highlightedIndex: selectedIndex ?? 0,
                  anchor: self
              ) else {
            return
        }

        list.onChoose = { [weak self] index in
            self?.closePopup()
            self?.select(index, notify: true)
        }

        list.onDismiss = { [weak self] in
            self?.closePopup()
        }

        popup = list
        setNeedsDisplay()
    }

    /// Closes the popup, returning focus to the button when the popup
    /// still held it (keyboard paths). When the popup is closing because
    /// something else took focus (an outside click), that focus stands.
    public func closePopup() {
        guard let popup else {
            return
        }

        let window = owningWindow
        let popupHadFocus = window?.firstResponder === popup

        self.popup = nil
        popup.removeFromSuperview()

        if popupHadFocus {
            window?.makeFirstResponder(self)
        }

        setNeedsDisplay()
    }

    // Nearest ancestor window.
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

/// Bordered choice list used by pop-up buttons and combo boxes
/// (framework-internal). Dismisses itself when it loses focus, so a click
/// anywhere else closes the popup.
@MainActor
final class PopUpList: TUIView {
    var onChoose: (Int) -> Void = { _ in }
    var onDismiss: () -> Void = {}

    /// Creates, places, and focuses a list attached to an anchor view's
    /// window — below the anchor when it fits, above when tighter. Wire
    /// `onChoose`/`onDismiss` on the returned list.
    static func present(items: [String], highlightedIndex: Int, anchor: TUIView) -> PopUpList? {
        var window: Window?
        var origin = Point.zero
        var current: TUIView? = anchor

        while let view = current {
            if let found = view as? Window {
                window = found
                break
            }

            origin = origin + view.frame.origin
            current = view.superview
        }

        guard let window else {
            return nil
        }

        let list = PopUpList(items: items, highlightedIndex: highlightedIndex)
        let size = list.intrinsicContentSize ?? Size(width: 10, height: 4)
        let spaceBelow = window.bounds.size.height - (origin.y + 1)

        let y = spaceBelow >= size.height || origin.y < size.height
            ? origin.y + 1              // below (also when neither fits)
            : origin.y - size.height    // above

        list.frame = Rect(
            origin: Point(
                x: max(0, min(origin.x, window.bounds.size.width - size.width)),
                y: max(0, y)
            ),
            size: size
        )

        window.addSubview(list)
        window.makeFirstResponder(list)
        return list
    }

    private let items: [String]
    private var highlightedIndex: Int
    private var isDismissed = false

    init(items: [String], highlightedIndex: Int) {
        self.items = items
        self.highlightedIndex = min(max(0, highlightedIndex), max(0, items.count - 1))
        super.init(frame: .zero)
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override var intrinsicContentSize: Size? {
        let widest = items.map(\.count).max() ?? 4
        return Size(width: widest + 4, height: items.count + 2)
    }

    /// The open list is a transient overlay: an outside press dismisses it.
    override var dismissesOnOutsidePress: Bool {
        true
    }

    override func didResignFirstResponder() {
        dismiss()
    }

    override func draw(_ painter: Painter) {
        let theme = effectiveTheme

        painter.fill(bounds, with: .blank)
        painter.drawBox(bounds, style: theme.border, border: theme.borderStyle)

        let innerWidth = max(0, bounds.size.width - 4)

        for (index, item) in items.enumerated() {
            let marker = index == highlightedIndex ? "▸" : " "
            let text = Label.truncated(item, width: innerWidth)
            let padded = marker + text + String(repeating: " ", count: max(0, innerWidth - text.count)) + " "
            let style = index == highlightedIndex ? theme.selection : CellStyle()

            painter.write(padded, at: Point(x: 1, y: index + 1), style: style)
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

        case .home:
            moveHighlight(to: 0)
            return true

        case .end:
            moveHighlight(to: items.count - 1)
            return true

        case .enter:
            choose(highlightedIndex)
            return true

        case .escape:
            dismiss()
            return true

        default:
            return false
        }
    }

    override func mouseEvent(_ mouse: MouseInput) -> Bool {
        switch mouse.action {
        case .press where mouse.button == .left:
            choose(mouse.position.y - 1)
            return true

        case .scrollUp:
            moveHighlight(by: -1)
            return true

        case .scrollDown:
            moveHighlight(by: 1)
            return true

        default:
            return false
        }
    }

    // MARK: - Internals

    private func choose(_ index: Int) {
        guard items.indices.contains(index), !isDismissed else {
            return
        }

        isDismissed = true
        onChoose(index)
    }

    private func dismiss() {
        guard !isDismissed else {
            return
        }

        isDismissed = true
        onDismiss()
    }

    private func moveHighlight(by offset: Int) {
        moveHighlight(to: highlightedIndex + offset)
    }

    private func moveHighlight(to index: Int) {
        let clamped = min(max(0, index), max(0, items.count - 1))

        if clamped != highlightedIndex {
            highlightedIndex = clamped
            setNeedsDisplay()
        }
    }
}
