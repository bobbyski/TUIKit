/// Search box: a magnifier, a text field, and a clear affordance.
///
/// ```text
///   ⌕ Search                          (empty — the placeholder shows)
///   ⌕ ambiance theme                ✕ (typed — ✕, or Esc, clears)
/// ```
///
/// Two reports, like a search field anywhere: `onSearch` fires live as the
/// text changes (after `debounce`, when one is set) and `onCommit` fires on
/// Return. Esc clears a non-empty field and reports the empty search; the
/// `✕` does the same by mouse. The field inside is an ordinary `TextField`,
/// so editing, clipboard and selection behave exactly as they do in one.
///
/// ```swift
/// let search = SearchField()
/// search.debounce = .milliseconds(150)
/// search.onSearch = { query in results.filter(query) }
/// search.onCommit = { query in results.open(query) }
/// ```
///
/// Deliberately basic (Phase 16): no recents menu, no scope buttons, no
/// token-style filters — compose those beside it.
@MainActor
public final class SearchField: TUIView {
    /// The text field doing the editing.
    public let field: TextField

    /// Current query.
    public var text: String {
        field.text
    }

    /// Dimmed text shown while empty.
    public var placeholder: String {
        get { field.placeholder }
        set { field.placeholder = newValue }
    }

    /// Called with the query as it changes — live, or after `debounce`.
    public var onSearch: (String) -> Void = { _ in }

    /// Called with the query when Return is pressed.
    public var onCommit: (String) -> Void = { _ in }

    /// Quiet time after a keystroke before `onSearch` fires. `nil` (the
    /// default) reports every change immediately. The wait rides the app's
    /// timer; with no running `App` (a bare test window) changes report
    /// live.
    public var debounce: Duration?

    // Cancels the pending debounced report, when one is armed.
    private var cancelPending: (() -> Void)?

    // How a debounce wait is scheduled — the app's timer by default, or a
    // test's hand-cranked stand-in. Returns the cancel.
    var scheduleDebounce: ((Duration, @escaping @MainActor () -> Void) -> (() -> Void))?

    /// Creates a search field.
    ///
    /// - Parameters:
    ///   - text: Initial query.
    ///   - placeholder: Dimmed text shown while empty.
    public init(text: String = "", placeholder: String = "Search") {
        field = TextField(text: text, placeholder: placeholder)
        super.init(frame: .zero)
        addSubview(field)

        field.onChanged = { [weak self] query in
            self?.queryChanged(query)
        }

        field.onSubmit = { [weak self] query in
            self?.submit(query)
        }
    }

    /// Focus lands on the field inside, never on the frame around it.
    public override var acceptsFirstResponder: Bool {
        false
    }

    /// One row, a comfortable query's width.
    public override var intrinsicContentSize: Size? {
        Size(width: 24, height: 1)
    }

    /// Replaces the query programmatically. Reports nothing.
    ///
    /// - Parameter newText: The new query.
    public func setText(_ newText: String) {
        field.setText(newText)
        setNeedsLayout()
        setNeedsDisplay()
    }

    /// Empties the field and reports the empty search — what Esc and `✕` do.
    public func clear() {
        cancelPending?()
        cancelPending = nil
        field.setText("")
        setNeedsLayout()
        setNeedsDisplay()
        onSearch("")
    }

    /// The field sits after the magnifier and leaves room for `✕` once
    /// there is something to clear.
    public override func layoutSubviews() {
        let trailing = text.isEmpty ? 0 : 2
        field.frame = Rect(x: 2, y: 0, width: max(0, bounds.size.width - 2 - trailing), height: 1)
    }

    /// Draws the magnifier, and the clear glyph while there is text.
    public override func draw(_ painter: Painter) {
        let theme = effectiveTheme
        let width = bounds.size.width

        guard width > 0, bounds.size.height > 0 else {
            return
        }

        painter.write("⌕", at: .zero, style: CellStyle(foreground: theme.placeholderForeground, background: theme.background))

        if !text.isEmpty, width >= 4 {
            painter.write("✕", at: Point(x: width - 1, y: 0), style: theme.base)
        }
    }

    /// Esc clears a non-empty query (bubbled up from the field, which does
    /// not use it).
    public override func keyDown(_ key: KeyInput) -> Bool {
        guard key.modifiers.isEmpty, key.key == .escape, !text.isEmpty else {
            return false
        }

        clear()
        return true
    }

    /// A click on `✕` clears.
    public override func mouseEvent(_ mouse: MouseInput) -> Bool {
        guard mouse.action == .press, mouse.button == .left,
              !text.isEmpty, mouse.position.x == bounds.size.width - 1 else {
            return false
        }

        clear()
        return true
    }

    // MARK: - Reports

    private func queryChanged(_ query: String) {
        setNeedsLayout()   // the ✕ appears or disappears
        setNeedsDisplay()
        cancelPending?()
        cancelPending = nil

        guard let debounce, let scheduler = scheduleDebounce ?? appScheduler else {
            onSearch(query)
            return
        }

        cancelPending = scheduler(debounce) { [weak self] in
            self?.cancelPending = nil
            self?.onSearch(query)
        }
    }

    private func submit(_ query: String) {
        // A debounced report still owed goes out first, so the commit never
        // arrives for a query the app has not seen.
        if cancelPending != nil {
            cancelPending?()
            cancelPending = nil
            onSearch(query)
        }

        onCommit(query)
    }

    private var appScheduler: ((Duration, @escaping @MainActor () -> Void) -> (() -> Void))? {
        guard let app = owningWindow?.app else {
            return nil
        }

        return { delay, body in
            let timer = app.schedule(after: delay, body)
            return { timer.cancel() }
        }
    }
}
