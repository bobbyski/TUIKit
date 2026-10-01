// Copyright (c) 2026 Bobby Skinner
// SPDX-License-Identifier: MIT
// See the LICENSE file at the repository root for the full text.

import Testing
@testable import TUIKit

// Check marks and a hook before opening (ActiveUI's menus: `checked { }`,
// `enabled { }` and dynamic items, asked each time a menu opens).

@Test @MainActor func aMenuIsToldBeforeItOpensAndDrawsItsChecks() {
    let menu = Menu("View")
    var opens = 0
    var showGrid = true
    menu.onWillOpen = { [weak menu] in
        guard let menu else { return }
        opens += 1
        menu.removeAllItems()
        let grid = MenuItem("Grid")
        grid.state = showGrid ? .on : .off
        menu.addItem(grid)
        menu.addItem(MenuItem("Rulers"))
    }

    let window = Window(frame: Rect(x: 0, y: 0, width: 30, height: 8))
    window.presentContextMenu(menu, at: Point(x: 0, y: 0))
    var screen = SceneRenderer(root: window).render(size: Size(width: 30, height: 8)).textLines()
    #expect(opens == 1)
    #expect(screen.contains { $0.contains("✓ Grid") }, "no check mark:\n\(screen.joined(separator: "\n"))")
    #expect(screen.contains { $0.contains("  Rulers") }, "an unchecked row should line up under the mark")

    window.dismissContextMenu()
    showGrid = false
    window.presentContextMenu(menu, at: Point(x: 0, y: 0))
    screen = SceneRenderer(root: window).render(size: Size(width: 30, height: 8)).textLines()
    #expect(opens == 2, "the menu was not told it was opening again")
    #expect(!screen.contains { $0.contains("✓") }, "the mark outlived the state behind it")
}
