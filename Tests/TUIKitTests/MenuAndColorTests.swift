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

@Test @MainActor func menuBarPaintsWholeStripWithHeaderSlot() {
    let (window, _, _, _) = makeMenuWindow()
    window.theme = .turbo   // header = black on light gray
    let buffer = SceneRenderer(root: window).render(size: window.frame.size)

    // A title cell (the 'F' of File) is black-on-gray from the header slot…
    let title = buffer[Point(x: 1, y: 0)].style
    #expect(title.foreground == .rgb(red: 0, green: 0, blue: 0))
    #expect(title.background == .rgb(red: 170, green: 170, blue: 170))

    // …and so is the empty tail of the bar (filled, not window-blue).
    #expect(buffer[Point(x: 29, y: 0)].style.background == .rgb(red: 170, green: 170, blue: 170))
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

@Test @MainActor func turboMenuDropdownUsesGrayChromeNotTheBackdrop() {
    let (window, bar, file, _) = makeMenuWindow()
    window.theme = .turbo   // nil context — the menu window resolves the gray base
    file.addItem("Open") {}
    file.addItem("Save") {}
    window.makeFirstResponder(bar)
    window.route(.key(KeyInput(key: .enter)))   // open the File dropdown

    let buffer = SceneRenderer(root: window).render(size: window.frame.size)
    var backgrounds: [TerminalColor] = []
    for y in 1..<7 {
        for x in 0..<12 {
            backgrounds.append(buffer[Point(x: x, y: y)].style.background)
        }
    }

    #expect(backgrounds.contains(.rgb(red: 170, green: 170, blue: 170)), "the dropdown fills with the gray base")
    #expect(!backgrounds.contains(.rgb(red: 85, green: 85, blue: 255)),
            "and is never tinted by the blue desktop backdrop (menus are base chrome, not .desktop context)")
}

@Test @MainActor func menuSeparatorWeldsIntoTheDropdownBorder() {
    let (window, bar, file, _) = makeMenuWindow()
    file.addItem("Open") {}
    file.addSeparator()
    file.addItem("Quit") {}
    window.makeFirstResponder(bar)
    window.route(.key(KeyInput(key: .enter)))   // open the File dropdown

    let buffer = SceneRenderer(root: window).render(size: window.frame.size)

    // Some row is the separator, welded into both side borders with ├ … ┤.
    var welded = false
    for y in 1..<7 {
        let row = (0..<14).map { buffer[Point(x: $0, y: y)].character }
        if row.contains("├"), row.contains("┤") {
            welded = true
        }
    }
    #expect(welded, "the separator connects to the menu border with ├ … ┤ tees")
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

// MARK: - Submenus

@MainActor
private func makeSubmenuWindow() -> (Window, MenuBar, Menu) {
    let window = Window(frame: Rect(x: 0, y: 0, width: 60, height: 20))
    let bar = MenuBar()

    let view = Menu("&View")
    view.addItem("&Fold All")
    let themes = view.addSubmenu("&Theme")
    themes.addItem("Turbo")
    themes.addItem("Ambiance")

    bar.addMenu(view)
    bar.frame = Rect(x: 0, y: 0, width: 60, height: 1)
    window.addSubview(bar)
    window.makeFirstResponder(bar)
    return (window, bar, view)
}

@MainActor
private func screenRows(_ window: Window) -> [String] {
    SceneRenderer(root: window).render(size: window.frame.size).textLines()
}

@Test @MainActor func aSubmenuItemOpensAChildInsteadOfActing() {
    let (window, bar, _) = makeSubmenuWindow()

    window.route(.key(KeyInput(key: .enter)))       // open View
    #expect(bar.isMenuOpen)
    #expect(screenRows(window).contains { $0.contains("▸") }, "the row says it has a child")

    window.route(.key(KeyInput(key: .down)))        // highlight Theme
    window.route(.key(KeyInput(key: .right)))       // cascade

    // A submenu item has no action of its own: opening the child IS what
    // activating it does.
    #expect(screenRows(window).contains { $0.contains("Turbo") }, "the child is on screen")
    #expect(screenRows(window).contains { $0.contains("Fold All") }, "beside its parent, not instead of it")
}

@Test @MainActor func closingAChildLeavesItsParentOpen() {
    let (window, bar, _) = makeSubmenuWindow()

    window.route(.key(KeyInput(key: .enter)))
    window.route(.key(KeyInput(key: .down)))
    window.route(.key(KeyInput(key: .right)))
    #expect(screenRows(window).contains { $0.contains("Turbo") })

    // Esc unwinds ONE level. Collapsing the whole cascade would make a
    // mis-aimed Right cost you the menu you were in.
    window.route(.key(KeyInput(key: .escape)))

    #expect(bar.isMenuOpen, "the parent survives")
    #expect(!screenRows(window).contains { $0.contains("Turbo") }, "and the child is gone")
}

@Test @MainActor func activatingASubmenuLeafRunsItAndClosesEverything() {
    let window = Window(frame: Rect(x: 0, y: 0, width: 60, height: 20))
    let bar = MenuBar()

    var applied: String?
    let view = Menu("&View")
    view.addItem("&Fold All")
    let themes = view.addSubmenu("&Theme")
    themes.addItem("Turbo") { applied = "Turbo" }

    bar.addMenu(view)
    bar.frame = Rect(x: 0, y: 0, width: 60, height: 1)
    window.addSubview(bar)
    window.makeFirstResponder(bar)

    window.route(.key(KeyInput(key: .enter)))
    window.route(.key(KeyInput(key: .down)))
    window.route(.key(KeyInput(key: .right)))
    window.route(.key(KeyInput(key: .enter)))

    #expect(applied == "Turbo")
    #expect(!bar.isMenuOpen, "a leaf activation exits menu mode entirely")
}

// MARK: - Accelerators across windows

/// A menu bar lives on the chrome window; the focused window is a document.
/// Its accelerators must still fire — that is the whole point of a menu bar.
@Test @MainActor func acceleratorsReachAMenuBarOnAnotherWindow() async throws {
    let driver = HeadlessDriver(size: Size(width: 40, height: 10))
    let app = App(driver: driver)

    let chrome = Window()
    chrome.fillsScreen = true
    let bar = MenuBar()
    bar.anchors = AnchorSet(leading: 0, trailing: 0, top: 0, height: 1)

    var fired = 0
    let file = Menu("&File")
    file.addItem("&New", keyEquivalent: KeyInput(key: .character("t"), modifiers: .control)) { fired += 1 }
    bar.addMenu(file)
    chrome.addSubview(bar)

    let session = Task { try await app.run(chrome) }
    while await driver.presentCount == 0 { await Task.yield() }

    // A document window on top takes focus, exactly as a real app's does.
    let document = FloatingWindow(title: "Doc", frame: Rect(x: 2, y: 2, width: 20, height: 6))
    app.present(document)
    #expect(app.keyWindow === document)

    await driver.send(.key(KeyInput(key: .character("t"), modifiers: .control)))
    await driver.send(.key(KeyInput(key: .character("c"), modifiers: .control)))
    try await session.value

    #expect(fired == 1, "the accelerator must survive another window having focus")
}

/// The fallback is accelerators only: a plain keystroke must not leak into a
/// window that does not have focus.
@Test @MainActor func plainKeysDoNotLeakToBackgroundWindows() async throws {
    let driver = HeadlessDriver(size: Size(width: 40, height: 10))
    let app = App(driver: driver)

    let background = Window()
    background.fillsScreen = true
    let field = TextField()
    field.frame = Rect(x: 0, y: 2, width: 20, height: 1)
    background.addSubview(field)

    let session = Task { try await app.run(background) }
    while await driver.presentCount == 0 { await Task.yield() }
    background.makeFirstResponder(field)

    let document = FloatingWindow(title: "Doc", frame: Rect(x: 2, y: 2, width: 20, height: 6))
    app.present(document)

    await driver.send(.key(KeyInput(key: .character("z"))))
    await driver.send(.key(KeyInput(key: .character("c"), modifiers: .control)))
    try await session.value

    #expect(field.text.isEmpty, "a background field must not receive typing")
}

@Test @MainActor func dropdownsWearTheMenuSurfaceNotTheWindowTheyCover() {
    // A context menu popped over Turbo's blue content window used to
    // inherit that surface — blue-on-blue (read as transparent) with the
    // content's double frame. Menus are floating chrome: they pin
    // themselves to the `menus` context, which resolves menus → base —
    // opaque gray, single border, wherever they pop.
    let window = Window(frame: Rect(x: 0, y: 0, width: 30, height: 10))
    window.theme = .turbo
    window.themeContext = .contentWindow

    let menu = Menu("")
    menu.addItem("History") {}   // highlighted (selection) — not asserted on
    menu.addItem("Copy") {}
    window.presentContextMenu(menu, at: Point(x: 2, y: 1))

    let buffer = SceneRenderer(root: window).render(size: Size(width: 30, height: 10))
    let lines = buffer.textLines()

    guard let row = lines.firstIndex(where: { $0.contains("Copy") }) else {
        Issue.record("no dropdown rendered")
        return
    }

    let base = Theme.turbo.resolved()
    let itemColumn = lines[row].distance(from: lines[row].startIndex, to: lines[row].range(of: "Copy")!.lowerBound)
    #expect(
        buffer[Point(x: itemColumn, y: row)].style.background == base.background,
        "opaque menu surface (chrome gray), not the window's blue"
    )

    // Single border lines — the menu look — even though the content
    // window's own frames are double.
    let borderRow = lines[row - 2]
    #expect(borderRow.contains("┌") && !borderRow.contains("╔"), "single-line menu frame: \(borderRow)")
}
