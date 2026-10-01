// Copyright (c) 2026 Bobby Skinner
// SPDX-License-Identifier: MIT
// See the LICENSE file at the repository root for the full text.

import Testing
@testable import TUIKit

// Multiple selection (ActiveUI's AUITable.allowsMultipleSelection):
// NSTableView's Shift and ⌘, with Ctrl/Alt for the ⌘ a terminal never sees.

@MainActor
private func table(multiple: Bool = true) -> (TableView, Window) {
    let view = TableView(columns: [TableColumn("Name")], rows: (0..<10).map { ["row \($0)"] })
    view.allowsMultipleSelection = multiple
    let window = Window(frame: Rect(x: 0, y: 0, width: 20, height: 12))
    view.frame = window.bounds
    window.addSubview(view)
    window.makeFirstResponder(view)
    return (view, window)
}

@MainActor
private func click(_ view: TableView, row: Int, _ modifiers: KeyModifiers = []) {
    _ = view.mouseEvent(MouseInput(position: Point(x: 2, y: row + 1), action: .click, button: .left, modifiers: modifiers))
}

@Test @MainActor func shiftExtendsFromTheAnchor() {
    let (view, window) = table()
    view.select(2)
    window.route(.key(KeyInput(key: .down, modifiers: .shift)))
    window.route(.key(KeyInput(key: .down, modifiers: .shift)))
    #expect(view.selectedIndexes == [2, 3, 4], "Shift-Down twice gave \(view.selectedIndexes)")
    click(view, row: 0, .shift)
    #expect(view.selectedIndexes == [0, 1, 2], "Shift-click above the anchor gave \(view.selectedIndexes)")
}

@Test @MainActor func controlClickAndSpaceToggleOneRow() {
    let (view, window) = table()
    click(view, row: 1)
    click(view, row: 5, .control)
    click(view, row: 7, .alt)
    #expect(view.selectedIndexes == [1, 5, 7], "Ctrl/Alt-click gave \(view.selectedIndexes)")
    click(view, row: 5, .control)
    #expect(view.selectedIndexes == [1, 7], "a second Ctrl-click did not take the row out")
    window.route(.key(KeyInput(key: .character(" "))))
    #expect(view.selectedIndexes == [1, 5, 7], "Space on the cursor row did not add it back")
}

@Test @MainActor func aPlainClickOrMoveCollapsesToOneRow() {
    let (view, window) = table()
    view.selectRows([1, 2, 3])
    #expect(view.selectedIndexes == [1, 2, 3] && view.selectedIndex == 3)
    click(view, row: 3)
    #expect(view.selectedIndexes == [3], "a plain click on the cursor row kept \(view.selectedIndexes)")
    view.selectRows([4, 6])
    window.route(.key(KeyInput(key: .down)))
    #expect(view.selectedIndexes == [7], "a plain arrow gave \(view.selectedIndexes)")
}

@Test @MainActor func aSingleSelectionTableIgnoresTheModifiers() {
    let (view, window) = table(multiple: false)
    view.select(2)
    window.route(.key(KeyInput(key: .down, modifiers: .shift)))
    click(view, row: 6, .control)
    #expect(view.selectedIndexes == [6], "a single-selection table selected \(view.selectedIndexes)")
}

// Through the run loop: the settled click carries the press's modifiers.
@Test @MainActor func aShiftClickThroughTheAppReachesTheTable() async throws {
    let driver = HeadlessDriver(size: Size(width: 20, height: 12))
    let app = App(driver: driver)
    app.multiClickIntervalMilliseconds = 0
    let window = Window()
    let view = TableView(columns: [TableColumn("Name")], rows: (0..<10).map { ["row \($0)"] })
    view.allowsMultipleSelection = true
    view.anchors = .fill()
    window.addSubview(view)

    let session = Task { try await app.run(window) }
    while await driver.presentCount == 0 {
        await Task.yield()
    }
    try await Task.sleep(for: .milliseconds(20))

    func click(row: Int, _ modifiers: KeyModifiers = []) async {
        let point = Point(x: 2, y: row + 1)
        await driver.send(.mouse(MouseInput(position: point, action: .press, button: .left, modifiers: modifiers)))
        await driver.send(.mouse(MouseInput(position: point, action: .release, button: .left, modifiers: modifiers)))
        try? await Task.sleep(for: .milliseconds(30))
    }

    await click(row: 1)
    await click(row: 3, .shift)
    for _ in 0..<200 where view.selectedIndexes != [1, 2, 3] {
        try await Task.sleep(for: .milliseconds(1))
    }
    #expect(view.selectedIndexes == [1, 2, 3], "a Shift-click through the app gave \(view.selectedIndexes)")

    app.stop()
    try await session.value
}

// Moving rows (ActiveUI's AUITable.allowsReordering).

@MainActor
private func reorderableTable() -> (TableView, Window, () -> [String], [(Int, Int)]) {
    var model = (0..<6).map { "row \($0)" }
    var moves: [(Int, Int)] = []
    let view = TableView(columns: [TableColumn("Name")], rows: model.map { [$0] })
    view.allowsReordering = true
    view.onMoveRow = { from, to in
        moves.append((from, to))
        let item = model.remove(at: from)
        model.insert(item, at: to)
        view.rows = model.map { [$0] }
    }
    let window = Window(frame: Rect(x: 0, y: 0, width: 20, height: 10))
    view.frame = window.bounds
    window.addSubview(view)
    window.makeFirstResponder(view)
    return (view, window, { model }, moves)
}

@Test @MainActor func altArrowsMoveTheCursorRow() {
    let (view, window, model, _) = reorderableTable()
    view.select(1)
    window.route(.key(KeyInput(key: .down, modifiers: .alt)))
    window.route(.key(KeyInput(key: .down, modifiers: .alt)))
    #expect(model()[3] == "row 1", "Alt-Down twice left \(model())")
    #expect(view.selectedIndex == 3, "the cursor did not follow the row")
    window.route(.key(KeyInput(key: .up, modifiers: .alt)))
    #expect(model()[2] == "row 1")
}

@Test @MainActor func aDraggedRowLandsWhereItIsDropped() {
    let (view, _, model, _) = reorderableTable()
    _ = view.mouseEvent(MouseInput(position: Point(x: 2, y: 1), action: .press, button: .left))   // row 0
    _ = view.mouseEvent(MouseInput(position: Point(x: 2, y: 3), action: .drag, button: .left))
    _ = view.mouseEvent(MouseInput(position: Point(x: 2, y: 5), action: .drag, button: .left))    // row 4
    _ = view.mouseEvent(MouseInput(position: Point(x: 2, y: 5), action: .release, button: .left))
    #expect(model() == ["row 1", "row 2", "row 3", "row 4", "row 0", "row 5"], "the drag gave \(model())")
    #expect(view.selectedIndex == 4)

    // A press and release on one row moves nothing.
    _ = view.mouseEvent(MouseInput(position: Point(x: 2, y: 2), action: .press, button: .left))
    _ = view.mouseEvent(MouseInput(position: Point(x: 2, y: 2), action: .release, button: .left))
    #expect(model()[1] == "row 2", "a click moved a row")
}
