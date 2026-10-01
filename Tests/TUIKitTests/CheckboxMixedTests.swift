// Copyright (c) 2026 Bobby Skinner
// SPDX-License-Identifier: MIT
// See the LICENSE file at the repository root for the full text.

import Testing
@testable import TUIKit

// ActiveUI change request R6: the third checkbox state, `[-]`.

@MainActor
private func drawn(_ box: Checkbox) -> String {
    let window = Window(frame: Rect(x: 0, y: 0, width: 12, height: 1))
    box.frame = window.bounds
    window.addSubview(box)
    let buffer = SceneRenderer(root: window).render(size: Size(width: 12, height: 1))
    return String((0..<3).map { buffer[Point(x: $0, y: 0)].character })
}

@Test @MainActor func aMixedBoxDrawsADash() {
    let box = Checkbox("All", isChecked: false)
    box.isMixed = true
    #expect(drawn(box) == "[-]")
    box.isMixed = false
    #expect(drawn(box) == "[ ]")
}

@Test @MainActor func togglingAMixedBoxChecksIt() {
    let box = Checkbox("All", isChecked: false)
    box.isMixed = true
    var reported: [Bool] = []
    box.onChange = { reported.append($0) }
    _ = box.keyDown(KeyInput(key: .character(" "), modifiers: []))
    #expect(!box.isMixed && box.isChecked)
    #expect(reported == [true])
    box.toggle()
    #expect(!box.isChecked, "after the first toggle it is an ordinary box")
}
