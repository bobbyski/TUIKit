import Testing
@testable import TUIKit

// MARK: - Navigation Core (pure)

@Test func rowNavigationClampsAndReportsChanges() {
    var state = RowNavigationState(count: 5)

    let selected = state.select(2)
    #expect(selected)
    #expect(state.selectedIndex == 2)

    let reselected = state.select(2)
    #expect(!reselected, "reselecting is not a change")

    let clamped = state.select(99)
    #expect(clamped)
    #expect(state.selectedIndex == 4, "clamped to the last row")

    let cleared = state.select(nil)
    #expect(cleared)
    #expect(state.selectedIndex == nil)
}

@Test func rowNavigationMovesFromEdgesWhenEmpty() {
    var state = RowNavigationState(count: 3)

    state.move(by: 1)
    #expect(state.selectedIndex == 0, "down from no selection starts at the top")

    state.select(nil)
    state.move(by: -1)
    #expect(state.selectedIndex == 2, "up from no selection starts at the bottom")
}

@Test func rowNavigationKeepsSelectionVisible() {
    var state = RowNavigationState(count: 20)

    state.select(10)
    state.ensureSelectionVisible(height: 5)
    #expect(state.scrollOffset == 6, "scrolled so row 10 is the last visible")

    state.select(2)
    state.ensureSelectionVisible(height: 5)
    #expect(state.scrollOffset == 2, "scrolled up so row 2 is the first visible")
}

@Test func rowNavigationScrollClampsToContent() {
    var state = RowNavigationState(count: 6)

    state.scroll(by: 100, height: 4)
    #expect(state.scrollOffset == 2, "cannot scroll past the last page")

    state.scroll(by: -100, height: 4)
    #expect(state.scrollOffset == 0)
}

// MARK: - ListView

@MainActor
private func makeList(_ count: Int, height: Int) -> ListView {
    let list = ListView(items: (1...count).map { "item \($0)" })
    list.frame = Rect(x: 0, y: 0, width: 10, height: height)
    return list
}

@Test @MainActor func listNavigatesWithKeysAndScrolls() {
    let list = makeList(10, height: 3)
    var selections: [Int?] = []
    list.onSelectionChanged = { selections.append($0) }

    _ = list.keyDown(KeyInput(key: .down))
    _ = list.keyDown(KeyInput(key: .down))
    #expect(list.selectedIndex == 1)

    _ = list.keyDown(KeyInput(key: .end))
    #expect(list.selectedIndex == 9)
    #expect(list.scrollOffset == 7, "end scrolled the viewport to the last page")

    _ = list.keyDown(KeyInput(key: .home))
    #expect(list.selectedIndex == 0)
    #expect(list.scrollOffset == 0)

    _ = list.keyDown(KeyInput(key: .pageDown))
    #expect(list.selectedIndex == 2)

    #expect(selections == [0, 1, 9, 0, 2])
}

@Test @MainActor func listActivatesWithReturn() {
    let list = makeList(3, height: 3)
    var activated: [Int] = []
    list.onActivate = { activated.append($0) }

    _ = list.keyDown(KeyInput(key: .enter))
    #expect(activated.isEmpty, "no selection, no activation")

    _ = list.keyDown(KeyInput(key: .down))
    _ = list.keyDown(KeyInput(key: .enter))
    #expect(activated == [0])
}

@Test @MainActor func listClickSelectsVisibleRow() {
    let list = makeList(10, height: 3)
    _ = list.keyDown(KeyInput(key: .end))          // scrollOffset 7
    _ = list.mouseEvent(MouseInput(position: Point(x: 0, y: 1), action: .press, button: .left))

    #expect(list.selectedIndex == 8, "clicked row = scroll offset + click row")
}

@Test @MainActor func listWheelScrollsWithoutMovingSelection() {
    let list = makeList(10, height: 3)
    _ = list.keyDown(KeyInput(key: .down))          // select 0

    _ = list.mouseEvent(MouseInput(position: .zero, action: .scrollDown))
    _ = list.mouseEvent(MouseInput(position: .zero, action: .scrollDown))

    #expect(list.scrollOffset == 2)
    #expect(list.selectedIndex == 0)
}

@Test @MainActor func listRendersSelectionAndViewport() {
    let list = makeList(5, height: 2)
    list.select(2)

    let window = Window(frame: Rect(x: 0, y: 0, width: 10, height: 2))
    window.addSubview(list)
    let lines = SceneRenderer(root: window).render(size: Size(width: 10, height: 2)).textLines()

    // Selection stays visible: viewport scrolled to rows 1-2 so the
    // selected row 2 is the last visible line.
    #expect(lines == ["item 2    ", "item 3    "])
}

@Test @MainActor func shrinkingItemsClampsSelection() {
    let list = makeList(5, height: 3)
    list.select(4)

    list.items = ["only", "two"]

    #expect(list.selectedIndex == 1)
}
