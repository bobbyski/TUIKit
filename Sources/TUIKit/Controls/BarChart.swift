// `BarChart` — categories against magnitudes, the ActiveUI `AUIBarMark`
// shape on the TUI side. Cells first, VTG optional, colors from the
// chartData palette (with per-series overrides), like every chart here.

/// Vertical bars per category, grouped when there are several series.
///
/// ```text
///    12 ┤        ▂█
///     8 ┤   ▄█   ██   ▆█
///     4 ┤   ██   ██   ██   ▂█
///     0 ┼───██───██───██───██──
///          Mon  Tue  Wed  Thu
/// ```
///
/// Bars answer "which is biggest" (use ``PieChart`` only for "what share
/// of the whole"). Values are magnitudes: the baseline is always zero and
/// negatives clamp to it. On a VTG terminal bars render as rounded
/// sub-cell-precise blocks; ``TUIView/suppressesVectorChrome`` pins glyphs.
@MainActor
public final class BarChart: TUIView {
    /// One plotted series: a value per category.
    public struct Series: Sendable {
        /// Name shown in the legend.
        public var label: String

        /// One magnitude per category (missing trailing entries read 0).
        public var values: [Double]

        /// Colour override; `nil` takes the theme's ``ResolvedTheme/chartData(_:)``.
        public var style: CellStyle?

        /// Creates a series.
        public init(label: String, values: [Double], style: CellStyle? = nil) {
            self.label = label
            self.values = values
            self.style = style
        }
    }

    /// Category names, drawn under their groups.
    public var categories: [String] {
        didSet {
            setNeedsDisplay()
        }
    }

    /// The plotted series — one bar per category each, grouped side by side.
    public var series: [Series] {
        didSet {
            setNeedsDisplay()
        }
    }

    /// The value axis's top. `nil` fits the data, rounded OUT to a tick
    /// multiple so live values do not relabel the axis. The bottom is
    /// always zero — bars without a zero baseline lie.
    public var maximumValue: Double? {
        didSet {
            if maximumValue != oldValue {
                setNeedsDisplay()
            }
        }
    }

    /// Glyph alphabet: `.blocks` (default) or `.ascii`.
    public var fidelity: ChartFidelity = .blocks {
        didSet {
            if fidelity != oldValue {
                setNeedsDisplay()
            }
        }
    }

    /// Formats a value-axis tick. Defaults to a bare trimmed number.
    public var yFormatter: (Double) -> String = { value in
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

    /// Creates a bar chart.
    public init(categories: [String] = [], series: [Series] = []) {
        self.categories = categories
        self.series = series
        super.init(frame: .zero)
    }

    /// A natural minimum; hosts normally size a chart with anchors.
    public override var intrinsicContentSize: Size? {
        Size(width: 24, height: 8)
    }

    // MARK: - Drawing

    public override func draw(_ painter: Painter) {
        painter.fill(bounds, with: .blank)

        let theme = effectiveTheme
        let legendRows = showsLegend ? 1 : 0
        let axisRows = 2   // the baseline rule plus category labels
        let plotRows = bounds.size.height - legendRows - axisRows

        guard plotRows >= 2, !categories.isEmpty, !series.isEmpty else {
            return
        }

        // Domain: zero up to the fitted-or-given maximum, rounded out.
        let peak = max(maximumValue ?? 0, series.flatMap(\.values).max() ?? 0, 1)
        let step = ChartMath.niceStep(span: peak, maximumTicks: max(2, plotRows / 2))
        let top = maximumValue ?? (peak / step).rounded(.up) * step

        // Ticks size the gutter.
        var tickValues: [Double] = []
        var tick = 0.0
        while tick <= top + step / 2 {
            tickValues.append(tick)
            tick += step
        }

        let gutter = (tickValues.map { DisplayWidth.of(yFormatter($0)) }.max() ?? 1) + 1
        let plotLeft = gutter + 1
        let plotWidth = bounds.size.width - plotLeft

        guard plotWidth >= categories.count else {
            return
        }

        if showsLegend {
            drawLegend(painter, theme: theme)
        }

        let plotTop = legendRows
        let baseline = plotTop + plotRows   // the axis row

        drawAxis(
            painter, theme: theme, tickValues: tickValues, top: top,
            gutter: gutter, plotTop: plotTop, plotRows: plotRows, baseline: baseline, plotWidth: plotWidth
        )

        // Group geometry: one column per series per category, two blank
        // columns between groups (room for three-letter category labels to
        // breathe), extra leftover padding at the edges.
        let groupWidth = series.count
        let spacing = 2
        let contentWidth = categories.count * groupWidth + (categories.count - 1) * spacing
        let leading = plotLeft + max(0, (plotWidth - contentWidth) / 2)

        // Vector mode is all-or-nothing: the backing AND every series ink
        // must have real RGB, or the whole chart keeps glyphs (a lone
        // glyph-drawn series among vector bars would be erased by the
        // transparent plot cells).
        let inks = series.enumerated().map { index, oneSeries in
            oneSeries.style ?? CellStyle(foreground: theme.chartData(index))
        }

        let vector: (chrome: ChromeSurface, backing: ChromeColor, fills: [ChromeColor])?

        if let chrome = painter.chrome,
           let backing = ChromeColor(theme.background),
           inks.allSatisfy({ ChromeColor($0.foreground) != nil }) {
            vector = (chrome, backing, inks.map { ChromeColor($0.foreground)! })
        } else {
            vector = nil
        }

        if let vector {
            vector.chrome.rect(
                "backing",
                ChromeRect(Rect(x: plotLeft, y: plotTop, width: plotWidth, height: plotRows)),
                fill: vector.backing
            )

            let transparent = painter.withBase(CellStyle())
            transparent.fill(Rect(x: plotLeft, y: plotTop, width: plotWidth, height: plotRows), with: .blank)
        }

        for (categoryIndex, category) in categories.enumerated() {
            let groupX = leading + categoryIndex * (groupWidth + spacing)

            // The category label, centered under its group.
            let label = Label.truncated(category, width: groupWidth + spacing + 1)
            let labelX = groupX + max(0, (groupWidth - label.count) / 2)
            painter.write(label, at: Point(x: labelX, y: baseline + 1), style: theme.chartDeemphasis)

            for (seriesIndex, oneSeries) in series.enumerated() {
                let value = categoryIndex < oneSeries.values.count ? oneSeries.values[categoryIndex] : 0
                let fraction = min(max(value, 0), top) / top
                let ink = inks[seriesIndex]
                let x = groupX + seriesIndex

                if let vector {
                    // Vector: one rounded-top block, sub-cell precise.
                    let height = fraction * (Double(plotRows) - 0.1)

                    guard height > 0.02 else {
                        continue
                    }

                    vector.chrome.rect(
                        "bar-\(categoryIndex)-\(seriesIndex)",
                        ChromeRect(
                            x: Double(x) + 0.1,
                            y: Double(baseline) - height,
                            width: 0.8,
                            height: height
                        ),
                        fill: vector.fills[seriesIndex],
                        radius: 0.15,
                        corners: .top
                    )
                    continue
                }

                // Cells: full blocks up the column, the top cell quantised
                // to a partial block (or `#` at the ascii floor).
                let cellsTall = fraction * Double(plotRows)
                let full = Int(cellsTall)
                let remainder = cellsTall - Double(full)

                for row in 0..<full {
                    painter.set(
                        TerminalCell(character: fidelity == .ascii ? "#" : "█", style: ink),
                        at: Point(x: x, y: baseline - 1 - row)
                    )
                }

                if remainder > 0.05, full < plotRows, fidelity != .ascii {
                    let levels = Sparkline.blockLevels
                    let level = max(0, min(levels.count - 1, Int(remainder * Double(levels.count)) - 1))
                    painter.set(
                        TerminalCell(character: levels[level], style: ink),
                        at: Point(x: x, y: baseline - 1 - full)
                    )
                }
            }
        }

    }

    private func drawLegend(_ painter: Painter, theme: ResolvedTheme) {
        var x = 0

        for (index, oneSeries) in series.enumerated() {
            let style = oneSeries.style ?? CellStyle(foreground: theme.chartData(index))
            let marker = fidelity == .ascii ? "#" : "█"
            painter.write("\(marker) \(oneSeries.label)  ", at: Point(x: x, y: 0), style: style)
            x += DisplayWidth.of(oneSeries.label) + 4
        }
    }

    private func drawAxis(
        _ painter: Painter,
        theme: ResolvedTheme,
        tickValues: [Double],
        top: Double,
        gutter: Int,
        plotTop: Int,
        plotRows: Int,
        baseline: Int,
        plotWidth: Int
    ) {
        let axisStyle = theme.border
        let labelStyle = theme.chartDeemphasis
        let ascii = fidelity == .ascii

        for line in 0..<plotRows {
            painter.set(
                TerminalCell(character: ascii ? "|" : "│", style: axisStyle),
                at: Point(x: gutter, y: plotTop + line)
            )
        }

        painter.set(
            TerminalCell(character: ascii ? "+" : "┼", style: axisStyle),
            at: Point(x: gutter, y: baseline)
        )

        for x in 1...max(1, plotWidth) {
            painter.set(
                TerminalCell(character: ascii ? "-" : "─", style: axisStyle),
                at: Point(x: gutter + x, y: baseline)
            )
        }

        for value in tickValues where value > 0 || tickValues.count <= 2 {
            let row = baseline - Int((value / top * Double(plotRows)).rounded())

            guard row >= plotTop, row < baseline else {
                continue
            }

            painter.set(
                TerminalCell(character: ascii ? "+" : "┤", style: axisStyle),
                at: Point(x: gutter, y: row)
            )

            let label = yFormatter(value)
            painter.write(label, at: Point(x: max(0, gutter - label.count), y: row), style: labelStyle)
        }

        // The zero label sits on the baseline itself.
        let zero = yFormatter(0)
        painter.write(zero, at: Point(x: max(0, gutter - zero.count), y: baseline), style: labelStyle)
    }
}
