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

    /// Draws the newest values that fit, one column each — as smooth vector
    /// bars on a VTG terminal (fractional heights instead of eight block
    /// levels), as glyphs everywhere else. Set
    /// ``TUIView/suppressesVectorChrome`` to pin the glyph rendering on any
    /// terminal.
    public override func draw(_ painter: Painter) {
        let width = bounds.size.width

        guard width > 0, !values.isEmpty else {
            return
        }

        let visible = values.suffix(width)
        let low = range?.lowerBound ?? visible.min() ?? 0
        let high = range?.upperBound ?? visible.max() ?? 0
        let span = high - low

        let theme = effectiveTheme
        let cellStyle = style ?? CellStyle(foreground: theme.chartData(0))

        // Height fraction for one value; flat (or floor-clamped) stays a
        // visible baseline — flat is an answer.
        func fraction(of value: Double) -> Double {
            span > 0 ? (min(max(value, low), high) - low) / span : 0
        }

        // The vector rendering: a backing in the surface colour, then one
        // sub-cell-precise bar per column. Only when every colour has real
        // RGB — a colourless theme keeps glyphs.
        if let chrome = painter.chrome, chrome.covers(bounds),
           let ink = ChromeColor(cellStyle.foreground),
           let backing = ChromeColor(theme.background) {
            chrome.rect("backing", ChromeRect(bounds), fill: backing)

            let transparent = painter.withBase(CellStyle())
            transparent.fill(bounds, with: .blank)

            for (column, value) in visible.enumerated() {
                let height = max(0.1, fraction(of: value) * 0.9)
                chrome.rect(
                    "bar-\(column)",
                    ChromeRect(x: Double(column) + 0.1, y: 0.95 - height, width: 0.8, height: height),
                    fill: ink,
                    radius: 0.07,
                    corners: .top
                )
            }

            return
        }

        let levels = fidelity == .ascii ? Self.asciiLevels : Self.blockLevels

        for (column, value) in visible.enumerated() {
            let level = Int((fraction(of: value) * Double(levels.count - 1)).rounded())
            painter.set(
                TerminalCell(character: levels[level], style: cellStyle),
                at: Point(x: column, y: 0)
            )
        }
    }
}

/// Shared chart arithmetic (internal): the pieces every chart needs and
/// none should re-derive.
enum ChartMath {
    /// The largest 1/2/5×10^k step giving at most `maximumTicks` intervals —
    /// round tick values, not whatever divides the pixel count.
    static func niceStep(span: Double, maximumTicks: Int) -> Double {
        let rough = span / Double(max(1, maximumTicks))
        var magnitude = 1.0

        if rough > 0 {
            // The largest power of ten not above `rough`, without libm.
            while magnitude < rough { magnitude *= 10 }
            while magnitude > rough { magnitude /= 10 }
        }

        for multiplier in [1.0, 2.0, 5.0, 10.0] where magnitude * multiplier >= rough {
            return magnitude * multiplier
        }

        return magnitude * 10
    }
}
