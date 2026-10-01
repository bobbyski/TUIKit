// Copyright (c) 2026 Bobby Skinner
// SPDX-License-Identifier: MIT
// See the LICENSE file at the repository root for the full text.

import Testing
@testable import TUIKit

// ActiveUI change request R7: a host places the caret and the selection, and
// inserts at the caret, rather than only selecting everything or nothing.

@Test @MainActor func aHostSelectsARange() {
    let view = TextView(text: "first line\nsecond line")
    view.select(from: Point(x: 6, y: 0), to: Point(x: 6, y: 1))
    #expect(view.selectedText == "line\nsecond")
    #expect(view.cursorPosition == Point(x: 6, y: 1), "the caret goes to the head")
}

@Test @MainActor func selectionPointsAreClampedIntoTheText() {
    let view = TextView(text: "ab\ncd")
    view.select(from: Point(x: -3, y: -1), to: Point(x: 99, y: 99))
    #expect(view.selectedText == "ab\ncd")
    #expect(view.cursorPosition == Point(x: 2, y: 1))
}

@Test @MainActor func placingTheCaretSelectsNothing() {
    let view = TextView(text: "hello")
    view.select(from: .zero, to: Point(x: 5, y: 0))
    view.placeCursor(at: Point(x: 2, y: 0))
    #expect(view.selectedText == nil)
    #expect(view.cursorPosition == Point(x: 2, y: 0))
}

@Test @MainActor func insertingAtTheCaretReplacesTheSelectionOnce() {
    let view = TextView(text: "let x = 1")
    var changes: [String] = []
    view.onChanged = { changes.append($0) }
    view.select(from: Point(x: 4, y: 0), to: Point(x: 5, y: 0))
    view.insertAtCursor("total")
    #expect(view.text == "let total = 1")
    #expect(view.cursorPosition == Point(x: 9, y: 0))
    #expect(changes == ["let total = 1"], "one edit, one report")
}

@Test @MainActor func insertedNewlinesSplitLines() {
    let view = TextView(text: "ab")
    view.placeCursor(at: Point(x: 1, y: 0))
    view.insertAtCursor("1\r\n2\n3")
    #expect(view.text == "a1\n2\n3b")
    #expect(view.cursorPosition == Point(x: 1, y: 2))
}
