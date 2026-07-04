import Testing
@testable import TUIKit

// The App translates screen coordinates into window-local ones before
// routing; these helpers emulate that so drags read like the real flow.
@MainActor
private func send(_ window: Window, _ action: MouseInput.Action, atScreen point: Point) {
    var mouse = MouseInput(position: point, action: action, button: .left)
    mouse.position = point - window.frame.origin
    window.route(.mouse(mouse))
}

@Test @MainActor func floatingWindowMovesByTitleDrag() {
    let window = FloatingWindow(title: "Move me", frame: Rect(x: 2, y: 1, width: 12, height: 6))
    window.layoutIfNeeded()   // rendering does this before input in a real app

    send(window, .press, atScreen: Point(x: 7, y: 1))     // grab the title row
    send(window, .drag, atScreen: Point(x: 9, y: 2))      // pointer moves +2,+1
    #expect(window.frame == Rect(x: 4, y: 2, width: 12, height: 6))

    send(window, .drag, atScreen: Point(x: 6, y: 0))      // up-left, clamped at y 0
    #expect(window.frame == Rect(x: 1, y: 0, width: 12, height: 6))

    send(window, .release, atScreen: Point(x: 6, y: 0))
    send(window, .drag, atScreen: Point(x: 20, y: 3))
    #expect(window.frame.origin == Point(x: 1, y: 0), "release ends the move")
}

@Test @MainActor func floatingWindowResizesByCornerDrag() {
    let window = FloatingWindow(title: "Stretch", frame: Rect(x: 2, y: 1, width: 12, height: 6))
    window.layoutIfNeeded()

    send(window, .press, atScreen: Point(x: 13, y: 6))    // ◢ corner (local 11,5)
    send(window, .drag, atScreen: Point(x: 17, y: 8))     // local (15,7) → 16×8
    #expect(window.frame == Rect(x: 2, y: 1, width: 16, height: 8))

    send(window, .drag, atScreen: Point(x: 4, y: 2))      // tiny — clamps to minimum
    #expect(window.frame.size == window.minimumWindowSize)

    send(window, .release, atScreen: Point(x: 4, y: 2))
}

@Test @MainActor func floatingWindowCloseBoxAndEscapeAskToClose() {
    let window = FloatingWindow(title: "Bye", frame: Rect(x: 0, y: 0, width: 12, height: 4))
    window.layoutIfNeeded()   // the panel needs its frame for the [x] hit test

    var closes = 0
    window.onCloseRequest = { closes += 1 }

    // [x] sits at x 8..10 in a 12-wide panel.
    send(window, .press, atScreen: Point(x: 9, y: 0))
    #expect(closes == 1, "the close box asks to close")

    window.route(.key(KeyInput(key: .escape)))
    #expect(closes == 2, "Esc asks to close")

    #expect(!window.isModal, "floating windows participate in click-to-activate")
}

@Test @MainActor func desktopTilesBehindWindowsAndThemesThem() {
    let desktop = Desktop()
    desktop.frame = Rect(x: 0, y: 0, width: 8, height: 4)
    desktop.fillCharacter = "▒"
    desktop.theme = .ocean

    let window = Window(frame: Rect(x: 2, y: 1, width: 4, height: 2))
    desktop.addSubview(window)

    let buffer = SceneRenderer(root: desktop).render(size: Size(width: 8, height: 4))
    let lines = buffer.textLines()

    #expect(lines[0] == "▒▒▒▒▒▒▒▒")
    #expect(lines[1] == "▒▒    ▒▒", "the window's fill covers the weave")

    // The desktop's theme cascades into the (theme-less) window.
    #expect(buffer[Point(x: 0, y: 0)].style.background == .rgb(red: 34, green: 79, blue: 188))
    #expect(buffer[Point(x: 3, y: 1)].style.background == .rgb(red: 34, green: 79, blue: 188))
}

@Test @MainActor func appPresentsWindowsOntoItsDesktop() {
    let app = App(driver: HeadlessDriver(size: Size(width: 10, height: 4)))
    let window = Window(frame: Rect(x: 1, y: 1, width: 4, height: 2))

    app.present(window)
    #expect(window.superview === app.desktop)

    app.dismiss(window)
    #expect(window.superview == nil)
}
