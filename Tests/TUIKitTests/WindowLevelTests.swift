// Copyright (c) 2026 Bobby Skinner
// SPDX-License-Identifier: MIT
// See the LICENSE file at the repository root for the full text.

import Testing
@testable import TUIKit

// Window levels (ActiveUI R19): drawn by level, keyed by recency.

@Test @MainActor func aFloatingWindowStaysDrawnAboveTheKeyDocument() {
    let app = App(driver: HeadlessDriver(size: Size(width: 30, height: 10)))
    let document = Window(frame: Rect(x: 0, y: 0, width: 30, height: 10))
    let palette = Window(frame: Rect(x: 2, y: 2, width: 10, height: 4))
    palette.level = .floating

    app.present(document)
    app.present(palette)
    app.activate(document)

    #expect(app.keyWindow === document, "the document should have the keys")
    #expect(app.drawnWindows.last === palette, "the palette should be drawn on top")
    #expect(app.desktop.subviews.last === palette, "the desktop's order should match")
}

@Test @MainActor func aClickOnAFloatingWindowOverTheDocumentGoesToIt() async throws {
    let driver = HeadlessDriver(size: Size(width: 30, height: 10))
    let app = App(driver: driver)
    let document = Window(frame: Rect(x: 0, y: 0, width: 30, height: 10))
    let palette = Window(frame: Rect(x: 2, y: 2, width: 10, height: 4))
    palette.level = .floating

    let session = Task { try await app.run(document) }
    while await driver.presentCount == 0 {
        await Task.yield()
    }
    try await Task.sleep(for: .milliseconds(20))
    app.present(palette)
    app.activate(document)

    // Over the palette: it is drawn there, so it takes the press and the keys.
    await driver.send(.mouse(MouseInput(position: Point(x: 4, y: 3), action: .press, button: .left)))
    for _ in 0..<300 where app.keyWindow !== palette {
        try await Task.sleep(for: .milliseconds(1))
    }
    #expect(app.keyWindow === palette, "a press on the palette went to the document under it")

    app.stop()
    try await session.value
}

@Test @MainActor func aDialogIsDrawnAboveAPaletteAndASheetWithItsWindow() {
    let app = App(driver: HeadlessDriver(size: Size(width: 30, height: 10)))
    let document = Window(frame: Rect(x: 0, y: 0, width: 30, height: 10))
    let palette = Window(frame: Rect(x: 2, y: 2, width: 10, height: 4))
    palette.level = .floating
    app.present(document)
    app.present(palette)

    let sheet = Sheet(title: "Save?", on: palette)
    #expect(sheet.level == .floating, "a sheet should take its window's level")

    let dialog = Dialog(title: "Really?")
    app.present(dialog)
    app.activate(palette)
    #expect(app.drawnWindows.last === dialog, "a dialog should be drawn above a palette")
}

// `scrollRowToVisible` (ActiveUI's AUITable.revealRow): shows a row without
// choosing it.

@Test @MainActor func revealingARowScrollsWithoutSelecting() {
    let table = TableView(columns: [TableColumn("Name")], rows: (0..<50).map { ["row \($0)"] })
    table.frame = Rect(x: 0, y: 0, width: 20, height: 6)   // a header and five rows
    table.select(2)
    table.scrollRowToVisible(30)
    #expect(table.selectedIndex == 2, "revealing a row selected it")
    #expect(table.scrollOffset == 26, "row 30 should be the last of five visible; offset \(table.scrollOffset)")
    table.scrollRowToVisible(10)
    #expect(table.scrollOffset == 10, "scrolling back up should put row 10 at the top; offset \(table.scrollOffset)")
}
