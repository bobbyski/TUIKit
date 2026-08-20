import Testing
@testable import TUIKit

// Charts (R9–R11): Sparkline, TimelineChart, LineChart. Cells first — every
// assertion here is on the plain-terminal rendering, because that is the
// floor the charts must never sink below.

@MainActor
private func rendered(_ view: TUIView, width: Int, height: Int) -> [String] {
    view.frame = Rect(x: 0, y: 0, width: width, height: height)
    let buffer = SceneRenderer(root: view).render(size: Size(width: width, height: height))

    return (0..<height).map { row in
        String((0..<width).map { buffer[Point(x: $0, y: row)].character })
    }
}

@MainActor
private func renderedBuffer(_ view: TUIView, width: Int, height: Int) -> CellBuffer {
    view.frame = Rect(x: 0, y: 0, width: width, height: height)
    return SceneRenderer(root: view).render(size: Size(width: width, height: height))
}

// MARK: - The alphabets (the two load-bearing constraints)

@Test func everyChartGlyphIsSingleWidth() {
    // A double-width glyph in a chart shifts every column after it and
    // silently misplots the data — so every alphabet is walked, per level.
    for glyph in Sparkline.blockLevels + Sparkline.asciiLevels {
        #expect(DisplayWidth.of(glyph) == 1, "sparkline glyph \(glyph) must be single-width")
    }

    for glyph: Character in ["━", "╸", "┈", "=", "-", "─", "╭", "╮", "╰", "╯", "│", "┤", "┬", "┼", "*", "|", "+"] {
        #expect(DisplayWidth.of(glyph) == 1, "chart glyph \(glyph) must be single-width")
    }

    // The braille range used by LineChart.
    for bits in [UInt32(0), 0x55, 0xAA, 0xFF] {
        let glyph = Character(Unicode.Scalar(0x2800 + bits)!)
        #expect(DisplayWidth.of(glyph) == 1, "braille \(glyph) must be single-width")
    }
}

// MARK: - Sparkline (R9)

@Test @MainActor func sparklineQuantisesToBlockHeights() {
    let spark = Sparkline(values: [0, 1, 2, 3, 4, 5, 6, 7])
    #expect(rendered(spark, width: 8, height: 1) == ["▁▂▃▄▅▆▇█"])

    spark.fidelity = .ascii
    #expect(rendered(spark, width: 8, height: 1) == ["_..-=**#"], "ascii floor stays readable")
}

@Test @MainActor func sparklineShowsTheMostRecentValuesThatFit() {
    // A trend's newest end is the one being read: overflow drops the OLD.
    let spark = Sparkline(values: [7, 7, 7, 7, 0, 0, 0, 0])
    #expect(rendered(spark, width: 4, height: 1) == ["▁▁▁▁"])
}

@Test @MainActor func sparklineFlatSeriesReadsAsABaselineNotAsBlank() {
    let spark = Sparkline(values: [5, 5, 5])
    #expect(rendered(spark, width: 3, height: 1) == ["▁▁▁"], "flat is an answer — 'not the leak'")
}

@Test @MainActor func sparklinePinnedRangeKeepsRowsComparable() {
    // Two counters on one scale: the same value must render the same glyph.
    let low = Sparkline(values: [0, 25])
    low.range = 0...100
    let high = Sparkline(values: [75, 100])
    high.range = 0...100

    #expect(rendered(low, width: 2, height: 1) == ["▁▃"])
    #expect(rendered(high, width: 2, height: 1) == ["▆█"])
}

@Test @MainActor func sparklineDrawsInTheAccentByDefault() {
    let spark = Sparkline(values: [1])
    spark.theme = .turbo
    let buffer = renderedBuffer(spark, width: 1, height: 1)
    #expect(buffer[Point(x: 0, y: 0)].style.foreground == Theme.turbo.resolved().accent)
    #expect(!spark.acceptsFirstResponder, "a sparkline is a glyph, not a focus stop")
}

// MARK: - TimelineChart (R10)

@MainActor
private func waterfall() -> TimelineChart {
    TimelineChart(rows: [
        TimelineRow(label: "index.html", segments: [
            .init(start: 0, duration: 300, kind: .active),
        ]),
        TimelineRow(label: "style.css", segments: [
            .init(start: 100, duration: 200, kind: .waiting),
            .init(start: 300, duration: 500, kind: .active),
        ]),
        TimelineRow(label: "logo.png", segments: [
            .init(start: 200, duration: 30, kind: .active),   // the sub-cell case
        ]),
    ])
}

@Test @MainActor func timelineDrawsBarsAgainstOneSharedAxis() {
    let chart = waterfall()
    chart.domain = 0...800
    let lines = rendered(chart, width: 51, height: 4)

    // Labels in the gutter, bars to their right.
    #expect(lines[1].hasPrefix("index.html"))
    #expect(lines[2].hasPrefix("style.css"))

    // index.html: 0–300 of 0–800 over 40 plot columns → 15 cells with an
    // end cap; the shared axis means style.css's work starts where its wait
    // ends, at the same time scale.
    let indexRow = Array(lines[1])
    #expect(indexRow[11] == "━", "the bar starts at the gutter's edge")
    #expect(indexRow[25] == "╸", "the active run ends with the cap")
    #expect(indexRow[26] == " ")

    let cssRow = Array(lines[2])
    #expect(cssRow[16] == "┈", "waiting draws de-emphasized dashes")
    #expect(cssRow[30] == "━", "then the work")
}

@Test @MainActor func timelineSubCellSegmentStaysVisibleWithoutOverlapping() {
    let chart = waterfall()
    chart.domain = 0...800
    let lines = rendered(chart, width: 51, height: 4)

    // 30ms on an 800ms axis over 40 columns is 1.5 cells — it must paint
    // (dropping it makes a fast request look like it never happened).
    let logoRow = lines[3]
    #expect(logoRow.contains("╸"), "the 30ms request is visible: \(logoRow)")

    // And a genuinely sub-cell segment never rounds into its neighbour.
    let packed = TimelineChart(rows: [
        TimelineRow(label: "r", segments: [
            .init(start: 0, duration: 1, kind: .waiting),
            .init(start: 1, duration: 1, kind: .active),
        ]),
    ])
    packed.domain = 0...1000   // both spans are sub-cell
    packed.showsAxis = false
    let row = rendered(packed, width: 12, height: 1)[0]
    #expect(row.contains("┈"), "the first sub-cell span paints")
    #expect(row.contains("╸"), "the second paints beside it, not over it: \(row)")
}

@Test @MainActor func timelineAxisTicksFallOnRoundNumbers() {
    let chart = waterfall()
    chart.domain = 0...800
    chart.tickFormatter = { "\(Int($0))ms" }
    let axis = rendered(chart, width: 51, height: 4)[0]

    #expect(axis.contains("0ms"))
    #expect(axis.contains("200ms"), "ticks land on round values, not whatever divides the width: \(axis)")
}

@Test @MainActor func timelineKindsMapToThemeSlots() {
    let chart = TimelineChart(rows: [
        TimelineRow(label: "bad", segments: [.init(start: 0, duration: 100, kind: .failed)]),
    ])
    chart.theme = .turbo
    chart.showsAxis = false
    chart.domain = 0...100

    let buffer = renderedBuffer(chart, width: 20, height: 1)
    let barCell = buffer[Point(x: 6, y: 0)]
    #expect(barCell.style.foreground == Theme.turbo.resolved().errorAccent, "failed reads red without the caller naming a colour")
}

@Test @MainActor func timelineSelectsByClickAndArrowsAndCullsScrolledRows() {
    let many = TimelineChart(rows: (0..<50).map { index in
        TimelineRow(label: "row\(index)", segments: [.init(start: 0, duration: 1, kind: .active)])
    })
    many.domain = 0...1

    var selected: [Int] = []
    many.onSelectRow = { selected.append($0) }

    // Click on the second visible row line (axis is line 0).
    _ = rendered(many, width: 30, height: 6)
    _ = many.mouseEvent(MouseInput(position: Point(x: 3, y: 2), action: .press, button: .left))
    #expect(selected == [1])
    #expect(many.selectedRow == 1)

    // Arrows move the selection and keep it visible past the 5 row lines.
    for _ in 0..<10 {
        _ = many.keyDown(KeyInput(key: .down))
    }
    #expect(many.selectedRow == 11)

    let lines = rendered(many, width: 30, height: 6)
    #expect(lines.contains { $0.hasPrefix("row11") }, "the selection scrolled into view")
    #expect(!lines.contains { $0.hasPrefix("row0 ") }, "rows above the viewport are culled")
}

@Test @MainActor func everyChartTakesDirectColoursOverTheTheme() {
    // Theme slots are the DEFAULT, not the ceiling: an app that owns its
    // colour story (a waterfall coloured by MIME type) passes styles in and
    // they win. Same convention on all three charts.
    // Note: the assertions compare foregrounds — a passed-in style's
    // `.standard` background still resolves through the painter to the
    // window's surface, exactly like every other control's colours.
    let orangeInk = TerminalColor.rgb(red: 233, green: 84, blue: 32)
    let orange = CellStyle(foreground: orangeInk)

    let spark = Sparkline(values: [1, 2, 3])
    spark.style = orange
    spark.theme = .turbo
    let sparkBuffer = renderedBuffer(spark, width: 3, height: 1)
    #expect(sparkBuffer[Point(x: 0, y: 0)].style.foreground == orangeInk)

    let chart = TimelineChart(rows: [
        TimelineRow(label: "css", segments: [
            .init(start: 0, duration: 50, kind: .active, style: orange),
            .init(start: 50, duration: 50, kind: .active),
        ]),
    ])
    chart.theme = .turbo
    chart.showsAxis = false
    chart.domain = 0...100
    let timelineBuffer = renderedBuffer(chart, width: 24, height: 1)
    #expect(timelineBuffer[Point(x: 5, y: 0)].style.foreground == orangeInk, "the styled segment wears the app's colour")
    #expect(
        timelineBuffer[Point(x: 20, y: 0)].style.foreground == Theme.turbo.resolved().accent,
        "an unstyled segment beside it still falls back to the theme slot"
    )

    let line = LineChart(series: [.init(label: "m", values: [5, 5], style: orange)])
    line.theme = .turbo
    let lineBuffer = renderedBuffer(line, width: 24, height: 8)
    let plotted = (0..<24).contains { x in
        (0..<8).contains { y in lineBuffer[Point(x: x, y: y)].style.foreground == orangeInk }
    }
    #expect(plotted, "the series draws in its own style")
}

// MARK: - LineChart (R11)

@Test @MainActor func lineChartDrawsTheLineWithAxesAndRoundTicks() {
    let chart = LineChart(series: [
        .init(label: "resident", values: [0, 0, 10, 10, 20, 20, 30, 30]),
    ])
    chart.yFormatter = { "\(Int($0))MB" }
    chart.xDomain = 0...180
    chart.xFormatter = { "\(Int($0))s" }

    let lines = rendered(chart, width: 40, height: 10)
    let all = lines.joined(separator: "\n")

    #expect(all.contains("30MB"), "y ticks label the gutter: \n\(all)")
    #expect(all.contains("0s"), "x ticks label the bottom row")
    #expect(all.contains("─"), "the line draws with box segments")
    #expect(all.contains("╯") || all.contains("╭"), "slope changes draw turns")
    #expect(all.contains("┤"), "the y axis marks its ticks")
    #expect(all.contains("┬"), "the x axis marks its ticks")
}

@Test @MainActor func lineChartAsciiFloorIsReadable() {
    let chart = LineChart(series: [.init(label: "m", values: [0, 5, 10, 5, 0])])
    chart.fidelity = .ascii

    let all = rendered(chart, width: 30, height: 8).joined(separator: "\n")
    #expect(all.contains("*"), "points plot as *")
    #expect(!all.contains("─") && !all.contains("╯"), "no box glyphs at the ascii floor")
}

@Test @MainActor func lineChartBrailleIsOptInAndPlotsInTheBrailleRange() {
    let chart = LineChart(series: [.init(label: "m", values: [0, 10, 3, 8, 1])])
    chart.fidelity = .braille

    let all = rendered(chart, width: 30, height: 8)
    let plotted = all.joined().unicodeScalars.contains { (0x2801...0x28FF).contains($0.value) }
    #expect(plotted, "braille fidelity plots braille dots")
}

@Test @MainActor func lineChartFittedDomainRoundsOutAndDoesNotJitter() {
    // 0…27 fits into round ticks (0…30, step 10); a new sample at 28 lands
    // INSIDE the rounded domain, so the axis labels do not change.
    let chart = LineChart(series: [.init(label: "m", values: [0, 12, 27])])
    let before = rendered(chart, width: 30, height: 10)
    let axisBefore = before.map { String($0.prefix(4)) }

    chart.series = [.init(label: "m", values: [0, 12, 27, 28])]
    let after = rendered(chart, width: 30, height: 10)
    let axisAfter = after.map { String($0.prefix(4)) }

    #expect(axisBefore == axisAfter, "a value creeping up must not relabel the axis")
    #expect(before.joined().contains("30"), "the fitted domain rounded out to a tick multiple")
}

@Test @MainActor func lineChartLegendNamesEachSeriesInItsColour() {
    let chart = LineChart(series: [
        .init(label: "heap", values: [1, 2]),
        .init(label: "stack", values: [2, 1]),
    ])
    chart.showsLegend = true
    chart.theme = .turbo

    let buffer = renderedBuffer(chart, width: 36, height: 10)
    let legend = (0..<36).map { String(buffer[Point(x: $0, y: 0)].character) }.joined()
    #expect(legend.contains("heap") && legend.contains("stack"))

    let resolved = Theme.turbo.resolved()
    #expect(buffer[Point(x: 0, y: 0)].style.foreground == resolved.accent, "first series wears the accent")
}

// MARK: - VTG rendering and the suppression override

@MainActor
private func chromeRendered(_ view: TUIView, width: Int, height: Int, theme: Theme = .ambiance) -> (commands: [ChromeCommand], buffer: CellBuffer) {
    view.theme = theme
    view.frame = Rect(x: 0, y: 0, width: width, height: height)
    let renderer = SceneRenderer(root: view)
    renderer.chromeEnabled = true
    let buffer = renderer.render(size: Size(width: width, height: height))
    return (renderer.chromeCommands, buffer)
}

@Test @MainActor func chartsDrawVectorGraphicsOnAVTGTerminal() {
    // Sparkline: a backing plus one sub-cell bar per value, cells cleared.
    let spark = Sparkline(values: [1, 2, 3])
    let (sparkCommands, sparkBuffer) = chromeRendered(spark, width: 3, height: 1)
    #expect(sparkCommands.contains { $0.id.hasSuffix("_backing") })
    #expect(sparkCommands.filter { $0.id.contains("_bar-") }.count == 3)
    #expect(sparkBuffer[Point(x: 0, y: 0)].character == " ", "glyphs give way to the vector bars")
    #expect(sparkBuffer[Point(x: 0, y: 0)].style.background == .standard, "cells go transparent over the bars")

    // Timeline: rounded blocks at true fractional positions.
    let chart = TimelineChart(rows: [
        TimelineRow(label: "r", segments: [.init(start: 0, duration: 30, kind: .active)]),
    ])
    chart.domain = 0...800
    chart.showsAxis = false
    let (barCommands, _) = chromeRendered(chart, width: 40, height: 1)

    guard let bar = barCommands.first(where: { $0.id.contains("_bar-0-0") }),
          case .rect(let rect, _, _, _, let radius, _) = bar.shape else {
        Issue.record("no vector bar drawn")
        return
    }

    #expect(radius > 0, "the requested rounded corners")
    #expect(rect.width > 0.19 && rect.width < 2.5, "a 30ms segment is sub-cell honest, not a rounded column: \(rect.width)")

    // LineChart: one retained polyline per series.
    let line = LineChart(series: [.init(label: "m", values: [0, 10, 5])])
    let (lineCommands, _) = chromeRendered(line, width: 30, height: 8)

    guard let trace = lineCommands.first(where: { $0.id.contains("_trace-0") }),
          case .polyline(let points, _, _) = trace.shape else {
        Issue.record("no vector trace drawn")
        return
    }

    #expect(points.count >= 20, "sampled smoothly, not per cell")
    #expect(lineCommands.contains { $0.id.hasSuffix("_backing") })
}

@Test @MainActor func suppressesVectorChromePinsTheCellRenderingPerView() {
    // The side-by-side gallery case: two identical sparklines on one
    // chrome-enabled screen, one opted out — it renders the plain-terminal
    // glyphs while its twin draws vector bars.
    let root = TUIView(frame: Rect(x: 0, y: 0, width: 8, height: 1))
    root.theme = .ambiance

    let vector = Sparkline(values: [0, 7])
    vector.frame = Rect(x: 0, y: 0, width: 2, height: 1)
    root.addSubview(vector)

    let cells = Sparkline(values: [0, 7])
    cells.suppressesVectorChrome = true
    cells.frame = Rect(x: 4, y: 0, width: 2, height: 1)
    root.addSubview(cells)

    let renderer = SceneRenderer(root: root)
    renderer.chromeEnabled = true
    let buffer = renderer.render(size: Size(width: 8, height: 1))

    #expect(buffer[Point(x: 0, y: 0)].character == " ", "the vector twin cleared its glyphs")
    #expect(buffer[Point(x: 4, y: 0)].character == "▁", "the suppressed twin keeps the ANSI glyphs")
    #expect(buffer[Point(x: 5, y: 0)].character == "█")

    let owners = Set(renderer.chromeCommands.map(\.id))
    #expect(!owners.isEmpty, "the vector twin emitted chrome")
    #expect(
        renderer.chromeCommands.count == 1 + 2,
        "backing + two bars from ONE sparkline only, got \(renderer.chromeCommands.count)"
    )

    // The override cascades: a suppressed CONTAINER pins every descendant.
    let group = TUIView(frame: Rect(x: 0, y: 0, width: 8, height: 1))
    group.theme = .ambiance
    group.suppressesVectorChrome = true
    let child = Sparkline(values: [0, 7])
    child.frame = Rect(x: 0, y: 0, width: 2, height: 1)
    group.addSubview(child)

    let groupRenderer = SceneRenderer(root: group)
    groupRenderer.chromeEnabled = true
    let groupBuffer = groupRenderer.render(size: Size(width: 8, height: 1))

    #expect(groupRenderer.chromeCommands.isEmpty, "nothing below a suppressed view emits chrome")
    #expect(groupBuffer[Point(x: 1, y: 0)].character == "█")
}

@Test @MainActor func aColourlessThemeKeepsChartsOnGlyphsEvenWithChrome() {
    // Mono has no RGB story: charts must not half-render — they take the
    // glyph path wholesale.
    let spark = Sparkline(values: [1, 2])
    let (commands, buffer) = chromeRendered(spark, width: 2, height: 1, theme: .mono)
    #expect(commands.isEmpty)
    #expect(buffer[Point(x: 1, y: 0)].character == "█")
}

@Test @MainActor func chartsFallBackToForegroundInkWhenTheAccentIsTheSurface() {
    // A theme may point `accent` at a surface (Turbo's content window did,
    // before secondaryAccent took the toolbar-tinting job): derived chart
    // ink would vanish into it, so the derivation falls back to the body
    // foreground there.
    let blue = TerminalColor.rgb(red: 0, green: 0, blue: 170)
    let yellow = TerminalColor.rgb(red: 255, green: 255, blue: 85)
    let collided = Theme.surface("Collided", background: blue, foreground: yellow, accent: blue)

    let spark = Sparkline(values: [1])
    spark.theme = collided

    let buffer = renderedBuffer(spark, width: 1, height: 1)
    #expect(buffer[Point(x: 0, y: 0)].style.foreground == yellow, "derived ink falls back to the foreground")

    // And chart de-emphasis never drags the placeholder slot's own
    // background (tuned for other surfaces) onto the chart surface.
    #expect(collided.resolved().chartDeemphasis.background == .standard)

    // An explicit series palette is used as given — the derivation guard is
    // only for themes that never thought about charts.
    let turboContent = Theme.turbo.resolved(for: .contentWindow)
    #expect(turboContent.chartData(0) == .rgb(red: 0, green: 170, blue: 0), "Turbo's EGA palette: series 1 is green")
    #expect(turboContent.chartData(10) == turboContent.chartData(0), "the palette cycles")
}

// MARK: - BarChart, PieChart, ScatterChart, area fill (the ActiveUI ports)

@Test @MainActor func barChartDrawsGroupedBarsOnAZeroBaseline() {
    let chart = BarChart(
        categories: ["Mon", "Tue"],
        series: [
            .init(label: "a", values: [10, 20]),
            .init(label: "b", values: [5, 10]),
        ]
    )
    chart.theme = .turbo
    let lines = rendered(chart, width: 30, height: 8)
    let all = lines.joined(separator: "\n")

    #expect(all.contains("Mon") && all.contains("Tue"), "category labels under the groups")
    #expect(all.contains("0"), "the baseline is always zero")
    #expect(all.contains("█"), "bars draw as solid blocks")
    #expect(all.contains("┼") && all.contains("─"), "the baseline rule renders")

    // The 20-value bar is twice the height of the 10-value bar.
    let buffer = renderedBuffer(chart, width: 30, height: 8)
    var heights: [Int: Int] = [:]
    for x in 0..<30 {
        var count = 0
        for y in 0..<8 where buffer[Point(x: x, y: y)].character == "█" {
            count += 1
        }
        if count > 0 { heights[x] = count }
    }
    let tallest = heights.values.max() ?? 0
    #expect(heights.values.contains { $0 <= tallest / 2 + 1 && $0 > 0 }, "half the value, half the bar: \(heights)")
}

@Test @MainActor func barChartVectorBarsAreRoundedAndSuppressible() {
    let chart = BarChart(categories: ["A"], series: [.init(label: "s", values: [5])])
    let (commands, buffer) = chromeRendered(chart, width: 20, height: 7, theme: .turbo)

    guard let bar = commands.first(where: { $0.id.contains("_bar-0-0") }),
          case .rect(_, _, _, _, let radius, let corners) = bar.shape else {
        Issue.record("no vector bar")
        return
    }

    #expect(radius > 0 && corners == .top, "rounded-top vector bars")
    #expect(buffer.textLines().joined().contains("█") == false, "glyph bars gave way to vector ones")

    chart.suppressesVectorChrome = true
    let again = renderedBuffer(chart, width: 20, height: 7)
    #expect(again.textLines().joined().contains("█"), "suppressed → the ANSI bars")
}

@Test @MainActor func pieChartLegendCarriesTheTruthAndSlicesKeepTheirOrder() {
    let chart = PieChart(slices: [
        .init(label: "rent", value: 42),
        .init(label: "food", value: -33),   // magnitudes: negatives fold
        .init(label: "misc", value: 25),
    ])
    chart.theme = .turbo
    let lines = rendered(chart, width: 40, height: 7)
    let all = lines.joined(separator: "\n")

    #expect(all.contains("rent") && all.contains("42%"), "the legend names every share exactly")
    #expect(all.contains("food") && all.contains("33%"), "a negative slice reads as its magnitude")
    #expect(all.contains("misc") && all.contains("25%"))
    #expect(all.contains("█"), "and there is a disc, comic as cells make it")

    // First slice starts at 12 o'clock: the cell just above center belongs
    // to rent (chartData(0) = Turbo EGA green), because order is preserved.
    let buffer = renderedBuffer(chart, width: 40, height: 7)
    let above = buffer[Point(x: 7, y: 1)]
    #expect(above.style.foreground == Theme.turbo.resolved().chartData(0), "12 o'clock belongs to the first slice")
}

@Test @MainActor func pieChartVectorSectorsSweepTheWholeCircleAndDonutsKeepAHole() {
    let chart = PieChart(slices: [
        .init(label: "a", value: 3),
        .init(label: "b", value: 1),
    ])
    chart.innerRadiusFraction = 0.5
    let (commands, _) = chromeRendered(chart, width: 30, height: 7, theme: .turbo)

    let sectors = commands.compactMap { command -> (start: Double, end: Double)? in
        guard command.id.contains("_slice-"),
              case .sector(_, _, _, let start, let end, _) = command.shape else {
            return nil
        }

        return (start, end)
    }

    #expect(sectors.count == 2)

    // The last slice ends at exactly 2π and the FIRST slice reaches
    // backward under it, so the 12 o'clock edge antialiases over the first
    // slice's paint — never over background (a hairline) and never with a
    // wrong-colored wrap sliver on top. Interior boundaries are each
    // slice's exact start edge, drawn over the previous slice's overdrawn
    // end.
    let closing = sectors.last?.end ?? 0
    #expect(closing == 2 * Double.pi, "closes exactly at full: \(closing)")
    #expect(sectors[0].start < 0, "the first slice reaches back under the closing edge")
    #expect(sectors[0].end > 1.5 * Double.pi && sectors[0].end < 1.5 * Double.pi + 0.06, "3 of 4 ≈ three quarters, plus the overlap")
    #expect(sectors[1].start < sectors[0].end, "the next slice starts under the previous one's overdrawn edge")
    #expect(sectors[1].start == 1.5 * Double.pi, "and its exact start edge is the visible boundary")

    // The hole is one surface-colored full-turn sector over full pie
    // slices — winding-proof, unlike per-slice inner arcs, and a path
    // rather than the circle primitive, whose fan tessellation has been
    // seen to drop its closing wedge (a radial sliver of slice paint).
    guard let hole = commands.first(where: { $0.id.hasSuffix("_hole") }),
          case .sector(_, let radius, _, let start, let end, let fill) = hole.shape else {
        Issue.record("no donut hole")
        return
    }

    #expect(radius > 0)
    #expect(start == 0 && end == 2 * Double.pi, "the hole sweeps the full turn")
    #expect(fill == ChromeColor(Theme.turbo.resolved().background), "the hole wears the chart's surface")
}

@Test @MainActor func aPartiallyVisibleChartKeepsItsCellsInsideTheClip() {
    // Round vector shapes cannot be cropped by the terminal, so a chart
    // scrolled half out of view must NOT draw them — its sectors would
    // spill past the region cells are clipped to (the escaped-donut bug).
    // Partially visible → the cell rendering, which clips perfectly.
    let parent = TUIView(frame: Rect(x: 0, y: 0, width: 40, height: 4))
    parent.theme = .ambiance

    let pie = PieChart(slices: [.init(label: "a", value: 1), .init(label: "b", value: 1)])
    pie.frame = Rect(x: 0, y: 2, width: 40, height: 7)   // hangs 5 rows past the parent
    parent.addSubview(pie)

    let renderer = SceneRenderer(root: parent)
    renderer.chromeEnabled = true
    let buffer = renderer.render(size: Size(width: 40, height: 4))

    #expect(
        !renderer.chromeCommands.contains { $0.id.contains("_slice-") || $0.id.contains("_backing") },
        "no vector shapes from a partially clipped chart"
    )
    #expect(buffer.textLines().joined().contains("█"), "the visible strip still draws — as cells, clipped")

    // Fully visible again → vector shapes return.
    pie.frame = Rect(x: 0, y: 0, width: 40, height: 4)
    _ = renderer.render(size: Size(width: 40, height: 4))
    #expect(renderer.chromeCommands.contains { $0.id.contains("_slice-") })
}

@Test @MainActor func scatterPlotsEachSeriesInItsOwnMarkerAndVectorDots() {
    let chart = ScatterChart(series: [
        .init(label: "hit", points: [.init(x: 0, y: 0), .init(x: 10, y: 10)]),
        .init(label: "miss", points: [.init(x: 5, y: 5)]),
    ])
    chart.theme = .turbo
    let all = rendered(chart, width: 30, height: 8).joined(separator: "\n")

    #expect(all.contains("•"), "series 1's marker")
    #expect(all.contains("∘"), "series 2's marker — distinguishable without colour")
    #expect(all.contains("┤") && all.contains("┬"), "both axes tick")

    let (commands, _) = chromeRendered(chart, width: 30, height: 8, theme: .turbo)
    #expect(commands.filter { $0.id.contains("_pt-") }.count == 3, "one vector dot per observation")
}

@Test @MainActor func lineChartAreaFillsBelowTheLine() {
    let chart = LineChart(series: [
        .init(label: "m", values: [10, 10, 10], fillsArea: true),
    ])
    chart.theme = .turbo
    chart.yDomain = 0...20

    // Cells: solid blocks from below the line down to the axis.
    let buffer = renderedBuffer(chart, width: 20, height: 8)
    var blocks = 0
    for y in 0..<8 {
        for x in 0..<20 where buffer[Point(x: x, y: y)].character == "█" {
            blocks += 1
        }
    }
    #expect(blocks > 10, "the area under the line is solid, got \(blocks) blocks")

    // VTG: a translucent polygon under the trace, closed along the axis.
    let (commands, _) = chromeRendered(chart, width: 20, height: 8, theme: .turbo)
    guard let area = commands.first(where: { $0.id.hasSuffix("-area") }),
          case .polygon(let points, let fill, _, _) = area.shape else {
        Issue.record("no area polygon")
        return
    }

    #expect(points.count >= 4)
    #expect((fill?.alpha ?? 255) < 255, "the fill is translucent so grid/backing reads through")
}

@Test func sectorPathsApproximateArcsHonestly() {
    // Quarter circle from 12 to 3 o'clock, radius 100 at origin 200,200.
    let payload = ChromeSectorPath.payload(centerX: 200, centerY: 200, radius: 100, innerRadius: 0, start: 0, end: Double.pi / 2)

    #expect(payload.hasPrefix("M 200 100"), "starts at 12 o'clock: \(payload)")
    #expect(payload.contains("C"), "arcs become cubics")
    #expect(payload.contains("300 200"), "ends at 3 o'clock")
    #expect(payload.hasSuffix("L 200 200 Z"), "a pie slice closes through the center")

    let donut = ChromeSectorPath.payload(centerX: 200, centerY: 200, radius: 100, innerRadius: 50, start: 0, end: Double.pi / 2)
    #expect(donut.contains("L 250 200"), "a ring turns onto the inner arc instead")
    #expect(!donut.contains("L 200 200"), "and never touches the center")
}

@Test func scatterMarkersAreSingleWidth() {
    for marker in ScatterChart.markers {
        #expect(DisplayWidth.of(marker) == 1, "marker \(marker) must be single-width")
    }
}
