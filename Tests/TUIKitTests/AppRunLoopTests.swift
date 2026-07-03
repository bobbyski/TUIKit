import Testing
@testable import TUIKit

/// Focusable view that fills itself with a character and mutates on keys —
/// enough behavior to exercise the full input → state → render loop.
@MainActor
private final class EchoView: View {
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
