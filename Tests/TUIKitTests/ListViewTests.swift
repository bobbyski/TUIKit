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

    // The settled single click (count 1) selects — the raw press does not.
    _ = list.mouseEvent(MouseInput(position: Point(x: 0, y: 1), action: .press, button: .left))
    #expect(list.selectedIndex == 9, "the press alone doesn't move the selection")

    _ = list.mouseEvent(MouseInput(position: Point(x: 0, y: 1), action: .click, button: .left))
    #expect(list.selectedIndex == 8, "clicked row = scroll offset + click row")
}

@Test @MainActor func listDoubleClickActivatesTheRow() {
    let list = makeList(10, height: 3)
    var selections: [Int?] = []
    var activated: [Int] = []
    list.onSelectionChanged = { selections.append($0) }
    list.onActivate = { activated.append($0) }

    // A raw press selects nothing and does not activate — the click is debounced.
    _ = list.mouseEvent(MouseInput(position: Point(x: 0, y: 2), action: .press, button: .left))
    #expect(list.selectedIndex == nil)
    #expect(activated.isEmpty)

    // A settled single click (count 1) selects, without activating.
    _ = list.mouseEvent(MouseInput(position: Point(x: 0, y: 2), action: .click, button: .left, clickCount: 1))
    #expect(list.selectedIndex == 2)
    #expect(selections == [2])
    #expect(activated.isEmpty, "count 1 selects but does not activate")

    // A double-click on ANOTHER row is only the double action: the highlight
    // moves, the row activates, and the single-click callback stays silent.
    _ = list.mouseEvent(MouseInput(position: Point(x: 0, y: 1), action: .click, button: .left, clickCount: 2))
    #expect(list.selectedIndex == 1, "the highlight follows the double-click")
    #expect(activated == [1])
    #expect(selections == [2], "a double never fires the single-click callback")
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

@Test @MainActor func focusSelectsFirstRowWhenEmpty() {
    let window = Window(frame: Rect(x: 0, y: 0, width: 10, height: 3))
    let list = makeList(5, height: 3)
    window.addSubview(list)

    var selections: [Int?] = []
    list.onSelectionChanged = { selections.append($0) }

    window.makeFirstResponder(list)

    #expect(list.selectedIndex == 0, "focus highlights the first row")
    #expect(selections == [0])
}

@Test @MainActor func focusKeepsExistingSelection() {
    let window = Window(frame: Rect(x: 0, y: 0, width: 10, height: 3))
    let list = makeList(5, height: 3)
    list.select(3)
    window.addSubview(list)

    var selections: [Int?] = []
    list.onSelectionChanged = { selections.append($0) }

    window.makeFirstResponder(list)

    #expect(list.selectedIndex == 3, "existing selection is preserved on focus")
    #expect(selections.isEmpty)
}

@Test @MainActor func shrinkingItemsClampsSelection() {
    let list = makeList(5, height: 3)
    list.select(4)

    list.items = ["only", "two"]

    #expect(list.selectedIndex == 1)
}

@Test @MainActor func listViewShowsScrollbarOnOverflow() {
    let list = ListView(items: (1...20).map { "Item \($0)" })
    let window = Window(frame: Rect(x: 0, y: 0, width: 12, height: 5))
    list.frame = window.bounds
    window.addSubview(list)

    // 20 items in 5 rows → the last column becomes a proportional scrollbar,
    // thumb at the top while unscrolled.
    let buffer = SceneRenderer(root: window).render(size: Size(width: 12, height: 5))
    #expect(buffer[Point(x: 11, y: 0)].style.background == .named(.white), "thumb at top")
    #expect(buffer[Point(x: 11, y: 4)].style.background == .named(.brightBlack), "dim track below")

    // No scrollbar when everything fits.
    let small = ListView(items: ["a", "b"])
    let w2 = Window(frame: Rect(x: 0, y: 0, width: 12, height: 5))
    small.frame = w2.bounds
    w2.addSubview(small)
    let line = SceneRenderer(root: w2).render(size: Size(width: 12, height: 5)).textLines()[0]
    #expect(line.hasPrefix("a"))
}

@Test @MainActor func listViewScrollbarThumbDragsTheList() {
    let list = ListView(items: (1...40).map { "Item \($0)" })
    let window = Window(frame: Rect(x: 0, y: 0, width: 12, height: 8))
    list.frame = window.bounds
    window.addSubview(list)
    _ = SceneRenderer(root: window).render(size: window.frame.size)   // lay out
    #expect(list.scrollOffset == 0)

    // Grab the thumb (top) and drag to the bottom row → scrolled to the end.
    _ = list.mouseEvent(MouseInput(position: Point(x: 11, y: 0), action: .press, button: .left))
    _ = list.mouseEvent(MouseInput(position: Point(x: 11, y: 7), action: .drag, button: .left))
    #expect(list.scrollOffset == 40 - 8, "dragging the thumb to the bottom scrolls to the end")
    _ = list.mouseEvent(MouseInput(position: Point(x: 11, y: 7), action: .release, button: .left))

    // Click the track above the thumb → pages up.
    _ = list.mouseEvent(MouseInput(position: Point(x: 11, y: 0), action: .press, button: .left))
    #expect(list.scrollOffset < 32, "track click above the thumb pages up")
}
