/// Two thumbs bounding a span on one track, with a minimum gap between them.
///
/// ```text
///   ├────█━━━━━━━━━█─────────┤     20...60 of 0...100
///        lower      upper
/// ```
///
/// One thumb is *active* at a time: `←`/`→` move it by `step`, Home/End
/// send it to its bound, Space switches thumbs. Clicking grabs the nearest
/// thumb (and drags keep moving it). A thumb never crosses the other one or
/// closes the span below `minimumGap`; the other thumb stays put. The active
/// thumb recolors to the theme's accent while the slider is focused.
///
/// ```swift
/// let price = RangeSlider(lower: 20, upper: 60, in: 0...100, minimumGap: 5)
/// price.onValuesChanged = { span in filter.price = span }
/// ```
///
/// Horizontal only, and one row (Phase 16 basics); `Slider` covers the
/// vertical single-thumb case.
@MainActor
public final class RangeSlider: TUIView {
    /// Which thumb keys and drags move.
    public enum Thumb: Hashable, Sendable {
        /// The span's lower bound.
        case lower

        /// The span's upper bound.
        case upper
    }

    /// Lower end of the span.
    public private(set) var lowerValue: Int

    /// Upper end of the span.
    public private(set) var upperValue: Int

    /// The span as a range.
    public var values: ClosedRange<Int> {
        lowerValue...upperValue
    }

    /// Allowed value bounds.
    public var range: ClosedRange<Int> {
        didSet {
            if range != oldValue {
                apply(lower: lowerValue, upper: upperValue)
                setNeedsDisplay()
            }
        }
    }

    /// Amount one arrow step moves the active thumb.
    public var step: Int

    /// Smallest span the thumbs may enclose.
    public var minimumGap: Int {
        didSet {
            minimumGap = max(0, minimumGap)
            apply(lower: lowerValue, upper: upperValue)
        }
    }

    /// The thumb keys and drags move.
    public private(set) var activeThumb: Thumb = .lower

    /// Called when either value changes through interaction or
    /// `setValues(_:notify:)`.
    public var onValuesChanged: (ClosedRange<Int>) -> Void = { _ in }

    /// Creates a range slider.
    ///
    /// - Parameters:
    ///   - lower: Initial lower value.
    ///   - upper: Initial upper value.
    ///   - range: Allowed value bounds.
    ///   - step: Amount one arrow step moves a thumb.
    ///   - minimumGap: Smallest span the thumbs may enclose.
    public init(
        lower: Int = 0,
        upper: Int = 100,
        in range: ClosedRange<Int> = 0...100,
        step: Int = 1,
        minimumGap: Int = 0
    ) {
        self.range = range
        self.step = max(1, step)
        self.minimumGap = max(0, minimumGap)
        self.lowerValue = range.lowerBound
        self.upperValue = range.upperBound
        super.init(frame: .zero)
        apply(lower: lower, upper: upper)
    }

    /// Range sliders take keyboard focus.
    public override var acceptsFirstResponder: Bool {
        true
    }

    /// One row, a comfortable length.
    public override var intrinsicContentSize: Size? {
        Size(width: 20, height: 1)
    }

    /// Sets both values programmatically, clamped into the range and kept
    /// `minimumGap` apart (the upper value yields when they conflict).
    ///
    /// - Parameters:
    ///   - newValues: Desired span.
    ///   - notify: Whether `onValuesChanged` fires. Defaults to silent.
    public func setValues(_ newValues: ClosedRange<Int>, notify: Bool = false) {
        let before = values
        apply(lower: newValues.lowerBound, upper: newValues.upperBound)

        guard values != before else {
            return
        }

        setNeedsDisplay()

        if notify {
            onValuesChanged(values)
        }
    }

    /// Makes a thumb the one keys move.
    ///
    /// - Parameter thumb: The thumb to activate.
    public func activate(_ thumb: Thumb) {
        guard thumb != activeThumb else {
            return
        }

        activeThumb = thumb
        setNeedsDisplay()
    }

    /// Draws the track, the span between the thumbs, and the thumbs.
    public override func draw(_ painter: Painter) {
        let length = bounds.size.width

        guard length >= 4, bounds.size.height > 0 else {
            return
        }

        let theme = effectiveTheme
        let characters = theme.borderStyle.characters ?? BorderStyle.single.characters!
        let junctions = theme.borderStyle.junctions ?? BorderStyle.single.junctions!

        painter.set(TerminalCell(character: junctions.teeLeft, style: theme.border), at: .zero)
        painter.set(TerminalCell(character: junctions.teeRight, style: theme.border), at: Point(x: length - 1, y: 0))

        let lowerOffset = offset(forValue: lowerValue)
        let upperOffset = offset(forValue: upperValue)
        let cue = theme.cueAccent(over: theme.border.background)

        for x in 1..<(length - 1) {
            let inSpan = x > lowerOffset && x < upperOffset
            var style = theme.border

            if inSpan, let cue {
                style.foreground = cue
            }

            painter.set(TerminalCell(character: inSpan ? "━" : characters.horizontal, style: style), at: Point(x: x, y: 0))
        }

        for (thumb, x) in [(Thumb.lower, lowerOffset), (Thumb.upper, upperOffset)] {
            var style = theme.border

            if isFirstResponder, thumb == activeThumb, let cue {
                style.foreground = cue
            }

            painter.set(TerminalCell(character: "█", style: style), at: Point(x: x, y: 0))
        }
    }

    /// Arrows move the active thumb, Home/End send it to its bound, Space
    /// switches thumbs.
    public override func keyDown(_ key: KeyInput) -> Bool {
        guard key.modifiers.isEmpty else {
            return false
        }

        switch key.key {
        case .left:
            move(activeThumb, to: activeValue - step)
            return true

        case .right:
            move(activeThumb, to: activeValue + step)
            return true

        case .home:
            move(activeThumb, to: range.lowerBound)
            return true

        case .end:
            move(activeThumb, to: range.upperBound)
            return true

        case .character(" "):
            activate(activeThumb == .lower ? .upper : .lower)
            return true

        default:
            return false
        }
    }

    /// A press grabs the nearest thumb; drags keep moving it.
    public override func mouseEvent(_ mouse: MouseInput) -> Bool {
        switch mouse.action {
        case .press where mouse.button == .left:
            let x = mouse.position.x
            let nearest: Thumb = abs(x - offset(forValue: lowerValue)) <= abs(x - offset(forValue: upperValue)) ? .lower : .upper
            activate(nearest)
            move(nearest, to: value(atOffset: x))
            return true

        case .drag:
            move(activeThumb, to: value(atOffset: mouse.position.x))
            return true

        case .release:
            return true

        default:
            return false
        }
    }

    // MARK: - Values

    private var activeValue: Int {
        activeThumb == .lower ? lowerValue : upperValue
    }

    // Moves one thumb, interactively: the other stays put, the gap holds.
    private func move(_ thumb: Thumb, to candidate: Int) {
        let before = values

        switch thumb {
        case .lower:
            lowerValue = min(max(range.lowerBound, candidate), upperValue - minimumGap, range.upperBound)
            lowerValue = max(lowerValue, range.lowerBound)

        case .upper:
            upperValue = max(min(range.upperBound, candidate), lowerValue + minimumGap, range.lowerBound)
            upperValue = min(upperValue, range.upperBound)
        }

        guard values != before else {
            return
        }

        setNeedsDisplay()
        onValuesChanged(values)
    }

    // Clamps a pair into the range, keeping the gap; the upper value yields.
    private func apply(lower: Int, upper: Int) {
        let span = range.upperBound - range.lowerBound
        let gap = min(minimumGap, span)
        let clampedLower = min(max(range.lowerBound, lower), range.upperBound - gap)
        let clampedUpper = min(max(clampedLower + gap, upper), range.upperBound)
        lowerValue = clampedLower
        upperValue = clampedUpper
    }

    // MARK: - Geometry (the same track arithmetic as Slider)

    private func offset(forValue candidate: Int) -> Int {
        let inner = max(1, bounds.size.width - 2)
        let span = range.upperBound - range.lowerBound

        guard span > 0 else {
            return 1
        }

        return 1 + (candidate - range.lowerBound) * (inner - 1) / span
    }

    private func value(atOffset offset: Int) -> Int {
        let inner = max(2, bounds.size.width - 2)
        let span = range.upperBound - range.lowerBound
        let position = min(max(0, offset - 1), inner - 1)
        return range.lowerBound + (position * span + (inner - 1) / 2) / (inner - 1)
    }
}
