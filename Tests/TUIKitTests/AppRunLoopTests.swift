import Testing
@testable import TUIKit

/// Focusable view that fills itself with a character and mutates on keys —
/// enough behavior to exercise the full input → state → render loop.
@MainActor
private final class EchoView: TUIView {
    var character: Character = "."

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ painter: Painter) {
        painter.fill(bounds, with: TerminalCell(character: character))
    }

    override func keyDown(_ key: KeyInput) -> Bool {
        guard case .character(let typed) = key.key, key.modifiers.isEmpty else {
            return false
        }

        character = typed
        setNeedsDisplay()
        return true
    }
}

@Test @MainActor func appRunsRoutesRendersAndStopsGracefully() async throws {
    let driver = HeadlessDriver(size: Size(width: 6, height: 2))
    let app = App(driver: driver)
    let window = Window()
    let echo = EchoView(frame: Rect(x: 0, y: 0, width: 6, height: 2))

    window.addSubview(echo)
    window.makeFirstResponder(echo)

    let session = Task {
        try await app.run(window)
    }

    // Wait for the initial frame.
    while await driver.presentCount == 0 {
        await Task.yield()
    }

    #expect(await driver.snapshotText() == ["......", "......"])
    #expect(app.isRunning)
    #expect(window.fillsScreen, "zero-frame window fills the screen")
    #expect(window.frame.size == Size(width: 6, height: 2))

    // A key routes to the focused view and the next frame reflects it.
    await driver.send(.key(KeyInput(key: .character("x"))))

    while await driver.snapshotText() != ["xxxxxx", "xxxxxx"] {
        await Task.yield()
    }

    // Resize reshapes the screen root, the window, and the next frame.
    await driver.resize(to: Size(width: 4, height: 1))

    while await driver.snapshotText() != ["xxxx"] {
        await Task.yield()
    }

    #expect(window.frame.size == Size(width: 4, height: 1))

    // Ctrl+C stops the loop; run() returns and the driver is ended.
    await driver.send(.key(KeyInput(key: .character("c"), modifiers: .control)))

    try await session.value

    #expect(!app.isRunning)
    #expect(await driver.isRunning == false, "driver.end() must run on stop")
}

@Test @MainActor func unchangedFramesAreNotRepresented() async throws {
    let driver = HeadlessDriver(size: Size(width: 4, height: 1))
    let app = App(driver: driver)
    let window = Window()
    let echo = EchoView(frame: Rect(x: 0, y: 0, width: 4, height: 1))

    window.addSubview(echo)
    window.makeFirstResponder(echo)

    let session = Task {
        try await app.run(window)
    }

    while await driver.presentCount == 0 {
        await Task.yield()
    }

    let baseline = await driver.presentCount

    // An unhandled key (view declines modified characters) changes nothing,
    // so no new frame may be presented.
    await driver.send(.key(KeyInput(key: .character("y"), modifiers: .alt)))
    await driver.send(.key(KeyInput(key: .character("c"), modifiers: .control)))

    try await session.value

    #expect(await driver.presentCount == baseline, "clean trees must not re-present")
}

@Test @MainActor func modalWindowOwnsInputUntilDismissed() async throws {
    let driver = HeadlessDriver(size: Size(width: 8, height: 4))
    let app = App(driver: driver)

    let base = Window()
    let baseEcho = EchoView(frame: Rect(x: 0, y: 0, width: 8, height: 4))
    base.addSubview(baseEcho)
    base.makeFirstResponder(baseEcho)

    let session = Task {
        try await app.run(base)
    }

    while await driver.presentCount == 0 {
        await Task.yield()
    }

    // Present a modal on top; it becomes the key window.
    let modal = Window(frame: Rect(x: 2, y: 1, width: 4, height: 2))
    let modalEcho = EchoView(frame: Rect(x: 0, y: 0, width: 4, height: 2))
    modal.addSubview(modalEcho)
    modal.makeFirstResponder(modalEcho)
    app.present(modal)

    #expect(app.keyWindow === modal)

    await driver.send(.key(KeyInput(key: .character("m"))))

    while modalEcho.character != "m" {
        await Task.yield()
    }

    #expect(baseEcho.character == ".", "base window must not see modal input")

    // Dismissing returns input to the base window.
    app.dismiss(modal)
    #expect(app.keyWindow === base)

    await driver.send(.key(KeyInput(key: .character("b"))))

    while baseEcho.character != "b" {
        await Task.yield()
    }

    await driver.send(.key(KeyInput(key: .character("c"), modifiers: .control)))
    try await session.value
}

/// Records the mouse events it receives, separating immediate press/release
/// from the debounced `.click` (with its count).
@MainActor
private final class ClickRecorder: TUIView {
    var presses = 0
    var clicks: [Int] = []

    override var acceptsFirstResponder: Bool { true }

    override func mouseEvent(_ mouse: MouseInput) -> Bool {
        switch mouse.action {
        case .press: presses += 1
        case .click: clicks.append(mouse.clickCount)
        default: break
        }
        return true   // consume the gesture so it's ours
    }
}

@Test @MainActor func multiClickGuardCoalescesPressesIntoClickCounts() async throws {
    let driver = HeadlessDriver(size: Size(width: 10, height: 4))
    let clock = ManualTimerSource()
    let app = App(driver: driver, timerSource: clock)

    let window = Window(frame: Rect(x: 0, y: 0, width: 10, height: 4))
    let recorder = ClickRecorder(frame: Rect(x: 0, y: 0, width: 10, height: 4))
    window.addSubview(recorder)

    let session = Task { try await app.run(window) }
    while await driver.presentCount == 0 {
        await Task.yield()
    }

    func click(at point: Point) async {
        await driver.send(.mouse(MouseInput(position: point, action: .press, button: .left)))
        await driver.send(.mouse(MouseInput(position: point, action: .release, button: .left)))
    }

    // One click: press/release land immediately, but the `.click` is held back
    // for the guard — so nothing fires ahead of a possible double.
    await click(at: Point(x: 3, y: 1))
    while await clock.streamCount < 1 {
        await Task.yield()
    }
    #expect(recorder.presses == 1, "the low-level press is immediate")
    #expect(recorder.clicks.isEmpty, "no click event before the guard settles")

    // Guard elapses with no follow-up → a single click (count 1).
    clock.fire()
    while recorder.clicks.isEmpty {
        await Task.yield()
    }
    #expect(recorder.clicks == [1])

    // Two clicks inside one guard window coalesce into a double (count 2) —
    // and the single is never delivered on its own.
    await click(at: Point(x: 3, y: 1))
    await click(at: Point(x: 3, y: 1))
    while await clock.streamCount < 3 {
        await Task.yield()
    }
    #expect(recorder.clicks == [1], "the double is still pending, not yet delivered")

    clock.fire()
    while recorder.clicks.count < 2 {
        await Task.yield()
    }
    #expect(recorder.clicks == [1, 2], "two quick clicks arrive as one double-click")

    await driver.send(.key(KeyInput(key: .character("c"), modifiers: .control)))
    try await session.value
}

@Test @MainActor func pressOutsideAnOpenMenuDismissesItButInsideSelects() async throws {
    let driver = HeadlessDriver(size: Size(width: 20, height: 8))
    let app = App(driver: driver)

    let root = Window(frame: Rect(x: 0, y: 0, width: 20, height: 8))
    let bar = MenuBar()
    let file = Menu("File")
    var opened = 0
    file.addItem("Open") { opened += 1 }
    file.addItem("Save") {}
    bar.addMenu(file)
    bar.frame = Rect(x: 0, y: 0, width: 20, height: 1)
    root.addSubview(bar)

    let session = Task { try await app.run(root) }
    while await driver.presentCount == 0 {
        await Task.yield()
    }

    // A press well outside the open dropdown dismisses it — no item fires.
    bar.openMenu(at: 0)
    #expect(bar.isMenuOpen)
    await driver.send(.mouse(MouseInput(position: Point(x: 18, y: 6), action: .press, button: .left)))
    while bar.isMenuOpen {
        await Task.yield()
    }
    #expect(opened == 0, "an outside press only dismisses; it does not activate an item")

    // A press *inside* the dropdown still activates the item under it. The
    // dropdown sits at (0,1); its first item row is y = 1 (origin) + 1 (border).
    bar.openMenu(at: 0)
    #expect(bar.isMenuOpen)
    await driver.send(.mouse(MouseInput(position: Point(x: 2, y: 2), action: .press, button: .left)))
    while opened == 0 {
        await Task.yield()
    }
    #expect(!bar.isMenuOpen, "activating an item closes the menu")

    await driver.send(.key(KeyInput(key: .character("c"), modifiers: .control)))
    try await session.value
}

@Test @MainActor func clickActivatesNonModalWindowsButNotPastAModal() async throws {
    let driver = HeadlessDriver(size: Size(width: 10, height: 4))
    let app = App(driver: driver)

    // Two side-by-side non-modal windows (base is NOT full-screen).
    let base = Window(frame: Rect(x: 0, y: 0, width: 4, height: 4))
    base.addSubview(EchoView(frame: Rect(x: 0, y: 0, width: 4, height: 4)))

    let session = Task {
        try await app.run(base)
    }

    while await driver.presentCount == 0 {
        await Task.yield()
    }

    let float = Window(frame: Rect(x: 4, y: 0, width: 4, height: 4))
    float.addSubview(EchoView(frame: Rect(x: 0, y: 0, width: 4, height: 4)))
    app.present(float)
    #expect(app.keyWindow === float)

    // A press on the base window raises and keys it (activate-and-forward).
    await driver.send(.mouse(MouseInput(position: Point(x: 1, y: 1), action: .press, button: .left)))

    while app.keyWindow !== base {
        await Task.yield()
    }

    // And clicking the float hands key status back.
    await driver.send(.mouse(MouseInput(position: Point(x: 5, y: 1), action: .press, button: .left)))

    while app.keyWindow !== float {
        await Task.yield()
    }

    // A modal on top swallows outside presses: key status must not move.
    let dialog = Window(frame: Rect(x: 8, y: 0, width: 2, height: 2))
    dialog.isModal = true
    let dialogEcho = EchoView(frame: Rect(x: 0, y: 0, width: 2, height: 2))
    dialog.addSubview(dialogEcho)
    dialog.makeFirstResponder(dialogEcho)
    app.present(dialog)
    #expect(app.keyWindow === dialog)

    await driver.send(.mouse(MouseInput(position: Point(x: 1, y: 1), action: .press, button: .left)))
    await driver.send(.key(KeyInput(key: .character("z"))))   // fence: processed after the press

    while dialogEcho.character != "z" {
        await Task.yield()
    }

    #expect(app.keyWindow === dialog, "modal key window swallows outside clicks")

    await driver.send(.key(KeyInput(key: .character("c"), modifiers: .control)))
    try await session.value
}
