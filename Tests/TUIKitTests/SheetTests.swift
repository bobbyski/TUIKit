import Foundation
import Testing
@testable import TUIKit

// PLAN Phase 11.2 — a dialog that belongs to one window.
//
// The distinction that matters is not where it is drawn, it is what it stops.
// A `Dialog` is the app asking a question and owns every click. A sheet is one
// window's business: saving this document must not stop you reading another.

@MainActor
private func app(size: Size = Size(width: 60, height: 20)) -> (App, HeadlessDriver) {
    let driver = HeadlessDriver(size: size)
    return (App(driver: driver), driver)
}

@Test @MainActor func aSheetHangsFromItsHostsTitleRow() {
    let (app, _) = app()
    let host = Window(frame: Rect(x: 10, y: 4, width: 30, height: 10))
    app.present(host)

    let sheet = Sheet(title: "Save?", on: host)
    sheet.frame = Rect(x: 0, y: 0, width: 20, height: 6)
    app.presentSheet(sheet)

    #expect(sheet.frame.minY == host.frame.minY + 1, "under the title row, not over it")
    #expect(sheet.frame.minX == host.frame.minX + (30 - 20) / 2, "centred on the host")
    #expect(host.attachedSheet === sheet)
}

@Test @MainActor func aSheetOnAWindowAtTheEdgeIsPulledBackOnScreen() {
    let (app, _) = app(size: Size(width: 40, height: 20))
    // The desktop learns its size when the app runs; this test has no run
    // loop, so it says so directly rather than clamping against nothing.
    app.desktop.frame = Rect(x: 0, y: 0, width: 40, height: 20)
    let host = Window(frame: Rect(x: 28, y: 2, width: 12, height: 8))
    app.present(host)

    let sheet = Sheet(title: "Save?", on: host)
    sheet.frame = Rect(x: 0, y: 0, width: 24, height: 6)
    app.presentSheet(sheet)

    #expect(sheet.frame.minX >= 0)
    #expect(sheet.frame.maxX <= 40, "a sheet you cannot read is worse than one off centre")
}

@Test @MainActor func aSheetIsNotAppWideModal() {
    let (app, _) = app()
    let host = Window(frame: Rect(x: 0, y: 0, width: 20, height: 10))
    app.present(host)
    let sheet = Sheet(title: "Save?", on: host)
    sheet.frame = Rect(x: 0, y: 0, width: 10, height: 5)
    app.presentSheet(sheet)

    #expect(sheet.isModal == false,
            "isModal swallows every click aimed elsewhere; a sheet exists to avoid that")
}

@Test @MainActor func pressingTheHostGoesToTheSheetAndPressingAnotherWindowDoesNot() async throws {
    let driver = HeadlessDriver(size: Size(width: 60, height: 20))
    let app = App(driver: driver)

    let host = Window(frame: Rect(x: 0, y: 0, width: 20, height: 10))
    let other = Window(frame: Rect(x: 30, y: 0, width: 20, height: 10))
    app.present(host)
    app.present(other)

    let sheet = Sheet(title: "Save?", on: host)
    sheet.frame = Rect(x: 0, y: 0, width: 10, height: 5)
    app.presentSheet(sheet)
    #expect(app.keyWindow === sheet)

    let session = Task { try await app.run(host) }
    while await driver.presentCount == 0 {
        await Task.yield()
    }

    // A press deep inside the host, clear of the sheet.
    await driver.send(.mouse(MouseInput(position: Point(x: 2, y: 9), action: .press, button: .left)))
    while app.keyWindow !== sheet {
        await Task.yield()
    }
    #expect(app.keyWindow === sheet, "the host is blocked while its sheet is up")

    // The other window is not blocked — that is the whole difference from a
    // modal dialog.
    await driver.send(.mouse(MouseInput(position: Point(x: 35, y: 5), action: .press, button: .left)))
    while app.keyWindow !== other {
        await Task.yield()
    }
    #expect(app.keyWindow === other, "another window in the stack stays live")

    app.stop()
    _ = try? await session.value
}

@Test @MainActor func dismissingASheetGivesTheHostBackAndClearsTheLink() {
    let (app, _) = app()
    let host = Window(frame: Rect(x: 0, y: 0, width: 20, height: 10))
    app.present(host)
    let sheet = Sheet(title: "Save?", on: host)
    sheet.frame = Rect(x: 0, y: 0, width: 10, height: 5)
    app.presentSheet(sheet)

    app.dismissSheet(on: host)

    #expect(host.attachedSheet == nil)
    #expect(app.keyWindow === host)
}

@Test @MainActor func presentingASecondSheetReplacesTheFirst() {
    let (app, _) = app()
    let host = Window(frame: Rect(x: 0, y: 0, width: 20, height: 10))
    app.present(host)

    let first = Sheet(title: "One", on: host)
    first.frame = Rect(x: 0, y: 0, width: 10, height: 5)
    app.presentSheet(first)

    let second = Sheet(title: "Two", on: host)
    second.frame = Rect(x: 0, y: 0, width: 10, height: 5)
    app.presentSheet(second)

    #expect(host.attachedSheet === second, "one sheet per window")
    #expect(app.keyWindow === second)
}
