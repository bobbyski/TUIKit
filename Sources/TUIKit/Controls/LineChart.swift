// R11 — `LineChart`: one or more series over time, with labelled axes.
// The hard part is the axis, not the line: round tick values, labels that
// fit the gutter, and a fitted domain that rounds out to tick multiples so
// it does not jitter as points arrive.

import Foundation

/// A value over time, with axes — when a ``Sparkline`` answers "which way",
/// this answers "when".
///
/// ```text
///    40MB ┤                                   ╭──
///         │                            ╭──────╯
///    20MB ┤        ╭───────────────────╯
///         │────────╯
///     0MB ┼────┬────┬────┬────┬────┬────┬────┬───
///         0s   30s  60s  90s  120s 150s 180s
/// ```
///
/// Fidelity: `.blocks` (default) draws with box-drawing segments chosen from
/// the slope; `.ascii` plots `*` per column joined by `|`; `.braille` plots
/// at 2×4 subcells per cell for callers that know their terminal has it.
@MainActor
public final class LineChart: TUIView {
    /// One plotted series: evenly spaced samples, oldest first.
    public struct Series: Sendable {
        /// Name shown in the legend.
        public var label: String

        /// The samples, spaced evenly across ``LineChart/xDomain``.
        public var values: [Double]

        /// Colour override; `nil` takes the next default (accent, warning
        /// accent, error accent, foreground — cycling).
        public var style: CellStyle?

        /// Whether the region under the line fills — the area-chart reading
        /// (`AUIAreaMark`'s shape). Solid blocks in the series colour on
        /// cells; a translucent polygon under the trace on a VTG terminal.
        public var fillsArea = false

        /// Creates a series.
        public init(label: String, values: [Double], style: CellStyle? = nil, fillsArea: Bool = false) {
            self.label = label
            self.values = values
            self.style = style
            self.fillsArea = fillsArea
        }
    }

    /// The plotted series, drawn in order (later series overdraw earlier).
    public var series: [Series] {
        didSet {
            setNeedsDisplay()
        }
    }

    /// What the x axis spans. `nil` labels sample indices (0…count−1).
    public var xDomain: ClosedRange<Double>? {
        didSet {
            if xDomain != oldValue {
                setNeedsDisplay()
            }
        }
    }

    /// What the y axis spans. `nil` fits the data, rounded OUT to tick
    /// multiples — so a chart receiving live samples does not relabel its
    /// axis every time a value creeps past the previous maximum.
    public var yDomain: ClosedRange<Double>? {
        didSet {
            if yDomain != oldValue {
                setNeedsDisplay()
            }
        }
    }

    /// Glyph alphabet — `.blocks` (default), `.ascii`, or opt-in `.braille`.
    public var fidelity: ChartFidelity = .blocks {
        didSet {
            if fidelity != oldValue {
                setNeedsDisplay()
            }
        }
    }

    /// Formats a y-axis tick. Defaults to a bare trimmed number; a memory
    /// chart sets `{ "\(Int($0 / 1_048_576))MB" }`.
    public var yFormatter: (Double) -> String = { value in
        value == value.rounded() ? String(Int(value)) : String(value)
    } {
        didSet {
            setNeedsDisplay()
        }
    }

    /// Formats an x-axis tick. Same default as ``yFormatter``.
    public var xFormatter: (Double) -> String = { value in
        value == value.rounded() ? String(Int(value)) : String(value)
    } {
        didSet {
            setNeedsDisplay()
        }
    }

    /// Whether the first row names each series in its colour.
    public var showsLegend = false {
        didSet {
            if showsLegend != oldValue {
                setNeedsDisplay()
            }
        }
    }

    /// Creates a line chart.
    ///
    /// - Parameter series: The plotted series.
    public init(series: [Series] = []) {
        self.series = series
        super.init(frame: .zero)
    }

    /// A natural minimum; hosts normally size a chart with anchors.
    public override var intrinsicContentSize: Size? {
        Size(width: 32, height: 8)
    }

    // MARK: - Domains

    // The fitted-and-rounded y range plus its tick step. Fitting rounds the
    // bounds OUT to step multiples (axis stability); an explicit domain is
    // honoured exactly.
    private func resolvedYDomain(plotRows: Int) -> (domain: ClosedRange<Double>, step: Double) {
        var low: Double
        var high: Double

        if let yDomain {
            low = yDomain.lowerBound
            high = yDomain.upperBound
        } else {
            low = series.flatMap(\.values).min() ?? 0
            high = series.flatMap(\.values).max() ?? 1
        }

        if high <= low {
            high = low + 1
        }

        let step = niceStep(span: high - low, maximumTicks: max(2, plotRows / 2))

        if yDomain == nil {
            low = (low / step).rounded(.down) * step
            high = (high / step).rounded(.up) * step
        }

        return (low...high, step)
    }

    private var resolvedXDomain: ClosedRange<Double> {
        if let xDomain {
            return xDomain
        }

        let count = series.map(\.values.count).max() ?? 0
        return 0...Double(max(1, count - 1))
    }

    // The largest 1/2/5×10^k step giving at most `maximumTicks` intervals.
    private func niceStep(span: Double, maximumTicks: Int) -> Double {
        ChartMath.niceStep(span: span, maximumTicks: maximumTicks)
    }

    // MARK: - Drawing

    /// Draws the legend, the y gutter and axis, the plot, and the x axis.
    public override func draw(_ painter: Painter) {
        painter.fill(bounds, with: .blank)

        let theme = effectiveTheme
        let width = bounds.size.width
        let height = bounds.size.height

        let legendRows = showsLegend ? 1 : 0
        let axisRows = 2   // the ┼──┬── rule plus its labels
        let plotRows = height - legendRows - axisRows

        guard plotRows >= 2, width > 8 else {
            return
        }

        let (domain, step) = resolvedYDomain(plotRows: plotRows)

        // Gutter: wide enough for the widest tick label plus the axis line.
        var tickValues: [Double] = []
        var tick = (domain.lowerBound / step).rounded(.up) * step
        while tick <= domain.upperBound + step / 2 {
            tickValues.append(tick)
            tick += step
        }

        let gutter = (tickValues.map { DisplayWidth.of(yFormatter($0)) }.max() ?? 1) + 1
        let plotWidth = width - gutter - 1

        guard plotWidth > 2 else {
            return
        }

        if showsLegend {
            drawLegend(painter, theme: theme)
        }

        let plotTop = legendRows
        let axisColumn = gutter

        // Row for a value: top row is the domain's top.
        func row(of value: Double) -> Int {
            let clamped = min(max(value, domain.lowerBound), domain.upperBound)
            let fraction = (clamped - domain.lowerBound) / (domain.upperBound - domain.lowerBound)
            return plotTop + (plotRows - 1) - Int((fraction * Double(plotRows - 1)).rounded())
        }

        // The y axis: `│` down the rule, `┤` at labelled ticks, `┼` where it
        // meets the x axis.
        let axisStyle = theme.border
        let labelStyle = theme.chartDeemphasis

        for line in 0..<plotRows {
            painter.set(
                TerminalCell(character: fidelity == .ascii ? "|" : "│", style: axisStyle),
                at: Point(x: axisColumn, y: plotTop + line)
            )
        }

        for value in tickValues {
            let y = row(of: value)
            painter.set(
                TerminalCell(character: fidelity == .ascii ? "+" : "┤", style: axisStyle),
                at: Point(x: axisColumn, y: y)
            )

            // Right-aligned, ending just before the axis rule.
            let label = yFormatter(value)
            painter.write(label, at: Point(x: max(0, gutter - label.count), y: y), style: labelStyle)
        }

        drawXAxis(
            painter,
            atRow: plotTop + plotRows,
            axisColumn: axisColumn,
            plotWidth: plotWidth,
            theme: theme
        )

        // The series, in declared order. On a VTG terminal each trace is one
        // smooth vector polyline over a backing in the surface colour —
        // genuinely diagonal lines instead of box-drawing steps; the axes
        // and labels stay native text. Only when every colour involved has
        // real RGB; `suppressesVectorChrome` (or a colourless theme) keeps
        // the glyph rendering below.
        if let chrome = painter.chrome,
           let backing = ChromeColor(theme.background),
           let inks = vectorInks(theme: theme) {
            let plotArea = Rect(x: axisColumn + 1, y: plotTop, width: plotWidth, height: plotRows)
            chrome.rect("backing", ChromeRect(plotArea), fill: backing)

            let transparent = painter.withBase(CellStyle())
            transparent.fill(plotArea, with: .blank)

            for (index, oneSeries) in series.enumerated() where oneSeries.values.count >= 1 {
                drawVectorTrace(
                    oneSeries, key: "trace-\(index)", ink: inks[index],
                    plotLeft: axisColumn + 1, plotTop: plotTop,
                    plotWidth: plotWidth, plotRows: plotRows,
                    domain: domain, chrome: chrome
                )
            }

            return
        }

        // Cell-mode area fills paint FIRST (solid blocks under each line),
        // so every series' line stays on top of every fill.
        for (index, oneSeries) in series.enumerated() where oneSeries.fillsArea && oneSeries.values.count >= 1 {
            let style = oneSeries.style ?? defaultStyle(at: index, theme: theme)
            let bottom = plotTop + plotRows

            for column in 0..<plotWidth {
                let top = row(of: sample(oneSeries.values, at: column, plotWidth: plotWidth))

                for y in (top + 1)..<bottom {
                    painter.set(
                        TerminalCell(character: fidelity == .ascii ? "#" : "█", style: style),
                        at: Point(x: axisColumn + 1 + column, y: y)
                    )
                }
            }
        }

        for (index, oneSeries) in series.enumerated() where oneSeries.values.count >= 1 {
            let style = oneSeries.style ?? defaultStyle(at: index, theme: theme)

            switch fidelity {
            case .braille:
                drawBraille(oneSeries, style: style, plotLeft: axisColumn + 1, plotTop: plotTop,
                            plotWidth: plotWidth, plotRows: plotRows, domain: domain, painter: painter)

            case .ascii, .blocks:
                drawLine(oneSeries, style: style, plotLeft: axisColumn + 1,
                         plotWidth: plotWidth, rowOf: row(of:), painter: painter)
            }
        }
    }

    // Every series' ink as real RGB, or nil when any falls short (one
    // glyph-drawn series beside vector ones would misalign the story).
    private func vectorInks(theme: ResolvedTheme) -> [ChromeColor]? {
        var inks: [ChromeColor] = []

        for (index, oneSeries) in series.enumerated() {
            let style = oneSeries.style ?? defaultStyle(at: index, theme: theme)

            guard let ink = ChromeColor(style.foreground) else {
                return nil
            }

            inks.append(ink)
        }

        return inks
    }

    // One series as a single retained polyline, sampled at two points per
    // column for smooth slopes.
    private func drawVectorTrace(
        _ oneSeries: Series,
        key: String,
        ink: ChromeColor,
        plotLeft: Int,
        plotTop: Int,
        plotWidth: Int,
        plotRows: Int,
        domain: ClosedRange<Double>,
        chrome: ChromeSurface
    ) {
        let samples = max(2, plotWidth * 2)
        let top = Double(plotTop) + 0.15
        let bottom = Double(plotTop + plotRows) - 0.15
        var points: [ChromePoint] = []

        for sampleIndex in 0..<samples {
            let progress = Double(sampleIndex) / Double(samples - 1)
            let value = sample(oneSeries.values, at: sampleIndex, plotWidth: samples)
            let clamped = min(max(value, domain.lowerBound), domain.upperBound)
            let fraction = (clamped - domain.lowerBound) / (domain.upperBound - domain.lowerBound)

            points.append(ChromePoint(
                x: Double(plotLeft) + progress * (Double(plotWidth) - 0.4) + 0.2,
                y: bottom - fraction * (bottom - top)
            ))
        }

        // The area reading: a translucent polygon closed along the axis,
        // under its own trace.
        if oneSeries.fillsArea, let first = points.first, let last = points.last {
            var fill = ink
            fill.alpha = 90

            chrome.polygon(
                key + "-area",
                points: points + [
                    ChromePoint(x: last.x, y: bottom),
                    ChromePoint(x: first.x, y: bottom),
                ],
                fill: fill
            )
        }

        chrome.polyline(key, points: points, color: ink, width: 0.09)
    }

    private func defaultStyle(at index: Int, theme: ResolvedTheme) -> CellStyle {
        CellStyle(foreground: theme.chartData(index))
    }

    private func drawLegend(_ painter: Painter, theme: ResolvedTheme) {
        var x = 0

        for (index, oneSeries) in series.enumerated() {
            let style = oneSeries.style ?? defaultStyle(at: index, theme: theme)
            let marker = fidelity == .ascii ? "*" : "━"
            painter.write("\(marker) \(oneSeries.label)  ", at: Point(x: x, y: 0), style: style)
            x += DisplayWidth.of(oneSeries.label) + 4
        }
    }

    // The bottom rule (`┼────┬────┬──`) and its label row.
    private func drawXAxis(
        _ painter: Painter,
        atRow y: Int,
        axisColumn: Int,
        plotWidth: Int,
        theme: ResolvedTheme
    ) {
        let axisStyle = theme.border
        let labelStyle = theme.chartDeemphasis
        let domain = resolvedXDomain
        let span = domain.upperBound - domain.lowerBound

        painter.set(
            TerminalCell(character: fidelity == .ascii ? "+" : "┼", style: axisStyle),
            at: Point(x: axisColumn, y: y)
        )

        for x in 1...plotWidth {
            painter.set(
                TerminalCell(character: fidelity == .ascii ? "-" : "─", style: axisStyle),
                at: Point(x: axisColumn + x, y: y)
            )
        }

        guard span > 0 else {
            return
        }

        let step = niceStep(span: span, maximumTicks: max(2, plotWidth / 8))
        var tick = (domain.lowerBound / step).rounded(.up) * step
        var lastLabelEnd = -1

        while tick <= domain.upperBound {
            let column = axisColumn + 1 + Int(((tick - domain.lowerBound) / span * Double(plotWidth - 1)).rounded())

            painter.set(
                TerminalCell(character: fidelity == .ascii ? "+" : "┬", style: axisStyle),
                at: Point(x: column, y: y)
            )

            let label = xFormatter(tick)

            if column > lastLabelEnd, column + label.count <= bounds.size.width {
                painter.write(label, at: Point(x: column, y: y + 1), style: labelStyle)
                lastLabelEnd = column + label.count + 1
            }

            tick += step
        }
    }

    // The value at a plot column, linearly interpolated between samples.
    private func sample(_ values: [Double], at column: Int, plotWidth: Int) -> Double {
        guard values.count > 1 else {
            return values.first ?? 0
        }

        let position = Double(column) / Double(max(1, plotWidth - 1)) * Double(values.count - 1)
        let index = Int(position)
        let next = min(index + 1, values.count - 1)
        let fraction = position - Double(index)
        return values[index] + (values[next] - values[index]) * fraction
    }

    // `.blocks`: box-drawing segments chosen from the slope between adjacent
    // columns (`─ ╭ ╮ ╰ ╯ │`); `.ascii`: `*` per column, `|` bridging jumps.
    private func drawLine(
        _ oneSeries: Series,
        style: CellStyle,
        plotLeft: Int,
        plotWidth: Int,
        rowOf: (Double) -> Int,
        painter: Painter
    ) {
        let ascii = fidelity == .ascii
        var previousRow: Int?

        for column in 0..<plotWidth {
            let currentRow = rowOf(sample(oneSeries.values, at: column, plotWidth: plotWidth))
            let x = plotLeft + column

            defer {
                previousRow = currentRow
            }

            guard let previousRow, previousRow != currentRow, !ascii else {
                painter.set(
                    TerminalCell(character: ascii ? "*" : "─", style: style),
                    at: Point(x: x, y: currentRow)
                )

                // Bridge a multi-row jump so the ASCII line stays connected.
                if ascii, let previousRow, abs(previousRow - currentRow) > 1 {
                    for y in Swift.min(previousRow, currentRow) + 1..<Swift.max(previousRow, currentRow) {
                        painter.set(TerminalCell(character: "|", style: style), at: Point(x: x, y: y))
                    }
                }

                continue
            }

            // A turn: leave the previous row and arrive at the new one, with
            // verticals between. Rising (smaller row = higher) turns ╯ then
            // ╭; falling turns ╮ then ╰.
            let rising = currentRow < previousRow
            painter.set(
                TerminalCell(character: rising ? "╯" : "╮", style: style),
                at: Point(x: x, y: previousRow)
            )
            painter.set(
                TerminalCell(character: rising ? "╭" : "╰", style: style),
                at: Point(x: x, y: currentRow)
            )

            for y in Swift.min(previousRow, currentRow) + 1..<Swift.max(previousRow, currentRow) {
                painter.set(TerminalCell(character: "│", style: style), at: Point(x: x, y: y))
            }
        }
    }

    // `.braille`: 2×4 subcells per cell. Dot bits per (subcolumn, subrow).
    private static let brailleBits: [[UInt32]] = [
        [0x01, 0x02, 0x04, 0x40],   // left column, top to bottom
        [0x08, 0x10, 0x20, 0x80],   // right column
    ]

    private func drawBraille(
        _ oneSeries: Series,
        style: CellStyle,
        plotLeft: Int,
        plotTop: Int,
        plotWidth: Int,
        plotRows: Int,
        domain: ClosedRange<Double>,
        painter: Painter
    ) {
        let subWidth = plotWidth * 2
        let subHeight = plotRows * 4
        var cells: [Point: UInt32] = [:]

        var previous: (x: Int, y: Int)?

        for subColumn in 0..<subWidth {
            let value = sample(oneSeries.values, at: subColumn, plotWidth: subWidth)
            let clamped = min(max(value, domain.lowerBound), domain.upperBound)
            let fraction = (clamped - domain.lowerBound) / (domain.upperBound - domain.lowerBound)
            let subRow = (subHeight - 1) - Int((fraction * Double(subHeight - 1)).rounded())

            // Connect to the previous subcolumn so steep slopes stay a line
            // rather than scattered dots.
            let from = previous ?? (subColumn, subRow)

            for y in Swift.min(from.y, subRow)...Swift.max(from.y, subRow) {
                let cell = Point(x: plotLeft + subColumn / 2, y: plotTop + y / 4)
                cells[cell, default: 0] |= Self.brailleBits[subColumn % 2][y % 4]
            }

            previous = (subColumn, subRow)
        }

        for (cell, bits) in cells {
            guard let scalar = Unicode.Scalar(0x2800 + bits) else {
                continue
            }

            painter.set(TerminalCell(character: Character(scalar), style: style), at: cell)
        }
    }
}
