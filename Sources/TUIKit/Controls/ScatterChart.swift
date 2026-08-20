// `ScatterChart` — individual (x, y) observations, the ActiveUI
// `AUIPointMark` shape on the TUI side. Unlike ``LineChart``'s evenly
// spaced samples, every point carries its own x.

/// Points plotted against two linear axes.
///
/// ```text
///    9 ┤        ∘      •
///    6 ┤   •  •    ∘ •
///    3 ┤ •    ∘  •
///    0 ┼────┬────┬────┬───
///      0    5    10   15
/// ```
///
/// Each series gets its own marker glyph AND colour, so two series stay
/// distinguishable even at the colorless floor. On a VTG terminal points
/// render as small filled circles at sub-cell positions.
@MainActor
public final class ScatterChart: TUIView {
    /// One observation.
    public struct DataPoint: Sendable {
        /// Horizontal value.
        public var x: Double

        /// Vertical value.
        public var y: Double

        /// Creates a point.
        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
    }

    /// One plotted series.
    public struct Series: Sendable {
        /// Name shown in the legend.
        public var label: String

        /// The observations, any order.
        public var points: [DataPoint]

        /// Colour override; `nil` takes the theme's ``ResolvedTheme/chartData(_:)``.
        public var style: CellStyle?

        /// Creates a series.
        public init(label: String, points: [DataPoint], style: CellStyle? = nil) {
            self.label = label
            self.points = points
            self.style = style
        }
    }

    /// The plotted series, drawn in order (later points overdraw earlier).
    public var series: [Series] {
        didSet {
            setNeedsDisplay()
        }
    }

    /// What the x axis spans; `nil` fits the data, rounded out to ticks.
    public var xDomain: ClosedRange<Double>? {
        didSet {
            if xDomain != oldValue {
                setNeedsDisplay()
            }
        }
    }

    /// What the y axis spans; `nil` fits the data, rounded out to ticks.
    public var yDomain: ClosedRange<Double>? {
        didSet {
            if yDomain != oldValue {
                setNeedsDisplay()
            }
        }
    }

    /// Formats a y-axis tick.
    public var yFormatter: (Double) -> String = { value in
        value == value.rounded() ? String(Int(value)) : String(value)
    } {
        didSet {
            setNeedsDisplay()
        }
    }

    /// Formats an x-axis tick.
    public var xFormatter: (Double) -> String = { value in
        value == value.rounded() ? String(Int(value)) : String(value)
    } {
        didSet {
            setNeedsDisplay()
        }
    }

    /// Whether the first row names each series in its marker and colour.
    public var showsLegend = false {
        didSet {
            if showsLegend != oldValue {
                setNeedsDisplay()
            }
        }
    }

    /// Creates a scatter chart.
    public init(series: [Series] = []) {
        self.series = series
        super.init(frame: .zero)
    }

    /// A natural minimum; hosts normally size a chart with anchors.
    public override var intrinsicContentSize: Size? {
        Size(width: 28, height: 8)
    }

    // Marker glyphs, one per series, cycling — all single-width (tested
    // beside the other chart alphabets).
    nonisolated static let markers: [Character] = ["•", "∘", "▪", "▫", "◆"]

    // MARK: - Drawing

    public override func draw(_ painter: Painter) {
        painter.fill(bounds, with: .blank)

        let theme = effectiveTheme
        let legendRows = showsLegend ? 1 : 0
        let axisRows = 2
        let plotRows = bounds.size.height - legendRows - axisRows

        guard plotRows >= 2, series.contains(where: { !$0.points.isEmpty }) else {
            return
        }

        // Fitted domains round OUT to tick multiples (axis stability).
        func fitted(_ values: [Double], explicit: ClosedRange<Double>?, ticks: Int) -> (ClosedRange<Double>, Double) {
            var low = explicit?.lowerBound ?? values.min() ?? 0
            var high = explicit?.upperBound ?? values.max() ?? 1

            if high <= low {
                high = low + 1
            }

            let step = ChartMath.niceStep(span: high - low, maximumTicks: max(2, ticks))

            if explicit == nil {
                low = (low / step).rounded(.down) * step
                high = (high / step).rounded(.up) * step
            }

            return (low...high, step)
        }

        let allPoints = series.flatMap(\.points)
        let (yRange, yStep) = fitted(allPoints.map(\.y), explicit: yDomain, ticks: plotRows / 2)

        var yTicks: [Double] = []
        var tick = (yRange.lowerBound / yStep).rounded(.up) * yStep
        while tick <= yRange.upperBound + yStep / 2 {
            yTicks.append(tick)
            tick += yStep
        }

        let gutter = (yTicks.map { DisplayWidth.of(yFormatter($0)) }.max() ?? 1) + 1
        let plotLeft = gutter + 1
        let plotWidth = bounds.size.width - plotLeft

        guard plotWidth > 4 else {
            return
        }

        let (xRange, xStep) = fitted(allPoints.map(\.x), explicit: xDomain, ticks: plotWidth / 8)

        let inks = series.enumerated().map { index, oneSeries in
            oneSeries.style ?? CellStyle(foreground: theme.chartData(index))
        }

        let plotTop = legendRows
        let baseline = plotTop + plotRows

        if showsLegend {
            var x = 0

            for (index, oneSeries) in series.enumerated() {
                let marker = Self.markers[index % Self.markers.count]
                painter.write("\(marker) \(oneSeries.label)  ", at: Point(x: x, y: 0), style: inks[index])
                x += DisplayWidth.of(oneSeries.label) + 4
            }
        }

        drawAxes(
            painter, theme: theme,
            yTicks: yTicks, yRange: yRange, xRange: xRange, xStep: xStep,
            gutter: gutter, plotLeft: plotLeft, plotTop: plotTop,
            plotRows: plotRows, baseline: baseline, plotWidth: plotWidth
        )

        // Position of a value pair, in fractional plot cells.
        func position(_ point: DataPoint) -> (x: Double, y: Double) {
            let fx = (min(max(point.x, xRange.lowerBound), xRange.upperBound) - xRange.lowerBound)
                / (xRange.upperBound - xRange.lowerBound)
            let fy = (min(max(point.y, yRange.lowerBound), yRange.upperBound) - yRange.lowerBound)
                / (yRange.upperBound - yRange.lowerBound)
            return (
                Double(plotLeft) + fx * (Double(plotWidth) - 1) + 0.5,
                Double(plotTop) + (1 - fy) * (Double(plotRows) - 1) + 0.5
            )
        }

        // Vector: sub-cell-precise dots — all-or-nothing, like every chart.
        if let chrome = painter.chrome, chrome.covers(bounds),
           let backing = ChromeColor(theme.background),
           inks.allSatisfy({ ChromeColor($0.foreground) != nil }) {
            let plotArea = Rect(x: plotLeft, y: plotTop, width: plotWidth, height: plotRows)
            chrome.rect("backing", ChromeRect(plotArea), fill: backing)

            let transparent = painter.withBase(CellStyle())
            transparent.fill(plotArea, with: .blank)

            for (seriesIndex, oneSeries) in series.enumerated() {
                for (pointIndex, point) in oneSeries.points.enumerated() {
                    let at = position(point)
                    chrome.circle(
                        "pt-\(seriesIndex)-\(pointIndex)",
                        center: ChromePoint(x: at.x, y: at.y),
                        radius: 0.14,
                        fill: ChromeColor(inks[seriesIndex].foreground)!
                    )
                }
            }

            return
        }

        // Cells: the series marker at each point's cell.
        for (seriesIndex, oneSeries) in series.enumerated() {
            let marker = Self.markers[seriesIndex % Self.markers.count]

            for point in oneSeries.points {
                let at = position(point)
                painter.set(
                    TerminalCell(character: marker, style: inks[seriesIndex]),
                    at: Point(x: Int(at.x), y: Int(at.y))
                )
            }
        }
    }

    private func drawAxes(
        _ painter: Painter,
        theme: ResolvedTheme,
        yTicks: [Double],
        yRange: ClosedRange<Double>,
        xRange: ClosedRange<Double>,
        xStep: Double,
        gutter: Int,
        plotLeft: Int,
        plotTop: Int,
        plotRows: Int,
        baseline: Int,
        plotWidth: Int
    ) {
        let axisStyle = theme.border
        let labelStyle = theme.chartDeemphasis

        for line in 0..<plotRows {
            painter.set(TerminalCell(character: "│", style: axisStyle), at: Point(x: gutter, y: plotTop + line))
        }

        for value in yTicks {
            let fraction = (value - yRange.lowerBound) / (yRange.upperBound - yRange.lowerBound)
            let row = plotTop + (plotRows - 1) - Int((fraction * Double(plotRows - 1)).rounded())

            painter.set(TerminalCell(character: "┤", style: axisStyle), at: Point(x: gutter, y: row))

            let label = yFormatter(value)
            painter.write(label, at: Point(x: max(0, gutter - label.count), y: row), style: labelStyle)
        }

        painter.set(TerminalCell(character: "┼", style: axisStyle), at: Point(x: gutter, y: baseline))

        for x in 1...max(1, plotWidth) {
            painter.set(TerminalCell(character: "─", style: axisStyle), at: Point(x: gutter + x, y: baseline))
        }

        var tick = (xRange.lowerBound / xStep).rounded(.up) * xStep
        var lastLabelEnd = -1

        while tick <= xRange.upperBound {
            let fraction = (tick - xRange.lowerBound) / (xRange.upperBound - xRange.lowerBound)
            let column = plotLeft + Int((fraction * Double(plotWidth - 1)).rounded())

            painter.set(TerminalCell(character: "┬", style: axisStyle), at: Point(x: column, y: baseline))

            let label = xFormatter(tick)

            if column > lastLabelEnd, column + label.count <= bounds.size.width {
                painter.write(label, at: Point(x: column, y: baseline + 1), style: labelStyle)
                lastLabelEnd = column + label.count + 1
            }

            tick += xStep
        }
    }
}
