// Copyright (c) 2026 Bobby Skinner
// SPDX-License-Identifier: MIT
// See the LICENSE file at the repository root for the full text.

import Testing
@testable import TUIKit

// A window presented or dismissed from outside the event loop — from a task,
// as an awaited alert is — must reach the screen without waiting for a key.
// ActiveUI's terminal alert answered keys while nothing showed it.

@MainActor
private func waitForScreen(_ driver: HeadlessDriver, _ condition: ([String]) -> Bool) async -> [String] {
    var rows = await driver.snapshotText()
    for _ in 0..<500 where !condition(rows) {
        try? await Task.sleep(for: .milliseconds(1))
        rows = await driver.snapshotText()
    }
    return rows
}

@Test @MainActor func aWindowPresentedFromATaskIsDrawnWithoutAKey() async throws {
    let driver = HeadlessDriver(size: Size(width: 40, height: 12))
    let app = App(driver: driver)
    let window = Window()
    window.addSubview(Label("BODY"))

    let session = Task { try await app.run(window) }
    while await driver.presentCount == 0 {
        await Task.yield()
    }
    // `run` builds its event stream after the first present.
    try await Task.sleep(for: .milliseconds(20))

    let dialog = Dialog(title: "Saved", message: "All done.")
    dialog.addButton("OK", isDefault: true)
    dialog.sizeToFit(in: app.desktop.bounds.size)
    app.present(dialog)
    let shown = await waitForScreen(driver) { $0.joined().contains("All done.") }
    #expect(shown.joined().contains("All done."), "a presented window stayed off screen until a key")

    app.dismiss(dialog)
    let gone = await waitForScreen(driver) { !$0.joined().contains("All done.") }
    #expect(!gone.joined().contains("All done."), "a dismissed window stayed on screen until a key")

    app.stop()
    try await session.value
}

@Test @MainActor func presentingAPresentedWindowRaisesItInsteadOfAddingIt() {
    let app = App(driver: HeadlessDriver(size: Size(width: 20, height: 6)))
    let first = Window(frame: Rect(x: 0, y: 0, width: 10, height: 3))
    let second = Window(frame: Rect(x: 2, y: 1, width: 10, height: 3))

    app.present(first)
    app.present(second)
    app.present(first)
    #expect(app.windows.count == 2, "a window presented twice was stacked twice")
    #expect(app.keyWindow === first, "presenting it again did not raise it")

    app.dismiss(first)
    #expect(app.windows.count == 1 && app.keyWindow === second, "dismissing left the window behind")
}

@Test @MainActor func theKeyWindowIsAnnouncedOncePerChange() {
    let app = App(driver: HeadlessDriver(size: Size(width: 30, height: 8)))
    let lower = Window(frame: Rect(x: 0, y: 0, width: 10, height: 3))
    let upper = Window(frame: Rect(x: 5, y: 2, width: 10, height: 3))
    var told: [String] = []
    lower.onBecomeKey = { told.append("lower") }
    upper.onBecomeKey = { told.append("upper") }

    app.present(lower)
    app.present(upper)
    app.present(upper)     // already key: nothing
    app.activate(lower)    // switching back
    app.present(upper)     // raised again, through the nested activate: once
    app.dismiss(upper)     // uncovered
    #expect(told == ["lower", "upper", "lower", "upper", "lower"], "announced \(told)")
}
