import Foundation
import TUIKit

// The Phase 16 controls, each family on a page of its own (Bobby): fields,
// data views, the wizard, gauges, and drawing.

// MARK: - Fields

@MainActor
func makeFieldsTab(app: App) -> TUIView {
    let root = VStack(spacing: 0, insets: EdgeInsets(top: 0, left: 1, bottom: 0, right: 1))

    let searchResult = Label("search reports here")
    let search = SearchField()
    search.onSearch = { searchResult.text = $0.isEmpty ? "search cleared" : "searching: \($0)" }
    search.onCommit = { searchResult.text = "committed: \($0)" }
    let paste = PasteButton { searchResult.text = "pasted: \($0)" }
    paste.onEmpty = { searchResult.text = "nothing to paste — copy something first (^C in a field)" }

    let recipients = TokenField(tokens: ["ops"], placeholder: "add a team, Return mints")
    let teamCompletions = CompletionList(for: recipients.field)
    teamCompletions.items = ["ops", "dev", "design", "docs", "qa", "security"]
    teamCompletions.onAccept = { [weak recipients] in recipients?.mint($0) }
    let themeField = TextField(placeholder: "type a theme name…")
    let themeCompletions = CompletionList(for: themeField)
    themeCompletions.items = TUIKit.Theme.builtIn.map(\.name)

    let ticked = Slider(value: 50, in: 0...100)
    ticked.tickMarks = 5
    ticked.snapsToTicks = true
    let span = RangeSlider(lower: 20, upper: 60, in: 0...100, minimumGap: 10)
    let spanLabel = Label("20…60 — Space switches thumbs")
    span.onValuesChanged = { spanLabel.text = "\($0.lowerBound)…\($0.upperBound) — Space switches thumbs" }

    root.addSubview(pinnedHeight(group("SearchField · PasteButton — Esc/✕ clear, live and committed reports", [row([search, paste]), searchResult]), 5))
    root.addSubview(pinnedHeight(group("TokenField + CompletionList — type 'd', ↓, Return · a second list on a plain field", [row([recipients, themeField])]), 4))
    root.addSubview(pinnedHeight(group("Slider ticks that snap · RangeSlider", [row(spacing: 3, [ticked, span, spanLabel])]), 4))

    return root
}

// MARK: - Data

@MainActor
func makeDataTab() -> TUIView {
    let root = VStack(spacing: 0, insets: EdgeInsets(top: 0, left: 1, bottom: 0, right: 1))

    // MasterDetail at full width, so the split form shows; narrow the
    // window below 60 columns to watch it collapse onto a navigator.
    let folders = [
        SidebarItem(icon: "✉", title: "Inbox", subtitle: "12 unread"),
        SidebarItem(icon: "★", title: "Starred", subtitle: "3 flagged"),
        SidebarItem(icon: "✎", title: "Drafts", subtitle: "1 draft"),
        SidebarItem(icon: "⌫", title: "Trash", subtitle: "empty"),
    ]
    let masterDetail = MasterDetail(items: folders) { index in
        let detail = VStack(spacing: 0)
        detail.addSubview(pinnedHeight(Label("  \(folders[index].title)"), 1))
        detail.addSubview(pinnedHeight(Label("  \(folders[index].subtitle ?? "") — the detail pane for this folder"), 1))
        return detail
    }

    let files = CollectionView(sections: [
        .init(title: "Recent", items: ["report.pdf", "notes.md", "photo.png", "deck.key", "todo.txt"]),
        .init(title: "Shared", items: ["budget.xlsx", "plan.md", "logo.svg"]),
    ]) { Label($0) }
    files.itemWidth = 16

    root.addSubview(pinnedHeight(group("MasterDetail — list drives detail; collapses to a navigator below 60 columns", [masterDetail]), 11))
    root.addSubview(group("CollectionView — sections; arrows walk the grid", [files]))

    return root
}

// MARK: - Wizard

@MainActor
func makeWizardTab() -> TUIView {
    let root = VStack(spacing: 0, insets: EdgeInsets(top: 0, left: 1, bottom: 0, right: 1))

    let wizardName = TextField(placeholder: "user name (required)")
    let expressSkip = Checkbox("Express — skip the account step")
    let welcome = VStack(spacing: 0)
    welcome.addSubview(pinnedHeight(Label("Welcome to the setup wizard."), 1))
    welcome.addSubview(pinnedHeight(expressSkip, 1))
    let wizardDone = Label("setup has not finished yet")
    let wizard = Wizard(steps: [
        .init(id: "welcome", title: "Welcome", view: welcome, next: { expressSkip.isChecked ? "done" : nil }),
        .init(id: "account", title: "Account", view: wizardName,
              validate: { wizardName.text.isEmpty ? "Choose a user name to continue." : nil }),
        .init(id: "done", title: "All set", view: Label("Press Finish to complete the setup.")),
    ])
    wizard.onFinish = { wizardDone.text = "setup finished for \(wizardName.text.isEmpty ? "(express)" : wizardName.text)" }

    root.addSubview(pinnedHeight(group("Wizard — validation blocks Next; Express branches past a step; Back walks the trail", [wizard, wizardDone]), 12))

    return root
}

// MARK: - Gauges

@MainActor
func makeGaugesTab() -> TUIView {
    let root = VStack(spacing: 0, insets: EdgeInsets(top: 0, left: 1, bottom: 0, right: 1))

    func gauges(_ style: Gauge.Style) -> TUIView {
        let row = HStack(spacing: 2)
        for (label, value) in [("CPU", 42.0), ("RAM", 76.0), ("Disk", 93.0)] {
            let gauge = Gauge(value: value, in: 0...100, style: style)
            gauge.label = label
            gauge.warningThreshold = 0.7
            gauge.criticalThreshold = 0.9
            row.addSubview(gauge)
        }
        return row
    }

    let level = LevelIndicator(value: 4, maximum: 5)
    level.isEditable = true
    level.warningLevel = 4
    level.criticalLevel = 5
    let stars = LevelIndicator(value: 3, maximum: 5, style: .rating)
    stars.isEditable = true

    root.addSubview(sideBySide("Gauge .ring — 0.7 warning, 0.9 critical", height: 9) { gauges(.ring) })
    root.addSubview(sideBySide("Gauge .dial", height: 9) { gauges(.dial) })
    root.addSubview(pinnedHeight(group("Gauge .bar — the form every terminal draws", [gauges(.bar)]), 3))
    root.addSubview(pinnedHeight(group("LevelIndicator — warning at 4, critical at 5 (← → change it) · rating", [row(spacing: 3, [level, stars])]), 3))

    return root
}

// MARK: - Drawing

@MainActor
func makeDrawingTab() -> TUIView {
    let root = VStack(spacing: 0, insets: EdgeInsets(top: 0, left: 1, bottom: 0, right: 1))

    root.addSubview(sideBySide("Canvas — chrome-only draw closure (the ANSI side is the honest placeholder)", height: 7) {
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
    })

    root.addSubview(sideBySide("Canvas — with a cell closure too (no placeholder needed)", height: 5) {
        let canvas = Canvas()
        canvas.drawCells = { painter, bounds in
            painter.write("cells draw everywhere; chrome draws under them on a VectorTerminal", at: Point(x: 1, y: bounds.size.height / 2))
        }
        canvas.drawChrome = { chrome, bounds in
            chrome.rect("plate", ChromeRect(bounds), fill: ChromeColor(red: 30, green: 60, blue: 90), radius: 0.4)
        }
        return canvas
    })

    root.addSubview(sideBySide("ImageView — right-click or long-press for Open in Viewer / Copy / Paste", height: 6) {
        let image = ImageView(data: galleryGradientPNG, caption: "gradient.png")
        image.scaling = .fit
        return image
    })

    return root
}
