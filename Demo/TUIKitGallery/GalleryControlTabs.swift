import Foundation
import TUIKit

// The Buttons, Inputs, and Pickers folder tabs.

// MARK: - Buttons

@MainActor
func makeButtonsTab(app: App, settings: GallerySettings) -> TUIView {
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

    // Phase 16.25: a document window — DocumentController owns Open/Save/
    // Save As/Close, the dirty marker in the title, and the close confirm.
    let openDocument = Button("Document…") { [weak app] in
        guard let app else { return }
        let window = FloatingWindow(title: "Untitled", frame: Rect(x: 6, y: 3, width: 64, height: 16))
        let editor = TextView(text: "Type here, then File-style buttons below: the title shows • while dirty.")
        let document = DocumentController(app: app, types: [.init(title: "Text", patterns: ["*.txt", "*.md"])],
            read: { data in editor.setText(String(decoding: data, as: UTF8.self)) },
            write: { Data(editor.text.utf8) })
        document.onTitleChanged = { [weak window] in window?.title = $0 }
        editor.onChanged = { _ in document.markDirty() }

        let bar = HStack(spacing: 1)
        bar.addSubview(Button("&Open…") { document.open() })
        bar.addSubview(Button("&Save") { document.save() })
        bar.addSubview(Button("Save &As…") { document.saveAs() })
        bar.addSubview(Button("&Close") { [weak window, weak app] in
            document.close { if let window, let app { app.dismiss(window) } }
        })
        window.onCloseRequest = { [weak window, weak app] in
            document.close { if let window, let app { app.dismiss(window) } }
        }

        let column = VStack(spacing: 0)
        column.addSubview(pinnedHeight(bar, 1))
        column.addSubview(editor)
        column.anchors = .fill()
        window.content.addSubview(column)
        app.present(window)
    }

    root.addSubview(pinnedHeight(group("Roles & Styles", [row([ok, danger, plain, bordered])]), 4))
    root.addSubview(pinnedHeight(group("Long-press (hold a fresh press ~600 ms)", [
        row([hold, menuButton]),
        holdResult,
    ]), 5))
    root.addSubview(pinnedHeight(group("State", [row([toggle, check])]), 4))
    // The preferences dialog in each variation — the gallery's own
    // preferences (theme, panel at launch, hints), so the pages are real.
    let preferencesToolbar = Button("Preferences (toolbar)…") { [weak app] in
        if let app { settings.presentPreferences(in: app, style: .toolbar) }
    }
    let preferencesSplit = Button("Preferences (split)…") { [weak app] in
        if let app { settings.presentPreferences(in: app, style: .split) }
    }

    root.addSubview(pinnedHeight(group("Dialogs · Document (16.25) · Preferences (16.29)", [
        row([showDialog, openFile, openDocument]),
        row([preferencesToolbar, preferencesSplit]),
        dialogResult,
    ]), 6))
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

    root.addSubview(pinnedHeight(group("Text & Choices", [row([field, combo, popUp])]), 4))

    root.addSubview(pinnedHeight(group("Values", [row(spacing: 3, [slider, stepper, level])]), 4))
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

    // Phase 16: Matrix — a grid of cells as one control.
    let days = Matrix(titles: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"], columns: 4, mode: .highlight)
    let daysLabel = Label("highlight mode — Space toggles, arrows move")
    days.onSelectionChanged = { daysLabel.text = "selected: \($0.sorted().map { ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"][$0] }.joined(separator: ", "))" }
    let size = Matrix(titles: ["S", "M", "L", "XL"], columns: 4, mode: .radio)
    size.select([1])

    let left = VStack(spacing: 0)
    left.addSubview(pinnedHeight(group("DatePicker — .date (Space drops a month grid)", [date]), 4))
    left.addSubview(pinnedHeight(group("Matrix — .highlight (days) and .radio (size)", [days, row(spacing: 2, [size, daysLabel])]), 6))
    left.addSubview(group("DatePicker — .calendar", [calendar]))

    root.addSubview(left)
    root.addSubview(group("ColorPicker (named / palette / RGB tabs)", [color]))

    return root
}
