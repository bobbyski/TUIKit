/// Committed text becomes removable tokens — the To: field.
///
/// ```text
///   [swift ×] [tui ×] type and press Return…
/// ```
///
/// Return mints a token from the typed text (and clears it); Backspace on
/// an empty tail removes the last token; clicking a token's `×` removes that
/// one. The tail is an ordinary `TextField`, so attach a `CompletionList`
/// to `field` for suggestions. Tokens that do not fit collapse into a
/// `+n` count before the field.
///
/// ```swift
/// let recipients = TokenField(tokens: ["ops"])
/// recipients.onTokensChanged = { names in mail.to = names }
/// ```
///
/// Phase 16 basics: no ←/→ walking of tokens, no token selection.
@MainActor
public final class TokenField: TUIView {
    /// The tokens, in order.
    public private(set) var tokens: [String]

    /// The tail where the next token is typed.
    public let field: TextField

    /// Dimmed text in the empty tail.
    public var placeholder: String {
        get { field.placeholder }
        set { field.placeholder = newValue }
    }

    /// Whether minting trims whitespace and drops duplicates. On by default.
    public var deduplicates = true

    /// Called after tokens change through interaction or `setTokens(_:notify:)`.
    public var onTokensChanged: ([String]) -> Void = { _ in }

    // Token chips laid out by the last draw: x ranges for hit-testing.
    private var chipRanges: [Range<Int>] = []
    private var hiddenTokenCount = 0

    /// Creates a token field.
    ///
    /// - Parameters:
    ///   - tokens: Initial tokens.
    ///   - placeholder: Dimmed text in the empty tail.
    public init(tokens: [String] = [], placeholder: String = "") {
        self.tokens = tokens
        field = TextField(placeholder: placeholder)
        super.init(frame: .zero)
        addSubview(field)

        field.onSubmit = { [weak self] text in
            self?.mint(text)
        }

        field.onDeleteBackwardAtStart = { [weak self] in
            self?.removeLast()
        }
    }

    /// Focus lands on the tail.
    public override var acceptsFirstResponder: Bool {
        false
    }

    /// One row, the tokens plus a typing tail.
    public override var intrinsicContentSize: Size? {
        Size(width: chipsWidth + 16, height: 1)
    }

    /// Replaces the tokens programmatically. Reports nothing.
    ///
    /// - Parameters:
    ///   - newTokens: The tokens.
    ///   - notify: Whether `onTokensChanged` fires. Defaults to silent.
    public func setTokens(_ newTokens: [String], notify: Bool = false) {
        guard newTokens != tokens else {
            return
        }

        tokens = newTokens
        setNeedsLayout()
        setNeedsDisplay()

        if notify {
            onTokensChanged(tokens)
        }
    }

    /// Mints a token from text, exactly as Return does.
    ///
    /// - Parameter text: The text; trimmed, ignored when empty or (with
    ///   `deduplicates`) already present.
    public func mint(_ text: String) {
        let token = deduplicates ? text.trimmingCharacters(in: .whitespaces) : text

        field.setText("")

        guard !token.isEmpty, !(deduplicates && tokens.contains(token)) else {
            setNeedsLayout()
            setNeedsDisplay()
            return
        }

        tokens.append(token)
        setNeedsLayout()
        setNeedsDisplay()
        onTokensChanged(tokens)
    }

    /// Removes a token, exactly as its `×` does.
    ///
    /// - Parameter index: The token.
    public func remove(at index: Int) {
        guard tokens.indices.contains(index) else {
            return
        }

        tokens.remove(at: index)
        setNeedsLayout()
        setNeedsDisplay()
        onTokensChanged(tokens)
    }

    /// Removes the last token, exactly as Backspace on an empty tail does.
    public func removeLast() {
        guard !tokens.isEmpty else {
            return
        }

        remove(at: tokens.count - 1)
    }

    /// Chips first, the tail takes the rest.
    public override func layoutSubviews() {
        let used = layoutChips(width: bounds.size.width)
        field.frame = Rect(x: used, y: 0, width: max(0, bounds.size.width - used), height: 1)
    }

    /// Draws the chips.
    public override func draw(_ painter: Painter) {
        let theme = effectiveTheme
        var chip = theme.selection

        if theme.selectionBackground == theme.background, let cue = theme.cueAccent(over: theme.background) {
            chip = CellStyle(foreground: cue, background: theme.background, flags: [.inverse])
        }

        for (index, range) in chipRanges.enumerated() {
            painter.write("[\(tokens[index]) ×]", at: Point(x: range.lowerBound, y: 0), style: chip)
        }

        if hiddenTokenCount > 0, let last = chipRanges.last {
            painter.write("+\(hiddenTokenCount)", at: Point(x: last.upperBound + 1, y: 0), style: theme.placeholder)
        } else if hiddenTokenCount > 0 {
            painter.write("+\(hiddenTokenCount)", at: .zero, style: theme.placeholder)
        }
    }

    /// A click on a chip's `×` removes it; elsewhere on a chip does nothing.
    public override func mouseEvent(_ mouse: MouseInput) -> Bool {
        guard mouse.action == .press, mouse.button == .left, mouse.position.y == 0 else {
            return false
        }

        for (index, range) in chipRanges.enumerated() where range.contains(mouse.position.x) {
            if mouse.position.x == range.upperBound - 2 {   // the ×
                remove(at: index)
            }

            return true
        }

        return false
    }

    // MARK: - Chips

    private var chipsWidth: Int {
        tokens.reduce(0) { $0 + $1.count + 5 }
    }

    // Lays out as many chips as fit (leaving the tail at least 8 cells),
    // records their ranges, and returns the width used.
    @discardableResult
    private func layoutChips(width: Int) -> Int {
        chipRanges = []
        hiddenTokenCount = 0
        var x = 0
        let limit = max(0, width - 8)

        for token in tokens {
            let chipWidth = token.count + 4   // "[", token, " ×", "]"

            guard x + chipWidth <= limit else {
                hiddenTokenCount = tokens.count - chipRanges.count
                break
            }

            chipRanges.append(x..<(x + chipWidth))
            x += chipWidth + 1
        }

        if hiddenTokenCount > 0 {
            x += "+\(hiddenTokenCount)".count + 1
        }

        return x
    }
}
