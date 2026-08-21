import TUIKit

// The Charts tab: every chart TWICE, side by side — the left copy renders
// vector graphics on a VTG terminal, the right copy sets
// `suppressesVectorChrome` so it always renders ANSI cells. On a plain
// terminal the two columns are identical by design; the caption says so.
// Taller than the window on purpose: the whole tab lives in a ScrollView.

/// One chart beside its cells-pinned twin, each in a titled panel.
@MainActor
private func sideBySide(_ title: String, height: Int, make: () -> TUIView) -> TUIView {
    let vector = make()

    let cells = make()
    cells.suppressesVectorChrome = true

    let vectorPanel = Panel("\(title) — VTG")
    vector.anchors = .fill()
    vectorPanel.content.addSubview(vector)

    let cellsPanel = Panel("\(title) — ANSI")
    cells.anchors = .fill()
    cellsPanel.content.addSubview(cells)

    let pair = HStack(spacing: 1)
    pair.addSubview(vectorPanel)
    pair.addSubview(cellsPanel)
    return pinnedHeight(pair, height)
}

// A stack whose scroll height is declared, so the ScrollView can size the
// document (pinned rows carry no intrinsic of their own).
@MainActor
private final class ChartsColumn: StackView {
    var contentHeight = 0

    init(spacing: Int = 0, insets: EdgeInsets = .zero) {
        super.init(axis: .vertical, spacing: spacing, insets: insets)
    }

    override var intrinsicContentSize: Size? {
        Size(width: 0, height: contentHeight)
    }
}

@MainActor
func makeChartsTab() -> TUIView {
    let column = ChartsColumn(spacing: 0, insets: EdgeInsets(top: 0, left: 1, bottom: 0, right: 1))
    var totalHeight = 0

    func addRow(_ row: TUIView, _ height: Int) {
        column.addSubview(row)
        totalHeight += height
    }

    addRow(sideBySide("Sparkline", height: 3) {
        Sparkline(values: [2, 3, 3, 4, 5, 7, 8, 8, 9, 11, 14, 13, 15, 18, 17, 19, 22, 21, 24, 26])
    }, 3)

    addRow(sideBySide("BarChart", height: 9) {
        let chart = BarChart(
            categories: ["Mon", "Tue", "Wed", "Thu", "Fri"],
            series: [
                .init(label: "builds", values: [12, 17, 9, 21, 14]),
                .init(label: "deploys", values: [4, 6, 3, 8, 5]),
            ]
        )
        chart.showsLegend = true
        return chart
    }, 9)

    addRow(sideBySide("TimelineChart", height: 7) {
        let chart = TimelineChart(rows: [
            TimelineRow(label: "index.html", segments: [.init(start: 0, duration: 210, kind: .active)]),
            TimelineRow(label: "style.css", segments: [
                .init(start: 60, duration: 180, kind: .waiting),
                .init(start: 240, duration: 380, kind: .active),
            ]),
            TimelineRow(label: "logo.png", segments: [.init(start: 120, duration: 30, kind: .active)]),
            TimelineRow(label: "track.js", segments: [
                .init(start: 150, duration: 260, kind: .waiting),
                .init(start: 410, duration: 90, kind: .failed),
            ]),
        ])
        chart.domain = 0...800
        chart.tickFormatter = { "\(Int($0))ms" }
        return chart
    }, 7)

    addRow(sideBySide("ScatterChart", height: 9) {
        let chart = ScatterChart(series: [
            .init(label: "cache hit", points: [
                .init(x: 2, y: 11), .init(x: 5, y: 14), .init(x: 7, y: 13), .init(x: 11, y: 17),
                .init(x: 14, y: 16), .init(x: 17, y: 21), .init(x: 21, y: 20), .init(x: 24, y: 24),
            ]),
            .init(label: "cache miss", points: [
                .init(x: 3, y: 4), .init(x: 8, y: 7), .init(x: 12, y: 5), .init(x: 16, y: 9),
                .init(x: 20, y: 7), .init(x: 25, y: 11),
            ]),
        ])
        chart.showsLegend = true
        return chart
    }, 9)

    addRow(sideBySide("LineChart (heap fills its area)", height: 10) {
        let chart = LineChart(series: [
            .init(label: "resident", values: [8, 9, 9, 10, 12, 12, 14, 17, 16, 18, 21, 22, 22, 25, 28]),
            .init(label: "heap", values: [3, 3, 4, 5, 5, 6, 8, 7, 8, 10, 10, 12, 12, 13, 15], fillsArea: true),
        ])
        chart.showsLegend = true
        chart.yFormatter = { "\(Int($0))MB" }
        chart.xDomain = 0...180
        chart.xFormatter = { "\(Int($0))s" }
        return chart
    }, 10)

    // Canvas (Phase 16.9): a draw closure, chrome only — so the ANSI side is
    // the honest placeholder rather than a blank.
    addRow(sideBySide("Canvas — chrome-only draw closure", height: 7) {
        let canvas = Canvas()
        canvas.drawChrome = { chrome, bounds in
            let w = Double(bounds.size.width)
            let h = Double(bounds.size.height)
            chrome.rect("plate", ChromeRect(x: 1, y: 0.5, width: w - 2, height: h - 1),
                        fill: ChromeColor(red: 28, green: 40, blue: 80), radius: 0.5)
            chrome.circle("sun", center: ChromePoint(x: w * 0.25, y: h * 0.5), radius: h * 0.3,
                          fill: ChromeColor(red: 250, green: 200, blue: 60))
            chrome.polyline("hills", points: [
                ChromePoint(x: w * 0.4, y: h * 0.8), ChromePoint(x: w * 0.55, y: h * 0.35),
                ChromePoint(x: w * 0.7, y: h * 0.65), ChromePoint(x: w * 0.85, y: h * 0.3),
                ChromePoint(x: w * 0.95, y: h * 0.8),
            ], color: ChromeColor(red: 90, green: 200, blue: 120), width: 0.12)
        }
        return canvas
    }, 7)

    // The pie sits last: its cell disc is the coarsest thing on the tab,
    // and the charts above it deserve the first screenful.
    addRow(sideBySide("PieChart (donut 0.55)", height: 8) {
        let chart = PieChart(slices: [
            .init(label: "rent", value: 42),
            .init(label: "food", value: 33),
            .init(label: "transit", value: 17),
            .init(label: "misc", value: 8),
        ])
        chart.innerRadiusFraction = 0.55
        return chart
    }, 8)

    let note = Label("If the two columns look the same, this terminal has no VTG graphics.")
    note.alignment = .center
    addRow(pinnedHeight(note, 1), 1)

    column.contentHeight = totalHeight

    let scroll = ScrollView(document: column)
    scroll.fitsDocumentWidth = true
    return scroll
}
