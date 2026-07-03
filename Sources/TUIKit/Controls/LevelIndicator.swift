/// Capacity or rating display: `▮▮▮▯▯` or `★★★☆☆`.
///
/// Read-only by default; set `isEditable` to let arrows, Home/End, and
/// clicks change the value (click a cell to set that level, click the
/// filled first cell to clear to zero — the rating-widget convention).
/// Filled cells use the theme's accent color.
///
/// ```swift
/// let stars = LevelIndicator(value: 3, maximum: 5, style: .rating)
/// stars.isEditable = true
/// stars.onValueChanged = { rating in review.stars = rating }
/// ```
@MainActor
public final class LevelIndicator: View {
    /// Symbol families.
    public enum IndicatorStyle: Sendable {
        /// `▮` filled / `▯` empty capacity cells.
        case capacity

        /// `★` filled / `☆` empty rating stars.
        case rating

        var filled: Character {
            self == .capacity ? "▮" : "★"
        }

        var empty: Character {
            self == .capacity ? "▯" : "☆"
        }
    }

    /// Current level, `0...maximum`.
    public private(set) var value: Int

    /// Number of cells.
    public var maximum: Int {
        didSet {
            if maximum != oldValue {
                value = min(value, maximum)
                superview?.setNeedsLayout()
                setNeedsDisplay()
            }
        }
    }

    /// Symbol family.
    public var style: IndicatorStyle {
        didSet {
            setNeedsDisplay()
        }
    }

    /// Whether arrows and clicks change the value.
    public var isEditable = false

    /// Called when the value changes through interaction or
    /// `setValue(_:notify:)`.
    public var onValueChanged: (Int) -> Void = { _ in }

    /// Creates a level indicator.
    ///
    /// - Parameters:
    ///   - value: Initial level.
    ///   - maximum: Number of cells.
    ///   - style: Symbol family.
    public init(value: Int = 0, maximum: Int = 5, style: IndicatorStyle = .capacity) {
        self.maximum = max(1, maximum)
        self.value = min(max(0, value), max(1, maximum))
        self.style = style
        super.init(frame: .zero)
    }

    /// Editable indicators take keyboard focus.
    public override var acceptsFirstResponder: Bool {
        isEditable
    }

    /// One row, one cell per level.
    public override var intrinsicContentSize: Size? {
        Size(width: maximum, height: 1)
    }

    /// Sets the level programmatically.
    ///
    /// - Parameters:
    ///   - newValue: Desired level, clamped to `0...maximum`.
    ///   - notify: Whether `onValueChanged` fires. Defaults to silent.
    public func setValue(_ newValue: Int, notify: Bool = false) {
        let clamped = min(max(0, newValue), maximum)

        guard clamped != value else {
            return
        }

        value = clamped
        setNeedsDisplay()

        if notify {
            onValueChanged(value)
        }
    }

    /// Draws filled cells in the accent color, empty cells de-emphasized.
    public override func draw(_ painter: Painter) {
        let theme = effectiveTheme
        var filledStyle = CellStyle()

        if theme.accent != .standard {
            filledStyle.foreground = theme.accent
        }

        for cell in 0..<min(maximum, bounds.size.width) {
            let filled = cell < value
            painter.set(
                TerminalCell(
                    character: filled ? style.filled : style.empty,
                    style: filled ? filledStyle : theme.placeholder
                ),
                at: Point(x: cell, y: 0)
            )
        }
    }

    /// Arrows adjust; Home/End clear/fill (when editable).
    public override func keyDown(_ key: KeyInput) -> Bool {
        guard isEditable, key.modifiers.isEmpty else {
            return false
        }

        switch key.key {
        case .left:
            change(to: value - 1)
            return true

        case .right:
            change(to: value + 1)
            return true

        case .home:
            change(to: 0)
            return true

        case .end:
            change(to: maximum)
            return true

        default:
            return false
        }
    }

    /// Click sets the level; clicking the current level clears to zero.
    public override func mouseEvent(_ mouse: MouseInput) -> Bool {
        guard isEditable, mouse.action == .press, mouse.button == .left,
              mouse.position.x < maximum else {
            return false
        }

        let clicked = mouse.position.x + 1
        change(to: clicked == value ? 0 : clicked)
        return true
    }

    private func change(to newValue: Int) {
        let clamped = min(max(0, newValue), maximum)

        guard clamped != value else {
            return
        }

        value = clamped
        setNeedsDisplay()
        onValueChanged(value)
    }
}
