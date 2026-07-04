import Testing
@testable import TUIKit

@MainActor
private func renderedLines(_ view: TUIView, size: Size, focused: Bool = false) -> [String] {
    let window = Window(frame: Rect(origin: .zero, size: size))
    view.frame = Rect(origin: .zero, size: size)
    window.addSubview(view)

    if focused {
        window.makeFirstResponder(view)
    }

    return SceneRenderer(root: window).render(size: size).textLines()
}

// MARK: - SegmentedControl

@Test @MainActor func segmentedRendersSegments() {
    let control = SegmentedControl(["Day", "Week"], selectedIndex: 1)

    // " Day " (5) + " Week " (6) = 11 wide.
    #expect(control.intrinsicContentSize == Size(width: 11, height: 1))
    #expect(renderedLines(control, size: Size(width: 11, height: 1)) == [" Day  Week "])
}

@Test @MainActor func segmentedMovesWithArrowsAndHomeEnd() {
    let control = SegmentedControl(["A", "B", "C"])
    var events: [Int] = []
    control.onSelectionChanged = { events.append($0) }

    _ = control.keyDown(KeyInput(key: .right))
    #expect(control.selectedIndex == 0)

    _ = control.keyDown(KeyInput(key: .right))
    #expect(control.selectedIndex == 1)

    _ = control.keyDown(KeyInput(key: .end))
    #expect(control.selectedIndex == 2)

    _ = control.keyDown(KeyInput(key: .home))
    #expect(control.selectedIndex == 0)

    #expect(events == [0, 1, 2, 0])
}

@Test @MainActor func segmentedClickSelectsSegmentUnderPointer() {
    let control = SegmentedControl(["Day", "Week", "Month"])
    control.frame = Rect(x: 0, y: 0, width: 20, height: 1)

    var events: [Int] = []
    control.onSelectionChanged = { events.append($0) }

    // " Day " = x0..4, " Week " = x5..10, " Month " = x11..18.
    _ = control.mouseEvent(MouseInput(position: Point(x: 7, y: 0), action: .press, button: .left))
    #expect(control.selectedIndex == 1)

    _ = control.mouseEvent(MouseInput(position: Point(x: 13, y: 0), action: .press, button: .left))
    #expect(control.selectedIndex == 2)

    #expect(events == [1, 2])
}

@Test @MainActor func segmentedSilentProgrammaticSelect() {
    let control = SegmentedControl(["A", "B"])
    var events: [Int] = []
    control.onSelectionChanged = { events.append($0) }

    control.select(1)
    #expect(control.selectedIndex == 1)
    #expect(events.isEmpty)
}

// MARK: - TabView

@MainActor
private func makeTabs() -> (TabView, Label, Label) {
    let tabs = TabView()
    let first = Label("FIRST CONTENT")
    let second = Label("SECOND CONTENT")
    tabs.addTab("Files", content: first)
    tabs.addTab("Edit", content: second)
    return (tabs, first, second)
}

@Test @MainActor func tabViewShowsSelectedContentOnly() {
    let (tabs, first, second) = makeTabs()

    #expect(tabs.tabCount == 2)
    #expect(first.isHidden == false)
    #expect(second.isHidden == true)

    let lines = renderedLines(tabs, size: Size(width: 24, height: 5))

    // Tab bar on row 0, separator row 1, first content on row 2.
    #expect(lines[0].contains("Files"))
    #expect(lines[0].contains("Edit"))
    #expect(lines[1] == String(repeating: "─", count: 24))
    #expect(lines[2].contains("FIRST CONTENT"))
    #expect(!lines.joined().contains("SECOND CONTENT"))
}

@Test @MainActor func tabViewSwitchesWithArrowsAndShowsOtherContent() {
    let (tabs, first, second) = makeTabs()
    var events: [Int] = []
    tabs.onSelectionChanged = { events.append($0) }

    _ = tabs.keyDown(KeyInput(key: .right))

    #expect(tabs.selectedIndex == 1)
    #expect(first.isHidden == true)
    #expect(second.isHidden == false)
    #expect(events == [1])

    let lines = renderedLines(tabs, size: Size(width: 24, height: 5))
    #expect(lines[2].contains("SECOND CONTENT"))
}

@Test @MainActor func tabViewClickSelectsTab() {
    let (tabs, _, _) = makeTabs()
    tabs.frame = Rect(x: 0, y: 0, width: 24, height: 5)

    // " Files " = x0..6, gap x7, " Edit " = x8..13.
    _ = tabs.mouseEvent(MouseInput(position: Point(x: 10, y: 0), action: .press, button: .left))
    #expect(tabs.selectedIndex == 1)

    // A click below the tab bar is ignored.
    _ = tabs.mouseEvent(MouseInput(position: Point(x: 2, y: 3), action: .press, button: .left))
    #expect(tabs.selectedIndex == 1)

    // A click back on the first tab title selects it.
    _ = tabs.mouseEvent(MouseInput(position: Point(x: 2, y: 0), action: .press, button: .left))
    #expect(tabs.selectedIndex == 0)
}

@Test @MainActor func tabViewSetTabReplacesTitleAndContentInPlace() {
    let (tabs, first, second) = makeTabs()
    tabs.select(1, notify: false)   // "Edit" selected → `second` is visible

    let replacement = Label("REPLACED CONTENT")
    tabs.setTab(at: 1, title: "Editor", content: replacement)

    #expect(tabs.tabCount == 2)
    #expect(tabs.selectedIndex == 1, "the tab stays selected")
    #expect(tabs.title(at: 1) == "Editor")
    #expect(second.superview == nil, "the old content is detached")
    #expect(replacement.isHidden == false, "the new content shows for the selected tab")
    #expect(first.isHidden == true)

    let lines = renderedLines(tabs, size: Size(width: 28, height: 5))
    #expect(lines[0].contains("Editor"))
    #expect(lines[2].contains("REPLACED CONTENT"))
    #expect(!lines.joined().contains("SECOND CONTENT"))
}

@Test @MainActor func tabViewHidesNonSelectedContentFromFocusOrder() {
    let tabs = TabView()
    let firstField = TextField()
    let secondField = TextField()
    tabs.addTab("One", content: firstField)
    tabs.addTab("Two", content: secondField)

    let window = Window(frame: Rect(x: 0, y: 0, width: 20, height: 6))
    tabs.frame = window.bounds
    window.addSubview(tabs)
    window.layoutIfNeeded()

    // Focus traversal reaches the tab view and the visible field, but not
    // the hidden tab's field.
    window.makeFirstResponder(tabs)
    window.focusNext()
    #expect(window.firstResponder === firstField)

    window.focusNext()
    #expect(window.firstResponder === tabs, "wraps past the hidden second field back to the tab view")
}
