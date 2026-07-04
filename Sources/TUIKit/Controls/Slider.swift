/// Horizontal value track with a draggable handle.
///
/// ```text
///   ├────────█─────────┤     value 45 of 0...100
/// ```
///
/// `←`/`→` step the value, Home/End jump to the bounds, and clicking or
/// dragging anywhere on the track positions the handle (the window's mouse
/// capture keeps drags alive). The handle recolors to the theme's accent
/// while the slider is focused.
///
/// ```swift
/// let volume = Slider(value: 40, in: 0...100, step: 5)
/// volume.onValueChanged = { level in mixer.volume = level }
/// ```
@MainActor
public final class Slider: TUIView {
    /// Current value, always within `range`.
    public private(set) var value: Int

    /// Allowed value bounds.
    public var range: ClosedRange<Int> {
        didSet {
            if range != oldValue {
                value = clamped(value)
                setNeedsDisplay()
            }
        }
    }

    /// Amount one arrow step moves the value.
    public var step: Int

    /// Called when the value changes through interaction or
    /// `setValue(_:notify:)`.
    public var onValueChanged: (Int) -> Void = { _ in }

    /// Creates a slider.
    ///
    /// - Parameters:
    ///   - value: Initial value, clamped into the range.
    ///   - range: Allowed value bounds.
    ///   - step: Amount one arrow step moves the value.
    public init(value: Int = 0, in range: ClosedRange<Int> = 0...100, step: Int = 1) {
        self.range = range
        self.step = max(1, step)
        self.value = min(max(range.lowerBound, value), range.upperBound)
        super.init(frame: .zero)
    }

    /// Sliders take keyboard focus.
    public override var acceptsFirstResponder: Bool {
        true
    }

    /// One row; a comfortable default width.
    public override var intrinsicContentSize: Size? {
        Size(width: 16, height: 1)
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

    /// Draws the track, end caps, and handle.
    public override func draw(_ painter: Painter) {
        let width = bounds.size.width

        guard width >= 3 else {
            return
        }

        let theme = effectiveTheme
        let characters = theme.borderStyle.characters ?? BorderStyle.single.characters!
        let junctions = theme.borderStyle.junctions ?? BorderStyle.single.junctions!

        painter.set(TerminalCell(character: junctions.teeLeft, style: theme.border), at: .zero)
        painter.set(TerminalCell(character: junctions.teeRight, style: theme.border), at: Point(x: width - 1, y: 0))

        for x in 1..<(width - 1) {
            painter.set(TerminalCell(character: characters.horizontal, style: theme.border), at: Point(x: x, y: 0))
        }

        var handleStyle = theme.border

        if isFirstResponder, theme.accent != .standard {
            handleStyle.foreground = theme.accent
        }

        painter.set(
            TerminalCell(character: "█", style: handleStyle),
            at: Point(x: handleColumn, y: 0)
        )
    }

    /// Arrows step; Home/End jump to the bounds.
    public override func keyDown(_ key: KeyInput) -> Bool {
        guard key.modifiers.isEmpty else {
            return false
        }

        switch key.key {
        case .left:
            change(to: value - step)
            return true

        case .right:
            change(to: value + step)
            return true

        case .home:
            change(to: range.lowerBound)
            return true

        case .end:
            change(to: range.upperBound)
            return true

        default:
            return false
        }
    }

    /// Click or drag positions the handle.
    public override func mouseEvent(_ mouse: MouseInput) -> Bool {
        switch mouse.action {
        case .press where mouse.button == .left, .drag:
            change(to: value(atColumn: mouse.position.x))
            return true

        case .release:
            return true

        default:
            return false
        }
    }

    // MARK: - Geometry

    // Handle position for the current value.
    private var handleColumn: Int {
        let inner = max(1, bounds.size.width - 2)
        let span = range.upperBound - range.lowerBound

        guard span > 0 else {
            return 1
        }

        return 1 + (value - range.lowerBound) * (inner - 1) / span
    }

    // Value for a clicked column (rounded).
    private func value(atColumn x: Int) -> Int {
        let inner = max(2, bounds.size.width - 2)
        let span = range.upperBound - range.lowerBound
        let position = min(max(0, x - 1), inner - 1)
        return range.lowerBound + (position * span + (inner - 1) / 2) / (inner - 1)
    }

    private func change(to newValue: Int) {
        let clampedValue = clamped(newValue)

        guard clampedValue != value else {
            return
        }

        value = clampedValue
        setNeedsDisplay()
        onValueChanged(value)
    }

    private func clamped(_ candidate: Int) -> Int {
        min(max(range.lowerBound, candidate), range.upperBound)
    }
}
