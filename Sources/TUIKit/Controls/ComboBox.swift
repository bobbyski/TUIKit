/// Free text entry plus a pop-up of suggestions: TextField + `▾`.
///
/// ```text
///   Ocean_________________ ▾     type anything, or pop the list
/// ```
///
/// The field behaves exactly like `TextField` (its `onChanged`/`onSubmit`
/// pass through); the `▾` disclosure — or `↓` from the field — pops the
/// value list (below when it fits, above when tighter, same as
/// `PopUpButton`). Picking an item fills the field and fires both
/// `onSelectionChanged` and `onChanged`.
///
/// ```swift
/// let font = ComboBox(items: ["Menlo", "Monaco", "SF Mono"], placeholder: "font name")
/// font.onSelectionChanged = { index in apply(fonts[index]) }
/// font.onSubmit = { name in apply(named: name) }
/// ```
@MainActor
public final class ComboBox: TUIView {
    /// Choices shown in the popup.
    public var items: [String] {
        didSet {
            superview?.setNeedsLayout()
            setNeedsDisplay()
        }
    }

    /// Current field text.
    public var text: String {
        field.text
    }

    /// Called as the text changes (typing or picking).
    public var onChanged: (String) -> Void = { _ in }

    /// Called when Return submits the field.
    public var onSubmit: (String) -> Void = { _ in }

    /// Called when an item is picked from the popup.
    public var onSelectionChanged: (Int) -> Void = { _ in }

    /// Whether the popup is open.
    public var isOpen: Bool {
        popup != nil
    }

    // Editing half; the popup when open.
    private let field: TextField
    private var popup: PopUpList?

    /// Creates a combo box.
    ///
    /// - Parameters:
    ///   - text: Initial field text.
    ///   - items: Choices shown in the popup.
    ///   - placeholder: Dimmed text while the field is empty.
    public init(text: String = "", items: [String] = [], placeholder: String = "") {
        self.items = items
        self.field = TextField(text: text, placeholder: placeholder)
        super.init(frame: .zero)

        addSubview(field)

        field.onChanged = { [weak self] value in
            self?.onChanged(value)
        }

        field.onSubmit = { [weak self] value in
            self?.onSubmit(value)
        }
    }

    /// Replaces the field text (silent).
    ///
    /// - Parameter newText: New text.
    public func setText(_ newText: String) {
        field.setText(newText)
    }

    /// One row: the widest item plus the disclosure cell.
    public override var intrinsicContentSize: Size? {
        let widest = items.map(\.count).max() ?? 8
        return Size(width: widest + 4, height: 1)
    }

    /// Positions the field, leaving the trailing cells for `▾`.
    public override func layoutSubviews() {
        field.frame = Rect(
            x: 0,
            y: 0,
            width: max(0, bounds.size.width - 2),
            height: 1
        )
    }

    /// Draws the disclosure; accent-colored while the popup is open.
    public override func draw(_ painter: Painter) {
        let theme = effectiveTheme
        var style = theme.border

        if isOpen, theme.accent != .standard {
            style.foreground = theme.accent
        }

        painter.set(
            TerminalCell(character: "▾", style: style),
            at: Point(x: bounds.size.width - 1, y: 0)
        )
    }

    /// `↓` (bubbling out of the field) opens the popup.
    public override func keyDown(_ key: KeyInput) -> Bool {
        guard key.modifiers.isEmpty, key.key == .down else {
            return false
        }

        openPopup()
        return true
    }

    /// Click on the disclosure cells toggles the popup.
    public override func mouseEvent(_ mouse: MouseInput) -> Bool {
        guard mouse.action == .press, mouse.button == .left,
              mouse.position.x >= bounds.size.width - 2 else {
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

    /// Opens the popup, highlighting the item matching the field text.
    public func openPopup() {
        guard popup == nil, !items.isEmpty else {
            return
        }

        let highlighted = items.firstIndex(of: field.text) ?? 0

        guard let list = PopUpList.present(
            items: items,
            highlightedIndex: highlighted,
            anchor: self
        ) else {
            return
        }

        list.onChoose = { [weak self] index in
            guard let self else {
                return
            }

            self.closePopup()
            self.field.setText(self.items[index])
            self.onSelectionChanged(index)
            self.onChanged(self.field.text)
        }

        list.onDismiss = { [weak self] in
            self?.closePopup()
        }

        popup = list
        setNeedsDisplay()
    }

    /// Closes the popup, returning focus to the field when the popup held
    /// it; outside-click focus stands.
    public func closePopup() {
        guard let popup else {
            return
        }

        let window = owningWindow
        let popupHadFocus = window?.firstResponder === popup

        self.popup = nil
        popup.removeFromSuperview()

        if popupHadFocus {
            window?.makeFirstResponder(field)
        }

        setNeedsDisplay()
    }

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
