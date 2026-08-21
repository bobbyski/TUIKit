/// A value in a range, drawn as a bar, a ring, or a dial.
///
/// ```text
///   cells (every terminal):     CPU ████████░░░░░░░░ 52%
///   VTG ring / dial:            a sector sweeping the fraction, value in the middle
/// ```
///
/// Cells first: the bar form draws on every terminal — and it is the honest
/// fallback for `.ring` and `.dial` where there is no vector chrome, because
/// a bar *is* the value, not a placeholder for it. On a VectorTerminal the
/// ring and dial draw as real sectors with the value label over them.
///
/// Thresholds colour the fill: `warningThreshold` and `criticalThreshold`
/// (fractions 0…1) switch the fill from the accent to the theme's warning
/// and error accents once crossed — the same bands `LevelIndicator` uses.
///
/// ```swift
/// let cpu = Gauge(value: 52, in: 0...100, style: .ring)
/// cpu.label = "CPU"
/// cpu.warningThreshold = 0.7
/// cpu.criticalThreshold = 0.9
/// ```
@MainActor
public final class Gauge: TUIView {
    /// How the value is drawn.
    public enum Style: Hashable, Sendable {
        /// A horizontal bar (every terminal).
        case bar

        /// A full ring (VTG; bar in cells).
        case ring

        /// A 270° dial open at the bottom (VTG; bar in cells).
        case dial
    }

    /// Current value, clamped into `range`.
    public private(set) var value: Double

    /// Allowed bounds.
    public var range: ClosedRange<Double> {
        didSet {
            value = min(max(range.lowerBound, value), range.upperBound)
            setNeedsDisplay()
        }
    }

    /// Bar, ring, or dial.
    public var style: Style {
        didSet {
            if style != oldValue {
                setNeedsDisplay()
            }
        }
    }

    /// Text before the bar / under the ring — "CPU".
    public var label = "" {
        didSet {
            if label != oldValue {
                superview?.setNeedsLayout()
                setNeedsDisplay()
            }
        }
    }

    /// Formats the value for display. Defaults to a percentage of the range.
    public var formatter: (Double) -> String = { _ in "" } {
        didSet {
            setNeedsDisplay()
        }
    }

    /// Whether the formatted value draws.
    public var showsValue = true {
        didSet {
            setNeedsDisplay()
        }
    }

    /// Fraction (0…1) past which the fill wears the warning accent.
    public var warningThreshold: Double? {
        didSet {
            setNeedsDisplay()
        }
    }

    /// Fraction (0…1) past which the fill wears the error accent.
    public var criticalThreshold: Double? {
        didSet {
            setNeedsDisplay()
        }
    }

    /// Creates a gauge.
    ///
    /// - Parameters:
    ///   - value: Initial value.
    ///   - range: Allowed bounds.
    ///   - style: Bar (the default), ring, or dial.
    public init(value: Double = 0, in range: ClosedRange<Double> = 0...100, style: Style = .bar) {
        self.range = range
        self.value = min(max(range.lowerBound, value), range.upperBound)
        self.style = style
        super.init(frame: .zero)
        formatter = { [range] value in
            let span = range.upperBound - range.lowerBound
            return span > 0 ? "\(Int(((value - range.lowerBound) / span * 100).rounded()))%" : "\(Int(value))"
        }
    }

    /// Fraction of the range the value sits at, 0…1.
    public var fraction: Double {
        let span = range.upperBound - range.lowerBound
        return span > 0 ? (value - range.lowerBound) / span : 0
    }

    /// A bar row, or room for a ring.
    public override var intrinsicContentSize: Size? {
        switch style {
        case .bar:
            return Size(width: label.count + (label.isEmpty ? 0 : 1) + 16 + 5, height: 1)

        case .ring, .dial:
            return Size(width: 14, height: 7)
        }
    }

    /// Sets the value programmatically, clamped.
    ///
    /// - Parameter newValue: The new value.
    public func setValue(_ newValue: Double) {
        let clamped = min(max(range.lowerBound, newValue), range.upperBound)

        guard clamped != value else {
            return
        }

        value = clamped
        setNeedsDisplay()
    }

    /// The colour the fill wears at the current value: accent, warning, or
    /// error once a threshold is crossed.
    public func fillColor(_ theme: ResolvedTheme) -> TerminalColor {
        if let criticalThreshold, fraction >= criticalThreshold {
            return theme.errorAccent
        }

        if let warningThreshold, fraction >= warningThreshold {
            return theme.warningAccent
        }

        return theme.chartAccent
    }

    /// Ring or dial under VTG; the bar everywhere else.
    public override func draw(_ painter: Painter) {
        painter.fill(bounds, with: .blank)

        let theme = effectiveTheme

        if style != .bar, let chrome = painter.chrome, chrome.covers(bounds),
           let backing = ChromeColor(theme.background),
           let ink = ChromeColor(fillColor(theme)),
           let track = ChromeColor(theme.placeholderForeground),
           bounds.size.height >= 3, bounds.size.width >= 6 {
            drawVector(painter, chrome: chrome, theme: theme, backing: backing, ink: ink, track: track)
            return
        }

        drawBar(painter, theme: theme)
    }

    // MARK: - Cells

    private func drawBar(_ painter: Painter, theme: ResolvedTheme) {
        let width = bounds.size.width

        guard width > 0, bounds.size.height > 0 else {
            return
        }

        var x = 0

        if !label.isEmpty {
            let text = Label.truncated(label, width: width)
            painter.write(text, at: .zero, style: theme.base)
            x = text.count + 1
        }

        let valueText = showsValue ? formatter(value) : ""
        let barWidth = max(0, width - x - (valueText.isEmpty ? 0 : valueText.count + 1))
        let filled = Int((Double(barWidth) * fraction).rounded())
        var fill = theme.base
        fill.foreground = fillColor(theme)

        for cell in 0..<barWidth {
            painter.set(
                TerminalCell(character: cell < filled ? "█" : "░", style: cell < filled ? fill : theme.placeholder),
                at: Point(x: x + cell, y: 0)
            )
        }

        if !valueText.isEmpty {
            painter.write(valueText, at: Point(x: x + barWidth + (barWidth > 0 ? 1 : 0), y: 0), style: theme.base)
        }
    }

    // MARK: - Vector

    private func drawVector(_ painter: Painter, chrome: ChromeSurface, theme: ResolvedTheme, backing: ChromeColor, ink: ChromeColor, track: ChromeColor) {
        // Cells go transparent so the ring shows through; the value label
        // sits on top as real text.
        painter.withBase(CellStyle()).fill(bounds, with: .blank)
        chrome.rect("backing", ChromeRect(bounds), fill: backing)

        let height = Double(bounds.size.height)
        let radius = height / 2 - 0.3
        let center = ChromePoint(x: Double(bounds.size.width) / 2, y: height / 2)
        let hole = radius * 0.62

        // The dial is a 270° arc open at the bottom; the ring goes all the way round.
        let sweep = style == .dial ? 1.5 * Double.pi : 2 * Double.pi
        let start = style == .dial ? -0.75 * Double.pi : 0
        let end = start + sweep * max(0, min(1, fraction))

        chrome.sector("track", center: center, radius: radius, start: start, end: start + sweep, fill: track)

        if end > start {
            chrome.sector("fill", center: center, radius: radius, start: start, end: end, fill: ink)
        }

        chrome.sector("hole", center: center, radius: hole, start: 0, end: 2 * Double.pi, fill: backing)

        if showsValue {
            let text = formatter(value)
            let x = max(0, (bounds.size.width - text.count) / 2)
            painter.write(text, at: Point(x: x, y: bounds.size.height / 2), style: theme.base)
        }

        if !label.isEmpty, bounds.size.height >= 5 {
            let text = Label.truncated(label, width: bounds.size.width)
            painter.write(text, at: Point(x: max(0, (bounds.size.width - text.count) / 2), y: bounds.size.height - 1), style: theme.base)
        }
    }
}
