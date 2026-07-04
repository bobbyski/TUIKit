import Testing
@testable import TUIKit

// MARK: - Slider

@Test @MainActor func sliderStepsClicksAndClamps() {
    let slider = Slider(value: 0, in: 0...100, step: 10)
    slider.frame = Rect(x: 0, y: 0, width: 12, height: 1)   // inner 10, positions 0-9

    var events: [Int] = []
    slider.onValueChanged = { events.append($0) }

    _ = slider.keyDown(KeyInput(key: .right))
    #expect(slider.value == 10)

    _ = slider.keyDown(KeyInput(key: .end))
    #expect(slider.value == 100)

    _ = slider.keyDown(KeyInput(key: .right))
    #expect(slider.value == 100, "clamped at the top, no event")

    // Click mid-track: position 5 of 9 → (5*100 + 4) / 9 = 56.
    _ = slider.mouseEvent(MouseInput(position: Point(x: 6, y: 0), action: .press, button: .left))
    #expect(slider.value == 56)

    _ = slider.mouseEvent(MouseInput(position: Point(x: 1, y: 0), action: .drag, button: .left))
    #expect(slider.value == 0, "drag to the left end")

    #expect(events == [10, 100, 56, 0])

    slider.setValue(40)
    #expect(slider.value == 40)
    #expect(events == [10, 100, 56, 0], "programmatic setValue is silent")
}

@Test @MainActor func sliderRendersTrackAndHandle() {
    let slider = Slider(value: 50, in: 0...100)
    let window = Window(frame: Rect(x: 0, y: 0, width: 12, height: 1))
    slider.frame = window.bounds
    window.addSubview(slider)

    let line = Array(SceneRenderer(root: window).render(size: Size(width: 12, height: 1)).textLines()[0])
    #expect(line[0] == "├")
    #expect(line[11] == "┤")
    #expect(line[5] == "█", "50% sits at inner position 4 of 9 → column 5")
    #expect(line[2] == "─")
}

// MARK: - LevelIndicator

@Test @MainActor func levelIndicatorRendersAndEdits() {
    let level = LevelIndicator(value: 3, maximum: 5, style: .rating)
    level.isEditable = true
    level.frame = Rect(x: 0, y: 0, width: 5, height: 1)

    var events: [Int] = []
    level.onValueChanged = { events.append($0) }

    let window = Window(frame: Rect(x: 0, y: 0, width: 6, height: 1))
    window.addSubview(level)
    let line = SceneRenderer(root: window).render(size: Size(width: 6, height: 1)).textLines()[0]
    #expect(line.hasPrefix("★★★☆☆"))

    _ = level.keyDown(KeyInput(key: .right))
    #expect(level.value == 4)

    _ = level.mouseEvent(MouseInput(position: Point(x: 1, y: 0), action: .press, button: .left))
    #expect(level.value == 2, "click sets that level")

    _ = level.mouseEvent(MouseInput(position: Point(x: 1, y: 0), action: .press, button: .left))
    #expect(level.value == 0, "clicking the current level clears")

    #expect(events == [4, 2, 0])
}

// MARK: - PathControl

@Test @MainActor func pathControlWalksAndSelectsPrefixes() {
    let crumbs = PathControl(path: "/Users/bobby/Projects")
    crumbs.frame = Rect(x: 0, y: 0, width: 30, height: 1)

    var selected: [String] = []
    crumbs.onPathSelected = { selected.append($0) }

    #expect(crumbs.intrinsicContentSize == Size(width: 5 + 3 + 5 + 3 + 8, height: 1))

    // Keyboard: walk from the last crumb to the middle one and choose.
    _ = crumbs.keyDown(KeyInput(key: .left))
    _ = crumbs.keyDown(KeyInput(key: .enter))
    #expect(selected == ["/Users/bobby"])

    // Click the first crumb ("Users" spans x0-4).
    _ = crumbs.mouseEvent(MouseInput(position: Point(x: 2, y: 0), action: .press, button: .left))
    #expect(selected == ["/Users/bobby", "/Users"])

    crumbs.setPath("relative/path")
    _ = crumbs.keyDown(KeyInput(key: .home))
    _ = crumbs.keyDown(KeyInput(key: .enter))
    #expect(selected.last == "relative", "relative paths stay relative")
}

@Test @MainActor func pathControlScrollsToShowTheTail() {
    // TUIKitDemo(10) ▸ Resources(9) ▸ presidents.json(15) = 40 cells, in 16.
    let crumbs = PathControl(path: "TUIKitDemo/Resources/presidents.json")
    let window = Window(frame: Rect(x: 0, y: 0, width: 16, height: 1))
    crumbs.frame = window.bounds
    window.addSubview(crumbs)

    let line = SceneRenderer(root: window).render(size: Size(width: 16, height: 1)).textLines()[0]
    #expect(line.hasSuffix("presidents.json"), "the filename stays visible on the right")
    #expect(!line.contains("TUIKitDemo"), "leading crumbs scroll off the left")

    // Clicks still map through the scroll to the correct crumb.
    var selected: [String] = []
    crumbs.onPathSelected = { selected.append($0) }
    _ = crumbs.mouseEvent(MouseInput(position: Point(x: 4, y: 0), action: .press, button: .left))
    #expect(selected == ["TUIKitDemo/Resources/presidents.json"])
}

// MARK: - DisclosureGroup

@Test @MainActor func disclosureGroupTogglesAndReflows() {
    let group = DisclosureGroup("Advanced")
    let inner = Label("secret")
    inner.anchors = .fill()
    group.content.addSubview(inner)
    group.content.frame = Rect(x: 0, y: 0, width: 10, height: 1)

    var events: [Bool] = []
    group.onExpansionChanged = { events.append($0) }

    #expect(!group.isExpanded)
    #expect(group.content.isHidden)
    #expect(group.intrinsicContentSize?.height == 1)

    _ = group.keyDown(KeyInput(key: .character(" ")))
    #expect(group.isExpanded)
    #expect(!group.content.isHidden)
    #expect(
        group.intrinsicContentSize?.height == 2,
        "expanded height includes the content's natural height (via its children)"
    )

    let window = Window(frame: Rect(x: 0, y: 0, width: 12, height: 3))
    group.anchors = .fill()
    window.addSubview(group)
    let lines = SceneRenderer(root: window).render(size: Size(width: 12, height: 3)).textLines()
    #expect(lines[0].hasPrefix("▾ Advanced"))
    #expect(lines[1].hasPrefix("secret"))

    _ = group.mouseEvent(MouseInput(position: Point(x: 3, y: 0), action: .press, button: .left))
    #expect(!group.isExpanded)
    #expect(events == [true, false])

    group.setExpanded(true)
    #expect(events == [true, false], "programmatic setExpanded is silent")
}

// MARK: - ComboBox

@Test @MainActor func comboBoxTypesPicksAndReports() {
    let window = Window(frame: Rect(x: 0, y: 0, width: 24, height: 8))
    let combo = ComboBox(items: ["Menlo", "Monaco", "SF Mono"], placeholder: "font")
    combo.frame = Rect(x: 2, y: 1, width: 14, height: 1)
    window.addSubview(combo)
    window.layoutIfNeeded()

    var changed: [String] = []
    var picked: [Int] = []
    combo.onChanged = { changed.append($0) }
    combo.onSelectionChanged = { picked.append($0) }

    // Click the disclosure cell; pick the second item.
    _ = combo.mouseEvent(MouseInput(position: Point(x: 13, y: 0), action: .press, button: .left))
    #expect(combo.isOpen)

    window.route(.key(KeyInput(key: .down)))
    window.route(.key(KeyInput(key: .enter)))

    #expect(!combo.isOpen)
    #expect(combo.text == "Monaco")
    #expect(picked == [1])
    #expect(changed.last == "Monaco")
    #expect(window.firstResponder === nil || window.firstResponder is TextField, "focus lands in the field")

    // ↓ bubbling from the field reopens, highlighting the current text.
    window.route(.key(KeyInput(key: .down)))
    #expect(combo.isOpen)

    window.route(.key(KeyInput(key: .escape)))
    #expect(!combo.isOpen)
}

// MARK: - Context menus

@Test @MainActor func rightClickPresentsAndActivatesContextMenu() {
    let window = Window(frame: Rect(x: 0, y: 0, width: 30, height: 10))
    let list = ListView(items: ["a.txt", "b.txt"])
    list.frame = Rect(x: 0, y: 0, width: 14, height: 4)
    window.addSubview(list)

    var log: [String] = []
    let menu = Menu("Actions")
    menu.addItem("Open") { log.append("open") }
    menu.addItem("Delete") { log.append("delete") }
    list.contextMenu = menu

    window.route(.mouse(MouseInput(position: Point(x: 3, y: 1), action: .press, button: .right)))

    let lines = SceneRenderer(root: window).render(size: Size(width: 30, height: 10)).textLines()
    #expect(lines[2].contains("┌"), "menu opens below the pointer")
    #expect(lines[3].contains("Open"))
    #expect(lines[4].contains("Delete"))

    window.route(.key(KeyInput(key: .down)))
    window.route(.key(KeyInput(key: .enter)))
    #expect(log == ["delete"])

    // Esc dismisses a reopened menu without activating anything.
    window.route(.mouse(MouseInput(position: Point(x: 3, y: 1), action: .press, button: .right)))
    window.route(.key(KeyInput(key: .escape)))
    #expect(log == ["delete"])

    // Right-click where no menu is attached does nothing.
    window.route(.mouse(MouseInput(position: Point(x: 20, y: 8), action: .press, button: .right)))
    let after = SceneRenderer(root: window).render(size: Size(width: 30, height: 10)).textLines()
    #expect(!after[9].contains("┌"))
}

// MARK: - Toolbar

@Test @MainActor func toolbarFitsItemsSkipsDisabledAndActivates() {
    let bar = Toolbar()
    bar.style = .bordered   // assert the bracketed layout geometry
    var log: [String] = []
    bar.addItem("Run") { log.append("run") }
    let stop = bar.addItem("Stop") { log.append("stop") }
    bar.addItem("Reset") { log.append("reset") }
    stop.isEnabled = false

    let window = Window(frame: Rect(x: 0, y: 0, width: 30, height: 1))
    bar.frame = window.bounds
    window.addSubview(bar)

    #expect(bar.intrinsicContentSize == Size(width: 26, height: 1), "7 + 8 + 9 + 2 separators")

    let line = SceneRenderer(root: window).render(size: Size(width: 30, height: 1)).textLines()[0]
    #expect(line.hasPrefix("[ Run ] [ Stop ] [ Reset ]"))

    window.makeFirstResponder(bar)

    // Right from Run skips the disabled Stop and lands on Reset.
    window.route(.key(KeyInput(key: .right)))
    window.route(.key(KeyInput(key: .enter)))
    #expect(log == ["reset"])

    // Home returns to Run; the disabled Stop never activates.
    window.route(.key(KeyInput(key: .home)))
    window.route(.key(KeyInput(key: .enter)))
    #expect(log == ["reset", "run"])
}

@Test @MainActor func toolbarOverflowMenuHoldsTrailingItems() {
    let bar = Toolbar()
    bar.style = .bordered   // assert the bracketed overflow geometry
    var log: [String] = []
    bar.addItem("Run") { log.append("run") }
    bar.addItem("Stop") { log.append("stop") }
    bar.addItem("Reset") { log.append("reset") }

    let window = Window(frame: Rect(x: 0, y: 0, width: 20, height: 8))
    bar.frame = Rect(x: 0, y: 0, width: 20, height: 1)
    window.addSubview(bar)

    // Too narrow for all three: only Run fits, the rest collapse into ».
    let line = SceneRenderer(root: window).render(size: Size(width: 20, height: 8)).textLines()[0]
    #expect(line.hasPrefix("[ Run ] [ » ]"))

    // Clicking the » button opens a menu holding the hidden items.
    window.route(.mouse(MouseInput(position: Point(x: 9, y: 0), action: .press, button: .left)))
    let lines = SceneRenderer(root: window).render(size: Size(width: 20, height: 8)).textLines()
    #expect(lines[1].contains("┌"), "overflow menu opens below the button")
    #expect(lines.contains { $0.contains("Stop") })
    #expect(lines.contains { $0.contains("Reset") })

    // Highlight moves Stop → Reset, and Return activates the hidden item.
    window.route(.key(KeyInput(key: .down)))
    window.route(.key(KeyInput(key: .enter)))
    #expect(log == ["reset"])
}

// MARK: - Tinted control style (color instead of brackets)

@Test @MainActor func tintedButtonUsesAccentColorNotBrackets() {
    let window = Window(frame: Rect(x: 0, y: 0, width: 12, height: 1))
    let button = Button("Go")   // default is .tinted
    button.frame = Rect(x: 0, y: 0, width: 4, height: 1)
    window.addSubview(button)

    let buffer = SceneRenderer(root: window).render(size: Size(width: 12, height: 1))
    let line = buffer.textLines()[0]
    #expect(line.hasPrefix(" Go "))
    #expect(!line.contains("["), "the tinted default drops the brackets")

    // The label is drawn in the theme accent, bold.
    #expect(buffer[Point(x: 1, y: 0)].style.foreground == .named(.brightCyan))
    #expect(buffer[Point(x: 1, y: 0)].style.flags.contains(.bold))
}

@Test @MainActor func tintedToolbarDropsBrackets() {
    let bar = Toolbar()   // default is .tinted
    bar.addItem("Run") {}
    bar.addItem("Stop") {}

    let window = Window(frame: Rect(x: 0, y: 0, width: 20, height: 1))
    bar.frame = window.bounds
    window.addSubview(bar)

    let line = SceneRenderer(root: window).render(size: Size(width: 20, height: 1)).textLines()[0]
    #expect(line.contains("Run") && line.contains("Stop"))
    #expect(!line.contains("["), "tinted toolbar items have no brackets")
}

// MARK: - StatusBar welding

@Test @MainActor func statusBarSeparatorsWeldIntoThePanelBottom() {
    let window = Window(frame: Rect(x: 0, y: 0, width: 20, height: 6))
    let panel = Panel("S")
    panel.anchors = .fill()
    window.addSubview(panel)

    let bar = StatusBar()
    bar.addSegment(Label("A"), percentage: 100)
    bar.addSegment(Label("B"), minimumWidth: 4)
    bar.anchors = AnchorSet(leading: 0, trailing: 0, bottom: 0, height: 1)
    panel.content.addSubview(bar)

    let lines = SceneRenderer(root: window).render(size: Size(width: 20, height: 6)).textLines()

    // Bar on the last content row (window row 4): A resolves to 13, so the
    // separator sits at content x13 → window x14, welded below with ┴.
    #expect(Array(lines[4])[14] == "│")
    #expect(Array(lines[5])[14] == "┴", "the separator joins the panel's bottom border")
}

// MARK: - TabView separator

@Test @MainActor func tabSeparatorWeldsIntoAPanelBorder() {
    let window = Window(frame: Rect(x: 0, y: 0, width: 20, height: 8))
    let panel = Panel("T")
    panel.anchors = .fill()
    window.addSubview(panel)

    let tabs = TabView()
    tabs.addTab("One", content: Label("1"))
    tabs.anchors = .fill()
    panel.content.addSubview(tabs)

    let lines = SceneRenderer(root: window).render(size: Size(width: 20, height: 8)).textLines()

    // Tab bar at window row 1, separator at row 2 — welded with tees.
    #expect(lines[2].hasPrefix("├"))
    #expect(lines[2].hasSuffix("┤"))
    #expect(lines[2].contains("──────"))
}
