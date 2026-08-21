import Foundation
import TUIKit

// The Buttons, Inputs, and Pickers folder tabs.

// MARK: - Buttons

@MainActor
func makeButtonsTab(app: App) -> TUIView {
    let root = VStack(spacing: 0, insets: EdgeInsets(top: 0, left: 1, bottom: 0, right: 1))

    // Roles: how a theme dresses ordinary/default/destructive.
    let ok = Button("&Save") {}
    ok.role = .default
    let danger = Button("&Delete") {}
    danger.role = .destructive
    let plain = Button("&Reset") {}
    let bordered = Button("Bordered") {}
    bordered.style = .bordered

    // Long-press: hold fires the alternate; a quick click still clicks.
    let holdResult = Label("click / hold ⇧ 600ms — the toolbar's Back button holds too")
    let hold = Button("&Back") { holdResult.text = "clicked — quick press" }
    hold.onLongPress = { holdResult.text = "long-pressed — the alternate action fired" }

    let menuButton = Button("Menu on hold") {}
    let context = Menu("")
    context.addItem("Reopen Closed Tab") { holdResult.text = "menu: reopen" }
    context.addItem("Copy Address") { holdResult.text = "menu: copy" }
    menuButton.contextMenu = context   // no handler → long-press opens this

    let toggle = ToggleButton("Wrap Lines")
    let check = Checkbox("Show hidden files")
    let radios = RadioGroup(["Ask", "Allow", "Block"])
    let segments = SegmentedControl(["Day", "Week", "Month"], selectedIndex: 0)

    // Dialogs: modal Dialog, and the open/save FileDialogs.
    let dialogResult = Label("dialogs report here")

    let showDialog = Button("Dialog…") {
        let dialog = Dialog(title: "Delete Page?", message: "This cannot be undone.")
        dialog.addButton("&Cancel", isCancel: true) { dialogResult.text = "dialog: cancelled" }
        dialog.addButton("&Delete", isDefault: true, isDestructive: true) { dialogResult.text = "dialog: deleted" }
        dialog.onDismiss = { [weak dialog, weak app] in
            if let dialog, let app {
                app.dismiss(dialog)
            }
        }
        dialog.sizeToFit(in: app.desktop.bounds.size)
        app.present(dialog)
        dialog.sizeToFit(in: app.desktop.bounds.size)
    }

    let openFile = Button("Open File…") {
        let dialog = FileDialog(mode: .open, root: FileManager.default.currentDirectoryPath)
        dialog.onConfirm = { dialogResult.text = "open: \($0)" }
        dialog.onDismiss = { [weak dialog, weak app] in
            if let dialog, let app {
                app.dismiss(dialog)
            }
        }
        dialog.sizeToFit(in: app.desktop.bounds.size)
        app.present(dialog)
        dialog.sizeToFit(in: app.desktop.bounds.size)
    }

    root.addSubview(pinnedHeight(group("Roles & Styles", [row([ok, danger, plain, bordered])]), 4))
    root.addSubview(pinnedHeight(group("Long-press (hold a fresh press ~600 ms)", [
        row([hold, menuButton]),
        holdResult,
    ]), 5))
    root.addSubview(pinnedHeight(group("State", [row([toggle, check])]), 4))
    root.addSubview(pinnedHeight(group("Dialogs", [row([showDialog, openFile]), dialogResult]), 5))
    root.addSubview(group("Choice", [row(spacing: 3, [radios, segments])]))

    return root
}

// MARK: - Inputs

@MainActor
func makeInputsTab(app: App) -> TUIView {
    let root = VStack(spacing: 0, insets: EdgeInsets(top: 0, left: 1, bottom: 0, right: 1))

    let field = TextField()
    field.placeholder = "type here…"
    let combo = ComboBox(items: ["Mercury", "Venus", "Earth", "Mars"])
    let popUp = PopUpButton(items: ["Balanced", "Performance", "Quiet"], selectedIndex: 0)

    let slider = Slider(value: 35, in: 0...100)
    let stepper = Stepper(value: 4, in: 0...10)
    let level = LevelIndicator(value: 3, maximum: 5)
    level.isEditable = true
    level.warningLevel = 4      // Phase 16.12: thresholds recolour the fill
    level.criticalLevel = 5

    let bar = ProgressIndicator(style: .bar, value: 0.6)
    let spinner = ProgressIndicator(style: .spinner)

    // The App timer story: the spinner animates like input redraws.
    app.addTimer(every: .milliseconds(150)) { [weak spinner] in
        spinner?.advance()
    }

    // Phase 16: SearchField (live + committed reports, Esc/✕ clear) and
    // PasteButton (the app pasteboard, or an honest "nothing to paste").
    let searchResult = Label("search reports here")
    let search = SearchField()
    search.onSearch = { searchResult.text = $0.isEmpty ? "search cleared" : "searching: \($0)" }
    search.onCommit = { searchResult.text = "committed: \($0)" }
    let paste = PasteButton { searchResult.text = "pasted: \($0)" }
    paste.onEmpty = { searchResult.text = "nothing to paste — copy something first (^C in a field)" }

    root.addSubview(pinnedHeight(group("Text & Choices", [row([field, combo, popUp])]), 4))
    root.addSubview(pinnedHeight(group("Search & Paste", [row([search, paste]), searchResult]), 5))
    // Phase 16: tick marks (snapping walks them) and the two-thumb range.
    let ticked = Slider(value: 50, in: 0...100)
    ticked.tickMarks = 5
    ticked.snapsToTicks = true
    let span = RangeSlider(lower: 20, upper: 60, in: 0...100, minimumGap: 10)
    let spanLabel = Label("20…60 — Space switches thumbs")
    span.onValuesChanged = { spanLabel.text = "\($0.lowerBound)…\($0.upperBound) — Space switches thumbs" }

    root.addSubview(pinnedHeight(group("Values", [row(spacing: 3, [slider, stepper, level])]), 4))
    root.addSubview(pinnedHeight(group("Sliders — ticks that snap, and a range", [row(spacing: 3, [ticked, span, spanLabel])]), 4))
    root.addSubview(group("Progress (the spinner rides an App timer)", [row(spacing: 3, [bar, spinner])]))

    return root
}

// MARK: - Pickers

@MainActor
func makePickersTab() -> TUIView {
    let root = HStack(spacing: 1, insets: EdgeInsets(top: 0, left: 1, bottom: 0, right: 1))

    let date = DatePicker(mode: .date)
    let calendar = DatePicker(mode: .calendar)
    let color = ColorPicker()

    let left = VStack(spacing: 0)
    left.addSubview(pinnedHeight(group("DatePicker — .date (Space drops a month grid)", [date]), 4))
    left.addSubview(group("DatePicker — .calendar", [calendar]))

    root.addSubview(left)
    root.addSubview(group("ColorPicker (named / palette / RGB tabs)", [color]))

    return root
}
