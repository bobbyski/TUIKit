import Testing
@testable import TUIKit

@MainActor
private func desktopHosting(_ window: FloatingWindow, size: Size = Size(width: 80, height: 24)) -> Desktop {
    let desktop = Desktop()
    desktop.frame = Rect(origin: .zero, size: size)
    desktop.addSubview(window)
    desktop.layoutIfNeeded()
    return desktop
}

@Test @MainActor func floatingWindowMaximizeAndRestore() {
    let window = FloatingWindow(title: "W", frame: Rect(x: 10, y: 5, width: 30, height: 12))
    let desktop = desktopHosting(window)
    _ = desktop   // keep the (weakly-referenced) superview alive for the test

    #expect(window.windowState == .normal)

    window.maximize()
    #expect(window.windowState == .maximized)
    #expect(window.frame == Rect(x: 0, y: 0, width: 80, height: 24), "fills the desktop")

    window.restore()
    #expect(window.windowState == .normal)
    #expect(window.frame == Rect(x: 10, y: 5, width: 30, height: 12), "returns to the exact saved frame")
}

@Test @MainActor func floatingWindowMaximizeRespectsInsets() {
    let window = FloatingWindow(title: "W", frame: Rect(x: 10, y: 5, width: 30, height: 12))
    window.maximizeInsets = EdgeInsets(top: 1, bottom: 1)
    let desktop = desktopHosting(window)
    _ = desktop   // keep the (weakly-referenced) superview alive for the test

    window.maximize()
    #expect(window.frame == Rect(x: 0, y: 1, width: 80, height: 22), "leaves the top and bottom rows clear")
}

@Test @MainActor func floatingWindowToggleAndDragExitsMaximized() {
    let window = FloatingWindow(title: "W", frame: Rect(x: 10, y: 5, width: 30, height: 12))
    let desktop = desktopHosting(window)
    _ = desktop   // keep the (weakly-referenced) superview alive for the test

    window.toggleMaximize()
    #expect(window.windowState == .maximized)

    // Grabbing the title bar of a maximized window hands geometry back to the
    // user: it becomes a normal, draggable frame again.
    _ = window.route(.mouse(MouseInput(position: Point(x: 5, y: 0), action: .press, button: .left)))
    #expect(window.windowState == .normal)

    window.toggleMaximize()
    #expect(window.windowState == .maximized)
}

@Test @MainActor func panelMaximizeButtonDrawsAndFires() {
    let panel = Panel("Hi")
    panel.showsMaximizeButton = true
    let window = Window(frame: Rect(x: 0, y: 0, width: 20, height: 5))
    panel.frame = window.bounds
    window.addSubview(panel)

    var maximized = 0
    panel.onMaximize = { maximized += 1 }

    // Normal state shows [+]; the box sits at width-8 = x12..14.
    let normal = SceneRenderer(root: window).render(size: Size(width: 20, height: 5)).textLines()[0]
    #expect(normal.contains("[+]"))

    _ = panel.mouseEvent(MouseInput(position: Point(x: 13, y: 0), action: .press, button: .left))
    #expect(maximized == 1)

    // Maximized state flips the glyph to [=].
    panel.isMaximized = true
    let restored = SceneRenderer(root: window).render(size: Size(width: 20, height: 5)).textLines()[0]
    #expect(restored.contains("[=]"))
}
