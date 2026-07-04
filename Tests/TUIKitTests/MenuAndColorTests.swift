import Testing
@testable import TUIKit

// MARK: - MenuBar

@MainActor
private func makeMenuWindow() -> (Window, MenuBar, Menu, [String]) {
    let window = Window(frame: Rect(x: 0, y: 0, width: 30, height: 8))
    let bar = MenuBar()

    let file = Menu("File")
    let edit = Menu("Edit")
    edit.addItem("Undo")

    bar.addMenu(file)
    bar.addMenu(edit)

    bar.frame = Rect(x: 0, y: 0, width: 30, height: 1)
    window.addSubview(bar)
    return (window, bar, file, [])
}

@Test @MainActor func menuBarRendersTitlesWithHighlight() {
    let (window, bar, _, _) = makeMenuWindow()
    window.makeFirstResponder(bar)

    let lines = SceneRenderer(root: window).render(size: window.frame.size).textLines()
    #expect(lines[0].hasPrefix(" File  Edit "))
}

@Test @MainActor func menuBarStaysIdleUntilEngaged() {
    let (window, bar, _, _) = makeMenuWindow()
    window.makeFirstResponder(bar)

    // Focused but not yet engaged: no title is highlighted.
    let idle = SceneRenderer(root: window).render(size: window.frame.size)[Point(x: 1, y: 0)].style

    // The first arrow enters menu mode and lights up the current title.
    window.route(.key(KeyInput(key: .right)))
    let active = SceneRenderer(root: window).render(size: window.frame.size)[Point(x: 1, y: 0)].style
    #expect(active != idle, "engaging the bar highlights a title")

    // Esc leaves menu mode; the highlight clears again.
    window.route(.key(KeyInput(key: .escape)))
    let cleared = SceneRenderer(root: window).render(size: window.frame.size)[Point(x: 1, y: 0)].style
    #expect(cleared == idle, "Esc returns the bar to idle")
}

@Test @MainActor func menuHotKeyFiresWithoutOpeningTheMenu() {
    let (window, bar, file, _) = makeMenuWindow()

    var log: [String] = []
    file.addItem("Save", keyEquivalent: KeyInput(key: .character("s"), modifiers: .control)) {
        log.append("save")
    }

    window.route(.key(KeyInput(key: .character("s"), modifiers: .control)))
    #expect(log == ["save"])
    #expect(!bar.isMenuOpen)
}

@Test @MainActor func menuOpensNavigatesAndActivates() {
    let (window, bar, file, _) = makeMenuWindow()

    var log: [String] = []
    file.addItem("Open") { log.append("open") }
    file.addItem("Save") { log.append("save") }

    window.makeFirstResponder(bar)
    window.route(.key(KeyInput(key: .enter)))
    #expect(bar.isMenuOpen)

    // Dropdown renders below the bar with a border and both items.
    let lines = SceneRenderer(root: window).render(size: window.frame.size).textLines()
    #expect(lines[1].hasPrefix("┌"))
    #expect(lines[2].contains("Open"))
    #expect(lines[3].contains("Save"))

    window.route(.key(KeyInput(key: .down)))
    window.route(.key(KeyInput(key: .enter)))

    #expect(log == ["save"])
    #expect(!bar.isMenuOpen)
    #expect(window.firstResponder === bar, "focus returns to the bar")
}

@Test @MainActor func menuHighlightSkipsSeparatorsAndDisabledItems() {
    let (window, bar, file, _) = makeMenuWindow()

    var log: [String] = []
    file.addItem("First") { log.append("first") }
    file.addSeparator()
    let broken = file.addItem("Broken") { log.append("broken") }
    broken.isEnabled = false
    file.addItem("Last") { log.append("last") }

    window.makeFirstResponder(bar)
    window.route(.key(KeyInput(key: .enter)))
    window.route(.key(KeyInput(key: .down)))   // skips the separator and Broken
    window.route(.key(KeyInput(key: .enter)))

    #expect(log == ["last"])
}

@Test @MainActor func menuArrowsSlideBetweenOpenMenus() {
    let (window, bar, file, _) = makeMenuWindow()
    file.addItem("Open")

    window.makeFirstResponder(bar)
    window.route(.key(KeyInput(key: .enter)))
    window.route(.key(KeyInput(key: .right)))

    #expect(bar.isMenuOpen, "the neighboring menu is now open")

    let lines = SceneRenderer(root: window).render(size: window.frame.size).textLines()
    #expect(lines[2].contains("Undo"), "the Edit menu's dropdown is showing")
}

@Test @MainActor func menuEscapeClosesAndClicksToggleAndActivate() {
    let (window, bar, file, _) = makeMenuWindow()

    var log: [String] = []
    file.addItem("Open") { log.append("open") }

    // Click the File title to open, Esc to close.
    window.route(.mouse(MouseInput(position: Point(x: 2, y: 0), action: .press, button: .left)))
    #expect(bar.isMenuOpen)

    window.route(.key(KeyInput(key: .escape)))
    #expect(!bar.isMenuOpen)

    // Open again and click the first item row (dropdown starts at y1).
    window.route(.mouse(MouseInput(position: Point(x: 2, y: 0), action: .press, button: .left)))
    window.route(.mouse(MouseInput(position: Point(x: 3, y: 2), action: .press, button: .left)))
    #expect(log == ["open"])
    #expect(!bar.isMenuOpen)
}

// MARK: - ColorPicker

@Test @MainActor func namedSwatchGridNavigatesAndReports() {
    let grid = NamedSwatchGrid()
    grid.frame = Rect(x: 0, y: 0, width: 32, height: 2)

    var picked: [TerminalColor.NamedColor] = []
    grid.onSelectionChanged = { picked.append($0) }

    grid.select(.white)   // index 7, end of the first row

    _ = grid.keyDown(KeyInput(key: .down))
    #expect(picked == [.brightWhite], "down moves one row (index 15)")

    _ = grid.keyDown(KeyInput(key: .home))
    #expect(picked == [.brightWhite, .black])

    // Click the swatch at column 2, row 1 → index 10 (brightGreen).
    _ = grid.mouseEvent(MouseInput(position: Point(x: 9, y: 1), action: .press, button: .left))
    #expect(picked.last == .brightGreen)
}

@Test @MainActor func colorPickerReportsInteractionsThroughOneEvent() {
    let picker = ColorPicker(color: .named(.white))
    let window = Window(frame: Rect(x: 0, y: 0, width: 40, height: 8))
    picker.frame = window.bounds
    window.addSubview(picker)
    window.layoutIfNeeded()

    var events: [TerminalColor] = []
    picker.onColorChanged = { events.append($0) }

    // Focus order: tab bar first, then the swatch grid.
    window.focusNext()
    window.focusNext()
    window.route(.key(KeyInput(key: .down)))

    #expect(events == [.named(.brightWhite)])
    #expect(picker.color == .named(.brightWhite))
}

@Test @MainActor func colorPickerSetColorIsSilentAndDescribed() {
    let picker = ColorPicker(color: .named(.red))

    var events: [TerminalColor] = []
    picker.onColorChanged = { events.append($0) }

    picker.setColor(.palette(42))
    #expect(picker.color == .palette(42))

    picker.setColor(.rgb(red: 1, green: 2, blue: 3))
    #expect(picker.color == .rgb(red: 1, green: 2, blue: 3))
    #expect(events.isEmpty, "programmatic color changes are silent")

    #expect(ColorPreview.describe(.palette(42)) == "palette 42")
    #expect(ColorPreview.describe(.rgb(red: 1, green: 2, blue: 3)) == "rgb(1, 2, 3)")
    #expect(ColorPreview.describe(.named(.brightCyan)) == "brightCyan")
}
