/// Progress display: a determinate bar or an indeterminate spinner.
///
/// ```text
///   ████████████░░░░░░░░  60%     .bar, determinate (fraction of the range)
///   ⠿ Loading…                    .spinner, indeterminate (advances on tick)
/// ```
///
/// The bar fills the theme's accent over a dim track and can show a trailing
/// `NN%` label. The spinner is a single glyph that advances one frame each
/// time `advance()` is called; wire it to an `App` timer so it animates
/// without blocking:
///
/// ```swift
/// let spinner = ProgressIndicator(style: .spinner)
/// spinner.caption = "Building…"
/// let tick = app.addTimer(every: .milliseconds(120)) { spinner.advance() }
/// // ... later, when work finishes ...
/// tick.cancel()
/// ```
///
/// Progress indicators are display-only: they never take focus and handle no
/// input.
@MainActor
public final class ProgressIndicator: TUIView {
    /// Presentation modes.
    public enum Style: Sendable {
        /// Determinate bar filled to `fractionCompleted`.
        case bar

        /// Indeterminate spinner advancing one glyph per tick.
        case spinner
    }

    /// Presentation mode.
    public var style: Style {
        didSet {
            if style != oldValue {
                superview?.setNeedsLayout()
                setNeedsDisplay()
            }
        }
    }

    /// Lowest value the bar represents.
    public var minValue: Double {
        didSet {
            if minValue != oldValue {
                storedValue = clamped(storedValue)
                setNeedsDisplay()
            }
        }
    }

    /// Highest value the bar represents.
    public var maxValue: Double {
        didSet {
            if maxValue != oldValue {
                storedValue = clamped(storedValue)
                setNeedsDisplay()
            }
        }
    }

    /// Current bar value, clamped into `minValue...maxValue`.
    public var doubleValue: Double {
        get { storedValue }
        set {
            let clampedValue = clamped(newValue)

            if clampedValue != storedValue {
                storedValue = clampedValue
                setNeedsDisplay()
            }
        }
    }

    /// Bar completion as a fraction `0...1`.
    public var fractionCompleted: Double {
        guard maxValue > minValue else {
            return 0
        }

        return (storedValue - minValue) / (maxValue - minValue)
    }

    /// Whether the bar shows a trailing `NN%` label.
    public var showsPercentage: Bool {
        didSet {
            if showsPercentage != oldValue {
                setNeedsDisplay()
            }
        }
    }

    /// Text drawn after the spinner glyph (spinner style).
    public var caption: String {
        didSet {
            if caption != oldValue {
                superview?.setNeedsLayout()
                setNeedsDisplay()
            }
        }
    }

    /// Spinner glyphs cycled by `advance()`.
    public var spinnerFrames: [Character] = ["|", "/", "-", "\\"] {
        didSet {
            spinnerIndex = spinnerFrames.isEmpty ? 0 : spinnerIndex % spinnerFrames.count
            setNeedsDisplay()
        }
    }

    private var storedValue: Double
    private var spinnerIndex = 0

    /// Creates a progress indicator.
    ///
    /// - Parameters:
    ///   - style: Bar or spinner.
    ///   - value: Initial bar value.
    ///   - minValue: Lowest bar value.
    ///   - maxValue: Highest bar value.
    public init(
        style: Style = .bar,
        value: Double = 0,
        minValue: Double = 0,
        maxValue: Double = 1
    ) {
        self.style = style
        self.minValue = minValue
        self.maxValue = maxValue
        self.storedValue = min(max(minValue, value), maxValue)
        self.showsPercentage = false
        self.caption = ""
        super.init(frame: .zero)
    }

    /// One row; a comfortable bar width, or the spinner plus its caption.
    public override var intrinsicContentSize: Size? {
        switch style {
        case .bar:
            return Size(width: 20, height: 1)

        case .spinner:
            let captionWidth = caption.isEmpty ? 0 : caption.count + 1
            return Size(width: 1 + captionWidth, height: 1)
        }
    }

    /// The current spinner glyph, when in spinner style.
    public var currentSpinnerGlyph: Character? {
        guard style == .spinner, !spinnerFrames.isEmpty else {
            return nil
        }

        return spinnerFrames[spinnerIndex % spinnerFrames.count]
    }

    /// Advances the spinner one frame (a no-op for the bar style).
    ///
    /// Typically called from an `App` timer; safe to call directly in tests.
    public func advance() {
        guard style == .spinner, !spinnerFrames.isEmpty else {
            return
        }

        spinnerIndex = (spinnerIndex + 1) % spinnerFrames.count
        setNeedsDisplay()
    }

    /// Draws the bar or spinner.
    public override func draw(_ painter: Painter) {
        switch style {
        case .bar:
            drawBar(painter)

        case .spinner:
            drawSpinner(painter)
        }
    }

    // MARK: - Drawing

    private func drawBar(_ painter: Painter) {
        let width = bounds.size.width

        guard width > 0 else {
            return
        }

        let theme = effectiveTheme
        let label = showsPercentage ? " \(percentString)" : ""
        let trackWidth = max(0, width - label.count)
        let (trackStyle, fillStyle) = Self.barStyles(for: theme)
        let filled = Int((fractionCompleted * Double(trackWidth)).rounded())

        // Solid cells only — a blank painted on a background color, never a
        // shaded glyph. The track is a filled dim bar; the fill is the accent.
        for x in 0..<trackWidth {
            let isFilled = x < filled
            painter.set(
                TerminalCell(character: " ", style: isFilled ? fillStyle : trackStyle),
                at: Point(x: x, y: 0)
            )
        }

        if !label.isEmpty {
            painter.write(label, at: Point(x: trackWidth, y: 0), style: CellStyle())
        }
    }

    // Solid track/fill styles — background colors only, never glyph patterns,
    // mirroring ScrollView's indicator styling and its colorless fallback.
    static func barStyles(for theme: ResolvedTheme) -> (track: CellStyle, fill: CellStyle) {
        let slot = theme.scrollbar

        guard slot.foreground != .standard, slot.background != .standard else {
            // Colorless theme (e.g. mono): solid video-attribute blocks.
            var track = theme.border
            track.flags.insert(.inverse)
            track.flags.insert(.dim)

            var fill = theme.border
            fill.flags.insert(.inverse)
            return (track, fill)
        }

        let track = CellStyle(background: slot.background)
        let fill = CellStyle(background: theme.accent != .standard ? theme.accent : slot.foreground)
        return (track, fill)
    }

    private func drawSpinner(_ painter: Painter) {
        guard let glyph = currentSpinnerGlyph else {
            return
        }

        let theme = effectiveTheme
        var glyphStyle = CellStyle()

        if theme.accent != .standard {
            glyphStyle.foreground = theme.accent
        }

        painter.set(TerminalCell(character: glyph, style: glyphStyle), at: .zero)

        if !caption.isEmpty, bounds.size.width > 2 {
            let text = Label.truncated(caption, width: bounds.size.width - 2)
            painter.write(text, at: Point(x: 2, y: 0), style: CellStyle())
        }
    }

    // Integer percentage, `0` to `100`.
    private var percentString: String {
        "\(Int((fractionCompleted * 100).rounded()))%"
    }

    private func clamped(_ candidate: Double) -> Double {
        guard maxValue > minValue else {
            return minValue
        }

        return min(max(minValue, candidate), maxValue)
    }
}
