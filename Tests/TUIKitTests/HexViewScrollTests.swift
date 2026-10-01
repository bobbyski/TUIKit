// Copyright (c) 2026 Bobby Skinner
// SPDX-License-Identifier: MIT
// See the LICENSE file at the repository root for the full text.

import Testing
@testable import TUIKit

// A free scroll sticks; the caret is followed when it moves (ActiveUI's
// AUIHexView drives both, and keeps its scroller beside the grid in step).

@MainActor
private func hexView(rows: Int) -> (HexView, Window) {
    let view = HexView(bytes: [UInt8](repeating: 0x41, count: 16 * rows))
    view.bytesPerRow = 16
    view.showsControlBar = false
    let window = Window(frame: Rect(x: 0, y: 0, width: 80, height: 6))
    view.frame = window.bounds
    window.addSubview(view)
    _ = SceneRenderer(root: window).render(size: Size(width: 80, height: 6))
    return (view, window)
}

@Test @MainActor func aWheelScrollIsNotUndoneByTheNextDraw() {
    let (view, window) = hexView(rows: 40)
    var scrolled: [Int] = []
    view.onScroll = { scrolled.append($0) }
    _ = view.mouseEvent(MouseInput(position: Point(x: 10, y: 2), action: .scrollDown, button: .none))
    let lines = SceneRenderer(root: window).render(size: Size(width: 80, height: 6)).textLines()
    // What is drawn, not only what is stored: row 3 starts at byte 0x30.
    #expect(lines.first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }?.contains("30") == true,
            "the wheel scroll snapped back:\n\(lines.joined(separator: "\n"))")
    #expect(view.firstVisibleRow == 3, "the wheel scroll snapped back to row \(view.firstVisibleRow)")
    #expect(scrolled == [3])
}

@Test @MainActor func aCaretSetFromCodeIsBroughtOnScreenSilently() {
    let (view, _) = hexView(rows: 40)
    var reported: [Int] = []
    view.onCaretMoved = { reported.append($0) }
    view.setCaret(16 * 20 + 5)
    #expect(view.caret == 325)
    #expect(view.firstVisibleRow > 0 && view.firstVisibleRow <= 20, "row 20 was not brought on screen (top \(view.firstVisibleRow))")
    #expect(reported.isEmpty, "a caret set from code was reported")
    view.scroll(toRow: 0)
    #expect(view.firstVisibleRow == 0 && view.caret == 325, "scrolling moved the caret")
}
