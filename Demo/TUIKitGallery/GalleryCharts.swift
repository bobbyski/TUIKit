import TUIKit

// The Charts tab: every chart TWICE, side by side — the left copy renders
// vector graphics on a VTG terminal, the right copy sets
// `suppressesVectorChrome` so it always renders ANSI cells. On a plain
// terminal the two columns are identical by design; the caption says so.

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
    pair.minimumSize = Size(width: 0, height: height)
    pair.maximumSize = Size(width: Int.max, height: height)
    return pair
}

@MainActor
func makeChartsTab() -> TUIView {
    let root = VStack(spacing: 0, insets: EdgeInsets(top: 0, left: 1, bottom: 0, right: 1))

    root.addSubview(sideBySide("Sparkline", height: 3) {
        let spark = Sparkline(values: [2, 3, 3, 4, 5, 7, 8, 8, 9, 11, 14, 13, 15, 18, 17, 19, 22, 21, 24, 26])
        return spark
    })

    root.addSubview(sideBySide("TimelineChart", height: 7) {
        let chart = TimelineChart(rows: [
            TimelineRow(label: "index.html", segments: [
                .init(start: 0, duration: 210, kind: .active),
            ]),
            TimelineRow(label: "style.css", segments: [
                .init(start: 60, duration: 180, kind: .waiting),
                .init(start: 240, duration: 380, kind: .active),
            ]),
            TimelineRow(label: "logo.png", segments: [
                .init(start: 120, duration: 30, kind: .active),
            ]),
            TimelineRow(label: "track.js", segments: [
                .init(start: 150, duration: 260, kind: .waiting),
                .init(start: 410, duration: 90, kind: .failed),
            ]),
        ])
        chart.domain = 0...800
        chart.tickFormatter = { "\(Int($0))ms" }
        return chart
    })

    // A flexible row: the line chart takes whatever height is left.
    let line = sideBySide("LineChart", height: 0) {
        let chart = LineChart(series: [
            .init(label: "resident", values: [8, 9, 9, 10, 12, 12, 14, 17, 16, 18, 21, 22, 22, 25, 28]),
            .init(label: "heap", values: [3, 3, 4, 5, 5, 6, 8, 7, 8, 10, 10, 12, 12, 13, 15]),
        ])
        chart.showsLegend = true
        chart.yFormatter = { "\(Int($0))MB" }
        chart.xDomain = 0...180
        chart.xFormatter = { "\(Int($0))s" }
        return chart
    }
    line.maximumSize = nil   // flexible: absorbs the leftover height
    line.minimumSize = Size(width: 0, height: 8)
    root.addSubview(line)

    let note = Label("If the two columns look the same, this terminal has no VTG graphics.")
    note.alignment = .center
    root.addSubview(pinnedHeight(note, 1))

    return root
}

// Pins a stack row to an exact height (shared shape with GalleryWindow's
// helper; small enough that duplicating beats exporting).
@MainActor
private func pinnedHeight(_ view: TUIView, _ height: Int) -> TUIView {
    view.minimumSize = Size(width: 0, height: height)
    view.maximumSize = Size(width: Int.max, height: height)
    return view
}
