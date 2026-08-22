/// Value track with a draggable handle, horizontal or vertical.
///
/// ```text
///   ├────────█─────────┤     value 45 of 0...100
///
///   ┬                        a vertical one runs LOW AT THE BOTTOM,
///   │                        the way a fader does — up is more
///   █
///   │
///   ┴
/// ```
///
/// Arrows step the value (`←`/`→` on a horizontal one, `↑`/`↓` on a vertical
/// one), Home/End jump to the bounds, and clicking or dragging anywhere on
/// the track positions the handle (the window's mouse capture keeps drags
/// alive). The handle recolors to the theme's accent while the slider is
/// focused.
///
/// ```swift
/// let volume = Slider(value: 40, in: 0...100, step: 5)
/// volume.onValueChanged = { level in mixer.volume = level }
///
/// let fader = Slider(value: 3, in: 0...10, orientation: .vertical)
/// ```
///
/// One control rather than two: a vertical slider differs from a horizontal
/// one in which coordinate it reads and which glyphs it draws, and a separate
/// type would be that difference plus a copy of everything else — the value
/// clamping, the stepping, the rounding, the focus colour, and every fix any
/// of those ever needs.
@MainActor
public final class Slider: TUIView {
    /// Which way a slider runs.
    ///
    /// Spelled with `StackView.Axis` so the framework has one word for this
    /// rather than an `Orientation` here and an `Axis` next door.
    public typealias Orientation = StackView.Axis

    /// Which way this one runs.
    public var orientation: Orientation {
        didSet {
            if orientation != oldValue {
                superview?.setNeedsLayout()
                setNeedsDisplay()
            }
        }
    }
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

    /// Evenly spaced marks drawn on the track, ends included; fewer than 2
    /// draws none. With `snapsToTicks`, the value only ever rests on one.
    public var tickMarks: Int = 0 {
        didSet {
            if tickMarks != oldValue {
                setNeedsDisplay()
            }
        }
    }

    /// Whether the value snaps to the nearest tick — and the arrows walk
    /// tick to tick rather than by `step`.
    public var snapsToTicks = false {
        didSet {
            if snapsToTicks, !oldValue {
                value = snapped(value)
                setNeedsDisplay()
            }
        }
    }

    /// Called when the value changes through interaction or
    /// `setValue(_:notify:)`.
    public var onValueChanged: (Int) -> Void = { _ in }

    /// Creates a slider.
    ///
    /// - Parameters:
    ///   - value: Initial value, clamped into the range.
    ///   - range: Allowed value bounds.
    ///   - step: Amount one arrow step moves the value.
    ///   - orientation: Horizontal (the default) or vertical.
    public init(
        value: Int = 0,
        in range: ClosedRange<Int> = 0...100,
        step: Int = 1,
        orientation: Orientation = .horizontal
    ) {
        self.orientation = orientation
        self.range = range
        self.step = max(1, step)
        self.value = min(max(range.lowerBound, value), range.upperBound)
        super.init(frame: .zero)
    }

    /// Sliders take keyboard focus.
    public override var acceptsFirstResponder: Bool {
        true
    }

    /// One row and a comfortable length — the other way round when vertical.
    public override var intrinsicContentSize: Size? {
        switch orientation {
        case .horizontal:
            return Size(width: 16, height: 1)

        case .vertical:
            return Size(width: 1, height: 8)
        }
    }

    /// Sets the value programmatically, clamped into the range.
    ///
    /// - Parameters:
    ///   - newValue: Desired value.
    ///   - notify: Whether `onValueChanged` fires. Defaults to silent.
    public func setValue(_ newValue: Int, notify: Bool = false) {
        let clampedValue = snapped(clamped(newValue))

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
        let length = trackLength

        guard length >= 3 else {
            return
        }

        let theme = effectiveTheme
        let characters = theme.borderStyle.inner.characters ?? BorderStyle.single.characters!
        let junctions = theme.borderStyle.inner.junctions ?? BorderStyle.single.junctions!

        // The theme's glyphs at their INNER weight: a track is an interior
        // line, never a window frame, so a double-framed theme still draws
        // it single (rule one: double lines are almost never the choice).
        let (startCap, endCap, line): (Character, Character, Character)

        switch orientation {
        case .horizontal:
            (startCap, endCap, line) = (junctions.teeLeft, junctions.teeRight, characters.horizontal)

        case .vertical:
            // Offset 0 is the LOW end, which on a fader is the bottom — so
            // the cap drawn there is the one that closes a line from below.
            (startCap, endCap, line) = (junctions.teeBottom, junctions.teeTop, characters.vertical)
        }

        painter.set(TerminalCell(character: startCap, style: theme.border), at: point(along: 0))
        painter.set(TerminalCell(character: endCap, style: theme.border), at: point(along: length - 1))

        for offset in 1..<(length - 1) {
            painter.set(TerminalCell(character: line, style: theme.border), at: point(along: offset))
        }

        // Ticks sit on the track; the handle draws over the one it rests on.
        // Always the single-line cross: a tick is a mark, not a frame, so it
        // stays light even where the theme frames windows in double lines.
        for tick in tickValues {
            painter.set(TerminalCell(character: "┼", style: theme.border), at: point(along: offset(forValue: tick)))
        }

        var handleStyle = theme.border

        // Same surface guard as the dividers: a full-block handle recolored
        // to an accent that IS the surface reads as a hole in the track.
        if isFirstResponder, let cue = theme.cueAccent(over: handleStyle.background) {
            handleStyle.foreground = cue
        }

        painter.set(TerminalCell(character: "█", style: handleStyle), at: point(along: handleOffset))
    }

    /// Arrows step; Home/End jump to the bounds.
    public override func keyDown(_ key: KeyInput) -> Bool {
        guard key.modifiers.isEmpty else {
            return false
        }

        switch key.key {
        case .left where orientation == .horizontal, .down where orientation == .vertical:
            change(to: snapsToTicks ? (tickValues.last { $0 < value } ?? value) : value - step)
            return true

        case .right where orientation == .horizontal, .up where orientation == .vertical:
            change(to: snapsToTicks ? (tickValues.first { $0 > value } ?? value) : value + step)
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
            change(to: value(atOffset: offset(of: mouse.position)))
            return true

        case .release:
            return true

        default:
            return false
        }
    }

    // MARK: - Geometry
    //
    // Everything below works in ONE dimension — an offset along the track —
    // and the two functions at the end are the only places that know which
    // way the track points.

    // Cells the track occupies.
    private var trackLength: Int {
        switch orientation {
        case .horizontal:
            return bounds.size.width

        case .vertical:
            return bounds.size.height
        }
    }

    // Where the handle sits along the track.
    private var handleOffset: Int {
        offset(forValue: value)
    }

    // Track offset for a value.
    private func offset(forValue candidate: Int) -> Int {
        let inner = max(1, trackLength - 2)
        let span = range.upperBound - range.lowerBound

        guard span > 0 else {
            return 1
        }

        return 1 + (candidate - range.lowerBound) * (inner - 1) / span
    }

    // The values the tick marks stand on, lowest first.
    private var tickValues: [Int] {
        guard tickMarks >= 2 else {
            return []
        }

        let span = range.upperBound - range.lowerBound
        return (0..<tickMarks).map { range.lowerBound + ($0 * span + (tickMarks - 1) / 2) / (tickMarks - 1) }
    }

    // The nearest tick when snapping; otherwise the value itself.
    private func snapped(_ candidate: Int) -> Int {
        guard snapsToTicks, !tickValues.isEmpty else {
            return candidate
        }

        return tickValues.min { abs($0 - candidate) < abs($1 - candidate) } ?? candidate
    }

    // Value for an offset along the track (rounded).
    private func value(atOffset offset: Int) -> Int {
        let inner = max(2, trackLength - 2)
        let span = range.upperBound - range.lowerBound
        let position = min(max(0, offset - 1), inner - 1)
        return range.lowerBound + (position * span + (inner - 1) / 2) / (inner - 1)
    }

    // A track offset as a point. A vertical slider counts from the BOTTOM:
    // it is a fader, and on a fader up is more.
    private func point(along offset: Int) -> Point {
        switch orientation {
        case .horizontal:
            return Point(x: offset, y: 0)

        case .vertical:
            return Point(x: 0, y: max(0, bounds.size.height - 1 - offset))
        }
    }

    // The reverse: a point as a track offset.
    private func offset(of point: Point) -> Int {
        switch orientation {
        case .horizontal:
            return point.x

        case .vertical:
            return max(0, bounds.size.height - 1 - point.y)
        }
    }

    private func change(to newValue: Int) {
        let clampedValue = snapped(clamped(newValue))

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
