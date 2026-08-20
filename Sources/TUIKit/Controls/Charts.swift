// Charts (REQUESTS R9–R11): the shared fidelity model and `Sparkline`.
// `TimelineChart` and `LineChart` live in their own files.
//
// The governing rule: cells first, VTG optional. Every chart renders
// completely on a plain ANSI terminal; the fidelity levels below choose the
// glyph alphabet, and `.ascii` is the floor every chart must stay readable
// at. Colours come from theme slots, never literals — a chart that hardcodes
// green is unreadable in Turbo and invisible in Mono.

/// Which glyph alphabet a chart draws with.
public enum ChartFidelity: Hashable, Sendable {
    /// Unicode block elements (`▁▂▃▄▅▆▇█`, `━`). The default: single-width
    /// everywhere, and present in every font that can render a TUI at all.
    case blocks

    /// Plain ASCII (`# = - | . *`). The floor: every chart must be readable
    /// here, for fonts without block coverage — and it is never chosen
    /// automatically, only asked for.
    case ascii

    /// Braille patterns (`⠀`–`⣿`), 2×4 subcells per cell. Opt-in only, for
    /// ``LineChart``: coverage is not universal, so it is never the default.
    case braille
}

/// A series in one row: shape and direction at a glance, no axes, no labels.
///
/// ```text
///    DOM nodes    1,284  ▁▁▂▂▃▃▄▅▆▇█▇▆▅
///    Image bytes  2.1 MB ▂▂▂▂▂▂▂▂▂▂▂▂▂▂     ← flat: not the leak
/// ```
///
/// One column per value; when there are more values than columns the most
/// *recent* ones show — a sparkline is a trend, and the newest end is the
/// one being read. It is a glyph, not a control: it takes no focus and no
/// input.
@MainActor
public final class Sparkline: TUIView {
    /// The series, oldest first.
    public var values: [Double] {
        didSet {
            if values != oldValue {
                superview?.setNeedsLayout()
                setNeedsDisplay()
            }
        }
    }

    /// Glyph alphabet. `.blocks` (the default) or `.ascii`; `.braille` is
    /// not meaningful for a one-row bar and draws as `.blocks`.
    public var fidelity: ChartFidelity = .blocks {
        didSet {
            if fidelity != oldValue {
                setNeedsDisplay()
            }
        }
    }

    /// The value range the row spans. `nil` (the default) fits the data, so
    /// the smallest value sits on the baseline and the largest tops out; set
    /// it to keep several sparklines comparable on one scale.
    public var range: ClosedRange<Double>? {
        didSet {
            if range != oldValue {
                setNeedsDisplay()
            }
        }
    }

    /// Colour override. `nil` (the default) draws in the theme's accent.
    public var style: CellStyle? {
        didSet {
            if style != oldValue {
                setNeedsDisplay()
            }
        }
    }

    /// Creates a sparkline.
    ///
    /// - Parameter values: The series, oldest first.
    public init(values: [Double] = []) {
        self.values = values
        super.init(frame: .zero)
    }

    /// One row, one column per value.
    public override var intrinsicContentSize: Size? {
        Size(width: max(1, values.count), height: 1)
    }

    // The quantisation alphabets, lowest to highest. All single-width
    // (locked by a test): a double-width glyph would shift every column
    // after it and silently misplot the data.
    nonisolated static let blockLevels: [Character] = ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]
    nonisolated static let asciiLevels: [Character] = ["_", ".", "-", "=", "*", "#"]

    /// Draws the newest values that fit, one column each.
    public override func draw(_ painter: Painter) {
        let width = bounds.size.width

        guard width > 0, !values.isEmpty else {
            return
        }

        let visible = values.suffix(width)
        let low = range?.lowerBound ?? visible.min() ?? 0
        let high = range?.upperBound ?? visible.max() ?? 0
        let span = high - low

        let levels = fidelity == .ascii ? Self.asciiLevels : Self.blockLevels

        let theme = effectiveTheme
        let cellStyle = style ?? CellStyle(foreground: theme.accent)

        for (column, value) in visible.enumerated() {
            // A flat series (or one clamped at the floor) reads as the
            // baseline glyph, not as empty cells: flat is an answer.
            let fraction = span > 0 ? (min(max(value, low), high) - low) / span : 0
            let level = Int((fraction * Double(levels.count - 1)).rounded())
            painter.set(
                TerminalCell(character: levels[level], style: cellStyle),
                at: Point(x: column, y: 0)
            )
        }
    }
}
