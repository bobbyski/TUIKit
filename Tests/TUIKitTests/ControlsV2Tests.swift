import Testing
@testable import TUIKit

// MARK: - ToggleButton

@Test @MainActor func toggleButtonTogglesAndReportsInStateColors() {
    let toggle = ToggleButton("Live", isOn: false)
    #expect(toggle.intrinsicContentSize == Size(width: 6, height: 1))

    var events: [Bool] = []
    toggle.onChange = { events.append($0) }

    let window = Window(frame: Rect(x: 0, y: 0, width: 10, height: 1))
    window.theme = .ocean
    toggle.frame = Rect(x: 0, y: 0, width: 6, height: 1)
    window.addSubview(toggle)

    // Off: placeholder (dim) colors.
    var buffer = SceneRenderer(root: window).render(size: Size(width: 10, height: 1))
    #expect(buffer[Point(x: 1, y: 0)].style.flags.contains(.dim))

    _ = toggle.keyDown(KeyInput(key: .character(" ")))
    #expect(toggle.isOn)

    // On: selection colors (ocean's accent background).
    buffer = SceneRenderer(root: window).render(size: Size(width: 10, height: 1))
    #expect(buffer[Point(x: 1, y: 0)].style.background == .rgb(red: 126, green: 190, blue: 255))

    _ = toggle.mouseEvent(MouseInput(position: Point(x: 2, y: 0), action: .press, button: .left))
    #expect(!toggle.isOn)
    #expect(events == [true, false])

    toggle.setOn(true)
    #expect(toggle.isOn)
    #expect(events == [true, false], "programmatic setOn is silent")
}

// MARK: - PopUpButton

@MainActor
private func makePopUp(buttonY: Int, windowHeight: Int = 10) -> (PopUpButton, Window) {
    let window = Window(frame: Rect(x: 0, y: 0, width: 24, height: windowHeight))
    let popUp = PopUpButton(items: ["Fast", "Balanced", "Accurate"], selectedIndex: 1)
    popUp.frame = Rect(x: 2, y: buttonY, width: 14, height: 1)
    window.addSubview(popUp)
    window.makeFirstResponder(popUp)
    return (popUp, window)
}

@Test @MainActor func popUpRendersSelectionAndOpensBelow() {
    let (popUp, window) = makePopUp(buttonY: 1)

    #expect(popUp.intrinsicContentSize == Size(width: 14, height: 1), "longest item + 6")

    let lines = SceneRenderer(root: window).render(size: window.frame.size).textLines()
    #expect(lines[1].contains("[ Balanced"))
    #expect(lines[1].contains("▾ ]"))

    _ = popUp.keyDown(KeyInput(key: .down))
    #expect(popUp.isOpen)

    // Room below: the popup (3 items + border = 5 rows) opens at y 2.
    let open = SceneRenderer(root: window).render(size: window.frame.size).textLines()
    #expect(open[2].contains("┌"))
    #expect(open[3].contains("Fast"))
    #expect(open[4].contains("▸Balanced"), "opens highlighting the current selection")
}

@Test @MainActor func popUpChoosesWithKeysAndRestoresFocus() {
    let (popUp, window) = makePopUp(buttonY: 1)
    var chosen: [Int] = []
    popUp.onSelectionChanged = { chosen.append($0) }

    _ = popUp.keyDown(KeyInput(key: .enter))
    window.route(.key(KeyInput(key: .down)))       // highlight Accurate
    window.route(.key(KeyInput(key: .enter)))      // choose it

    #expect(chosen == [2])
    #expect(popUp.selectedIndex == 2)
    #expect(!popUp.isOpen)
    #expect(window.firstResponder === popUp, "focus returns to the button")
}

@Test @MainActor func popUpOpensAboveWhenSpaceBelowIsTight() {
    let (popUp, window) = makePopUp(buttonY: 8, windowHeight: 10)

    _ = popUp.keyDown(KeyInput(key: .character(" ")))
    #expect(popUp.isOpen)

    // 3 items + border needs 5 rows; only 1 fits below y8 → opens above,
    // spanning rows 3...7.
    let lines = SceneRenderer(root: window).render(size: window.frame.size).textLines()
    #expect(lines[3].contains("┌"))
    #expect(lines[7].contains("└"))
}

@Test @MainActor func popUpEscCancelsAndFocusLossDismisses() {
    let (popUp, window) = makePopUp(buttonY: 1)
    var chosen: [Int] = []
    popUp.onSelectionChanged = { chosen.append($0) }

    _ = popUp.keyDown(KeyInput(key: .enter))
    window.route(.key(KeyInput(key: .escape)))
    #expect(!popUp.isOpen)
    #expect(window.firstResponder === popUp)

    // Reopen, then focus something else — the popup dismisses and the new
    // focus stands.
    let field = TextField()
    field.frame = Rect(x: 2, y: 3, width: 8, height: 1)
    window.addSubview(field)

    _ = popUp.keyDown(KeyInput(key: .enter))
    window.makeFirstResponder(field)
    #expect(!popUp.isOpen)
    #expect(window.firstResponder === field, "outside focus is not stolen back")
    #expect(chosen.isEmpty)
}

// MARK: - StatusBar

@Test @MainActor func statusBarResolvesSegmentWidths() {
    let bar = StatusBar()
    let status = Label("S")
    let toggle = Label("T")
    let popUp = Label("P")

    bar.addSegment(status, minimumWidth: 4, percentage: 100)
    bar.addSegment(toggle, minimumWidth: 6)
    bar.addSegment(popUp, minimumWidth: 4, maximumWidth: 8, percentage: 100)

    bar.frame = Rect(x: 0, y: 0, width: 30, height: 1)
    bar.layoutIfNeeded()

    // Available 28 (two separators); mins 14; leftover 14 split 7/7;
    // the third segment clamps at its maximum of 8.
    #expect(status.frame == Rect(x: 0, y: 0, width: 11, height: 1))
    #expect(toggle.frame == Rect(x: 12, y: 0, width: 6, height: 1))
    #expect(popUp.frame == Rect(x: 19, y: 0, width: 8, height: 1))

    let window = Window(frame: Rect(x: 0, y: 0, width: 30, height: 1))
    bar.removeFromSuperview()
    window.addSubview(bar)
    bar.frame = window.bounds

    let line = Array(SceneRenderer(root: window).render(size: Size(width: 30, height: 1)).textLines()[0])
    #expect(line[11] == "│")
    #expect(line[18] == "│")
}

@Test @MainActor func statusBarIntrinsicAndDefaultMinimums() {
    let bar = StatusBar()
    bar.addSegment(Label("abc"))       // natural width 3
    bar.addSegment(Label("de"))        // natural width 2

    #expect(bar.intrinsicContentSize == Size(width: 6, height: 1), "3 + 2 + one separator")
}

// MARK: - Divider

@Test @MainActor func dividerJoinsPanelBordersWithTees() {
    let window = Window(frame: Rect(x: 0, y: 0, width: 20, height: 7))
    let panel = Panel("D")
    panel.anchors = .fill()
    window.addSubview(panel)

    let divider = Divider(axis: .horizontal)
    divider.frame = Rect(x: 0, y: 2, width: 18, height: 1)   // full content width
    panel.content.addSubview(divider)

    let lines = SceneRenderer(root: window).render(size: Size(width: 20, height: 7)).textLines()

    #expect(lines[3].hasPrefix("├"))
    #expect(lines[3].hasSuffix("┤"))
    #expect(lines[3].contains("──────"))

    // Opting out leaves the panel border unbroken.
    divider.isConnected = false
    let plain = SceneRenderer(root: window).render(size: Size(width: 20, height: 7)).textLines()
    #expect(plain[3].hasPrefix("│─"))
    #expect(plain[3].hasSuffix("─│"))
}

@Test @MainActor func dividersCrossWithJunctions() {
    let container = View(frame: Rect(x: 0, y: 0, width: 20, height: 7))
    let horizontal = Divider(axis: .horizontal)
    horizontal.frame = Rect(x: 0, y: 3, width: 20, height: 1)
    let vertical = Divider(axis: .vertical)
    vertical.frame = Rect(x: 8, y: 0, width: 1, height: 7)
    container.addSubview(horizontal)
    container.addSubview(vertical)

    let window = Window(frame: Rect(x: 0, y: 0, width: 20, height: 7))
    window.addSubview(container)
    container.anchors = .fill()

    let lines = SceneRenderer(root: window).render(size: Size(width: 20, height: 7)).textLines()
    let row = Array(lines[3])

    #expect(row[8] == "┼", "crossing dividers meet in a ┼")
    #expect(row[0] == "─")
    #expect(Array(lines[0])[8] == "│")

    // A vertical divider *ending* on the line makes a tee instead.
    vertical.frame = Rect(x: 8, y: 0, width: 1, height: 3)
    let tee = SceneRenderer(root: window).render(size: Size(width: 20, height: 7)).textLines()
    #expect(Array(tee[3])[8] == "┴", "a line ending from above forms ┴")
}

@Test @MainActor func draggableDividerResizesItsNeighbors() {
    let container = View(frame: Rect(x: 0, y: 0, width: 20, height: 8))
    let top = View(frame: Rect(x: 0, y: 0, width: 20, height: 3))
    let divider = Divider(axis: .horizontal)
    divider.isDraggable = true
    divider.frame = Rect(x: 0, y: 3, width: 20, height: 1)
    let bottom = View(frame: Rect(x: 0, y: 4, width: 20, height: 4))

    container.addSubview(top)
    container.addSubview(divider)
    container.addSubview(bottom)

    var moves: [Int] = []
    divider.onMoved = { moves.append($0) }

    _ = divider.keyDown(KeyInput(key: .down))

    #expect(divider.frame.origin.y == 4)
    #expect(top.frame == Rect(x: 0, y: 0, width: 20, height: 4))
    #expect(bottom.frame == Rect(x: 0, y: 5, width: 20, height: 3))
    #expect(moves == [4])

    _ = divider.keyDown(KeyInput(key: .up))
    #expect(divider.frame.origin.y == 3)
    #expect(top.frame.size.height == 3)
    #expect(bottom.frame == Rect(x: 0, y: 4, width: 20, height: 4))
}
