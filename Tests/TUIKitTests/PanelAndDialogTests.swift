import Testing
@testable import TUIKit

// MARK: - Panel

@Test @MainActor func panelRendersBorderTitleAndContent() {
    let panel = Panel("Files")
    let label = Label("hello")
    label.anchors = .fill()
    panel.content.addSubview(label)

    let window = Window(frame: Rect(x: 0, y: 0, width: 20, height: 5))
    panel.frame = window.bounds
    window.addSubview(panel)

    let lines = SceneRenderer(root: window).render(size: Size(width: 20, height: 5)).textLines()

    #expect(lines[0].hasPrefix("┌─ Files "))
    #expect(lines[0].hasSuffix("┐"))
    #expect(lines[1].hasPrefix("│hello"))
    #expect(lines[4].hasPrefix("└"))
    #expect(lines[4].hasSuffix("┘"))
}

@Test @MainActor func panelCloseButtonRendersAndClicks() {
    let panel = Panel("Log")
    panel.showsCloseButton = true
    panel.frame = Rect(x: 0, y: 0, width: 20, height: 4)

    var closed = 0
    panel.onClose = { closed += 1 }

    let window = Window(frame: Rect(x: 0, y: 0, width: 20, height: 4))
    window.addSubview(panel)
    let lines = SceneRenderer(root: window).render(size: Size(width: 20, height: 4)).textLines()

    // [x] occupies x16..18, just inside the corner.
    #expect(lines[0].contains("[x]"))

    _ = panel.mouseEvent(MouseInput(position: Point(x: 17, y: 0), action: .press, button: .left))
    #expect(closed == 1)

    // Clicks elsewhere on the border are not close clicks.
    _ = panel.mouseEvent(MouseInput(position: Point(x: 5, y: 0), action: .press, button: .left))
    #expect(closed == 1)
}

// MARK: - Dialog

@Test @MainActor func dialogRendersChromeMessageAndButtons() {
    let dialog = Dialog(title: "Confirm", message: "Are you sure?")
    dialog.addButton("Cancel", isCancel: true).style = .bordered
    dialog.addButton("OK", isDefault: true).style = .bordered

    dialog.frame = Rect(origin: .zero, size: dialog.preferredSize)
    let lines = SceneRenderer(root: dialog).render(size: dialog.frame.size).textLines()

    #expect(lines[0].contains("Confirm"))
    #expect(lines[1].contains("Are you sure?"))
    #expect(lines[3].contains("[ Cancel ]"))
    #expect(lines[3].contains("[ OK ]"))
    #expect(lines[4].hasPrefix("└"))
}

@Test @MainActor func dialogPreferredSizeAndCentering() {
    let dialog = Dialog(title: "Confirm", message: "Are you sure?")
    dialog.addButton("Cancel", isCancel: true).style = .bordered
    dialog.addButton("OK", isDefault: true).style = .bordered

    // Width: buttons 16 + spacer/inter gaps 4 + chrome 4;
    // height: border 2 + message 1 + gap 1 + row 1.
    #expect(dialog.preferredSize == Size(width: 24, height: 5))

    dialog.sizeToFit(in: Size(width: 60, height: 20))
    #expect(dialog.frame == Rect(x: 18, y: 7, width: 24, height: 5))
}

@Test @MainActor func dialogEscReturnAndColdReturnRouting() {
    let dialog = Dialog(title: "Confirm", message: "Delete it?")
    var log: [String] = []

    dialog.addButton("Cancel", isCancel: true) { log.append("cancel") }
    let ok = dialog.addButton("Delete", isDefault: true) { log.append("delete") }
    dialog.onDismiss = { log.append("dismiss") }

    #expect(dialog.firstResponder === ok, "the default button starts focused")

    dialog.route(.key(KeyInput(key: .escape)))
    #expect(log == ["cancel", "dismiss"], "Esc activates the cancel button")

    dialog.route(.key(KeyInput(key: .enter)))
    #expect(log == ["cancel", "dismiss", "delete", "dismiss"], "Return activates the focused default")

    dialog.makeFirstResponder(nil)
    dialog.route(.key(KeyInput(key: .enter)))
    #expect(
        log == ["cancel", "dismiss", "delete", "dismiss", "delete", "dismiss"],
        "with no focus, Return still reaches the default through the cold pass"
    )
}

@Test @MainActor func dialogTabCyclesItsButtons() {
    let dialog = Dialog(title: "Confirm")
    let cancel = dialog.addButton("Cancel", isCancel: true)
    let ok = dialog.addButton("OK", isDefault: true)
    dialog.frame = Rect(origin: .zero, size: dialog.preferredSize)
    dialog.layoutIfNeeded()

    #expect(dialog.firstResponder === ok)

    dialog.route(.key(KeyInput(key: .tab)))
    #expect(dialog.firstResponder === cancel, "tab wraps around the button row")

    dialog.route(.key(KeyInput(key: .tab)))
    #expect(dialog.firstResponder === ok)
}
