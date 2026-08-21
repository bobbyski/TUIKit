/// The floating suggestion list that follows a text field.
///
/// ```text
///   Theme: tu▏
///          ┌────────────┐
///          │▸turbo      │
///          │ turbo-dark │
///          └────────────┘
/// ```
///
/// Attach one to any `TextField` (a `SearchField.field`, a
/// `TokenField.field`, a form row): as the text changes the list filters
/// `items` and shows the matches under the field. The field KEEPS the
/// focus — typing continues — while `↑`/`↓` move the highlight, Return
/// accepts it and Esc hides the list (those arrive as cold keys the field
/// does not use, and Return through the field's own submit). A click on a
/// suggestion accepts it too.
///
/// ```swift
/// let themes = CompletionList(for: themeField)
/// themes.items = Theme.builtIn.map(\.name)
/// themes.onAccept = { name in apply(name) }   // default: puts it in the field
/// ```
///
/// Phase 16 basics: single-line fields only; the code editor's completion
/// will attach through the same shape later.
@MainActor
public final class CompletionList: TUIView {
    /// The field this list follows.
    public private(set) weak var field: TextField?

    /// Every suggestion; `filter` picks the ones shown.
    public var items: [String] = [] {
        didSet {
            refilter()
        }
    }

    /// Decides whether an item matches the typed text. Defaults to a
    /// case-insensitive prefix match.
    public var filter: (String, String) -> Bool = { query, item in
        item.lowercased().hasPrefix(query.lowercased())
    }

    /// How many suggestions show at most.
    public var maximumVisible = 6

    /// Whether an empty field shows every item. Off by default.
    public var showsAllWhenEmpty = false

    /// Receives the accepted suggestion. Defaults to putting it in the field.
    public var onAccept: ((String) -> Void)?

    /// The suggestions currently shown.
    public private(set) var matches: [String] = []

    /// The highlighted suggestion.
    public private(set) var highlightedIndex = 0

    /// Creates a list following a field, wrapping the field's change and
    /// submit handlers (the ones already set keep running).
    ///
    /// - Parameter field: The field to follow.
    public init(for field: TextField) {
        self.field = field
        super.init(frame: .zero)
        themeContext = .menus
        isHidden = true

        let previousChanged = field.onChanged
        let previousSubmit = field.onSubmit

        field.onChanged = { [weak self] text in
            previousChanged(text)
            self?.refilter()
        }

        field.onSubmit = { [weak self] text in
            if let self, !self.isHidden, self.matches.indices.contains(self.highlightedIndex) {
                self.accept(self.highlightedIndex)
                return
            }

            previousSubmit(text)
        }
    }

    /// Never focused: the field keeps typing.
    public override var acceptsFirstResponder: Bool {
        false
    }

    /// Accepts a suggestion, exactly as Return or a click does.
    ///
    /// - Parameter index: The suggestion.
    public func accept(_ index: Int) {
        guard matches.indices.contains(index) else {
            return
        }

        let choice = matches[index]
        hide()

        if let onAccept {
            onAccept(choice)
        } else {
            field?.setText(choice)
        }
    }

    /// Hides the list until the text changes again.
    public func hide() {
        guard !isHidden else {
            return
        }

        isHidden = true
        setNeedsDisplay()
        superview?.setNeedsDisplay()
    }

    /// Draws the box of suggestions.
    public override func draw(_ painter: Painter) {
        let theme = effectiveTheme
        painter.fill(bounds, with: .blank)
        painter.drawBox(bounds, style: theme.border, border: theme.borderStyle.inner)

        let innerWidth = max(0, bounds.size.width - 4)

        for (index, item) in matches.prefix(maximumVisible).enumerated() {
            let marker = index == highlightedIndex ? "▸" : " "
            let text = Label.truncated(item, width: innerWidth)
            let padded = marker + text + String(repeating: " ", count: max(0, innerWidth - text.count)) + " "
            painter.write(padded, at: Point(x: 1, y: index + 1), style: index == highlightedIndex ? theme.selection : CellStyle())
        }
    }

    /// ↑/↓ move the highlight and Esc hides — keys the field left unused.
    public override func handleColdKey(_ key: KeyInput) -> Bool {
        guard !isHidden, key.modifiers.isEmpty else {
            return false
        }

        switch key.key {
        case .up:
            moveHighlight(by: -1)
            return true

        case .down:
            moveHighlight(by: 1)
            return true

        case .escape:
            hide()
            return true

        default:
            return false
        }
    }

    /// A click accepts the suggestion under it.
    public override func mouseEvent(_ mouse: MouseInput) -> Bool {
        guard mouse.action == .press, mouse.button == .left else {
            return false
        }

        let index = mouse.position.y - 1

        if matches.indices.contains(index), index < maximumVisible {
            accept(index)
        }

        return true
    }

    // MARK: - Following the field

    private func refilter() {
        guard let field else {
            hide()
            return
        }

        let query = field.text

        if query.isEmpty, !showsAllWhenEmpty {
            matches = []
        } else {
            matches = items.filter { filter(query, $0) && $0 != query }
        }

        highlightedIndex = 0

        guard !matches.isEmpty, place(below: field) else {
            hide()
            return
        }

        isHidden = false
        setNeedsDisplay()
    }

    // Puts the list in the field's window, under (or over) the field.
    private func place(below field: TextField) -> Bool {
        var window: Window?
        var origin = Point.zero
        var current: TUIView? = field

        while let view = current {
            if let found = view as? Window {
                window = found
                break
            }

            origin = origin + view.frame.origin
            current = view.superview
        }

        guard let window else {
            return false
        }

        if superview !== window {
            removeFromSuperview()
            window.addSubview(self)
        } else {
            window.addSubview(self)   // re-adding keeps the list above later siblings
        }

        let visible = min(matches.count, maximumVisible)
        let widest = matches.prefix(maximumVisible).map(\.count).max() ?? 4
        let size = Size(width: min(widest + 4, window.bounds.size.width), height: visible + 2)
        let spaceBelow = window.bounds.size.height - (origin.y + 1)
        let y = spaceBelow >= size.height || origin.y < size.height ? origin.y + 1 : origin.y - size.height

        frame = Rect(
            origin: Point(x: max(0, min(origin.x, window.bounds.size.width - size.width)), y: max(0, y)),
            size: size
        )
        return true
    }

    private func moveHighlight(by delta: Int) {
        let visible = min(matches.count, maximumVisible)

        guard visible > 0 else {
            return
        }

        highlightedIndex = (highlightedIndex + delta + visible) % visible
        setNeedsDisplay()
    }
}
