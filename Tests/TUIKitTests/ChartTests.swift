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
    // Turbo's content window sets accent = the document blue (for toolbar
    // tinting): data drawn in it would vanish into its own surface. Charts
    // fall back to the body foreground there — and keep the accent
    // everywhere the accent is actually visible.
    let spark = Sparkline(values: [1])
    spark.theme = .turbo
    spark.themeContext = .contentWindow

    let content = Theme.turbo.resolved(for: .contentWindow)
    #expect(content.accent == content.background, "the premise: Turbo's content accent IS the surface")

    let buffer = renderedBuffer(spark, width: 1, height: 1)
    #expect(buffer[Point(x: 0, y: 0)].style.foreground == content.foreground, "ink falls back to the foreground")

    // And chart de-emphasis never drags the placeholder's own background
    // (Turbo tunes it for gray toolbars) onto the chart surface.
    #expect(content.chartDeemphasis.background == .standard)
}
