// Copyright (c) 2026 Bobby Skinner
// SPDX-License-Identifier: MIT
// See the LICENSE file at the repository root for the full text.

import Testing
@testable import TUIKit

// `Window.onPressOutside` (ActiveUI's AUIPopover): a press outside a transient
// window tells it first, then lands where it points — as one outside a menu does.

@Test @MainActor func aPressOutsideATransientWindowClosesItAndStillLands() async throws {
    let driver = HeadlessDriver(size: Size(width: 40, height: 10))
    let app = App(driver: driver)
    let base = Window()
    var pressed = 0
    let button = Button("Behind") { pressed += 1 }
    button.frame = Rect(x: 2, y: 8, width: 10, height: 1)
    base.addSubview(button)

    let session = Task { try await app.run(base) }
    while await driver.presentCount == 0 {
        await Task.yield()
    }
    try await Task.sleep(for: .milliseconds(20))

    let popover = Window(frame: Rect(x: 10, y: 1, width: 16, height: 4))
    popover.addSubview(Label("POPOVER"))
    var outsidePresses = 0
    popover.onPressOutside = { [weak app, weak popover] in
        outsidePresses += 1
        if let app, let popover { app.dismiss(popover) }
    }
    app.present(popover)

    // Inside: nothing closes.
    await driver.send(.mouse(MouseInput(position: Point(x: 12, y: 2), action: .press, button: .left)))
    await driver.send(.mouse(MouseInput(position: Point(x: 12, y: 2), action: .release, button: .left)))
    try await Task.sleep(for: .milliseconds(20))
    #expect(outsidePresses == 0 && app.keyWindow === popover, "a press inside closed the popover")

    // Outside, on the button: the popover goes and the button still fires.
    await driver.send(.mouse(MouseInput(position: Point(x: 4, y: 8), action: .press, button: .left)))
    await driver.send(.mouse(MouseInput(position: Point(x: 4, y: 8), action: .release, button: .left)))
    for _ in 0..<300 where pressed == 0 {
        try await Task.sleep(for: .milliseconds(1))
    }
    #expect(outsidePresses == 1, "the popover was told \(outsidePresses) times")
    #expect(app.keyWindow === base, "the popover is still up")
    #expect(pressed == 1, "the press that closed the popover did not reach the button")

    app.stop()
    try await session.value
}
