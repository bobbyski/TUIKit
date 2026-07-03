/// Numeric value with bounded increment/decrement, rendered as `[-] 42 [+]`.
///
/// Up or `+` increments, Down or `-` decrements, Home/End jump to the range
/// bounds, and clicking either bracket button steps in that direction. The
/// value always stays inside `range`; steps at a bound do nothing (and emit
/// nothing). The application receives one semantic event:
///
/// ```swift
/// let size = Stepper(value: 12, in: 6...72, step: 2)
/// size.onValueChanged = { points in editor.fontSize = points }
/// ```
@MainActor
public final class Stepper: View {
    /// Current value, always within `range`.
    public private(set) var value: Int

    /// Allowed value bounds.
    public var range: ClosedRange<Int> {
        didSet {
            if range != oldValue {
                value = clamped(value)
                superview?.setNeedsLayout()
                setNeedsDisplay()
            }
        }
    }

    /// Amount one increment or decrement moves the value.
    public var step: Int

    /// Called when the value changes through interaction or
    /// `setValue(_:notify:)`.
    public var onValueChanged: (Int) -> Void = { _ in }

    /// Creates a stepper.
    ///
    /// - Parameters:
    ///   - value: Initial value, clamped into the range.
    ///   - range: Allowed value bounds.
    ///   - step: Amount one step moves the value.
    public init(value: Int = 0, in range: ClosedRange<Int> = 0...100, step: Int = 1) {
        self.range = range
        self.step = max(1, step)
        self.value = min(max(range.lowerBound, value), range.upperBound)
        super.init(frame: .zero)
    }

    /// Steppers take keyboard focus.
    public override var acceptsFirstResponder: Bool {
        true
    }

    /// One row at `[-] <widest value> [+]` width.
    public override var intrinsicContentSize: Size? {
        Size(width: 3 + 1 + valueFieldWidth + 1 + 3, height: 1)
    }

    /// Sets the value programmatically, clamped into the range.
    ///
    /// - Parameters:
    ///   - newValue: Desired value.
    ///   - notify: Whether `onValueChanged` fires. Defaults to silent.
    public func setValue(_ newValue: Int, notify: Bool = false) {
        let clampedValue = clamped(newValue)

        guard clampedValue != value else {
            return
        }

        value = clampedValue
        setNeedsDisplay()

        if notify {
            onValueChanged(value)
        }
    }

    /// Steps the value, exactly as user interaction would.
    ///
    /// - Parameter direction: `+1` to increment, `-1` to decrement.
    public func stepValue(_ direction: Int) {
        let target = clamped(value + (direction >= 0 ? step : -step))

        guard target != value else {
            return
        }

        value = target
        setNeedsDisplay()
        onValueChanged(value)
    }

    /// Draws the bracket buttons and the right-aligned value.
    public override func draw(_ painter: Painter) {
        let buttonStyle = CellStyle(flags: isFirstResponder ? .inverse : [])
        let field = String(value)
        let padded = String(repeating: " ", count: max(0, valueFieldWidth - field.count)) + field

        painter.write("[-]", at: .zero, style: buttonStyle)
        painter.write(padded, at: Point(x: 4, y: 0))
        painter.write("[+]", at: Point(x: 4 + valueFieldWidth + 1, y: 0), style: buttonStyle)
    }

    /// Up/`+` increments, Down/`-` decrements, Home/End jump to the bounds.
    public override func keyDown(_ key: KeyInput) -> Bool {
        guard key.modifiers.isEmpty else {
            return false
        }

        switch key.key {
        case .up, .character("+"):
            stepValue(1)
            return true

        case .down, .character("-"):
            stepValue(-1)
            return true

        case .home:
            setValue(range.lowerBound, notify: true)
            return true

        case .end:
            setValue(range.upperBound, notify: true)
            return true

        default:
            return false
        }
    }

    /// Clicking a bracket button steps in its direction.
    public override func mouseEvent(_ mouse: MouseInput) -> Bool {
        guard mouse.action == .press, mouse.button == .left, mouse.position.y == 0 else {
            return false
        }

        if mouse.position.x < 3 {
            stepValue(-1)
            return true
        }

        if mouse.position.x >= 4 + valueFieldWidth + 1 {
            stepValue(1)
            return true
        }

        return false
    }

    // Width of the widest value the range can produce.
    private var valueFieldWidth: Int {
        max(String(range.lowerBound).count, String(range.upperBound).count)
    }

    private func clamped(_ candidate: Int) -> Int {
        min(max(range.lowerBound, candidate), range.upperBound)
    }
}
