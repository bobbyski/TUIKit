// Copyright (c) 2026 Bobby Skinner
// SPDX-License-Identifier: MIT
// See the LICENSE file at the repository root for the full text.

import Testing
@testable import TUIKit

// The code editor's gutter decorations: what an IDE draws beside its lines —
// breakpoints, diagnostics, the stopped line, change bars — in cells.

@MainActor
private func render(_ view: TUIView, size: Size = Size(width: 24, height: 4)) -> CellBuffer {
    let window = Window(frame: Rect(origin: .zero, size: size))
    view.frame = Rect(origin: .zero, size: size)
    window.addSubview(view)
    return SceneRenderer(root: window).render(size: size)
}

@MainActor
private func row(_ buffer: CellBuffer, _ y: Int, width: Int = 24) -> String {
    String((0..<width).map { buffer[Point(x: $0, y: y)].character })
}

@Test @MainActor func withoutMarksTheGutterIsAsItWas() {
    let editor = SyntaxTextView(text: "a\nb", language: "text")
    editor.showsOwnScrollbars = false
    let buffer = render(editor)
    #expect(row(buffer, 0).hasPrefix("1 │a"))
    #expect(row(buffer, 1).hasPrefix("2 │b"))
}

@Test @MainActor func aMarkTakesAColumnBeforeTheNumbers() {
    let editor = SyntaxTextView(text: "a\nb", language: "text")
    editor.showsOwnScrollbars = false
    let red = CellStyle(foreground: .named(.red))
    editor.gutterMarks = [1: .init("●", style: red)]
    let buffer = render(editor)
    #expect(row(buffer, 0).hasPrefix(" 1 │a"), "lines without a mark keep the column blank")
    #expect(row(buffer, 1).hasPrefix("●2 │b"))
    #expect(buffer[Point(x: 0, y: 1)].style.foreground == .named(.red))
}

@Test @MainActor func aReservedColumnDoesNotMoveTheText() {
    let editor = SyntaxTextView(text: "a", language: "text")
    editor.showsOwnScrollbars = false
    editor.reservesMarkColumn = true
    #expect(row(render(editor), 0).hasPrefix(" 1 │a"))
    editor.gutterMarks = [0: .init("▶")]
    #expect(row(render(editor), 0).hasPrefix("▶1 │a"))
}

@Test @MainActor func theRuleTakesALineSChangeColour() {
    let editor = SyntaxTextView(text: "a\nb", language: "text")
    editor.showsOwnScrollbars = false
    editor.gutterRuleStyles = [0: CellStyle(foreground: .named(.green))]
    let buffer = render(editor)
    #expect(buffer[Point(x: 2, y: 0)].character == "│")
    #expect(buffer[Point(x: 2, y: 0)].style.foreground == .named(.green))
    #expect(buffer[Point(x: 2, y: 1)].style.flags.contains(.dim), "an unchanged line's rule stays dim")
}

@Test @MainActor func aLineBackgroundFillsTheRow() {
    let editor = SyntaxTextView(text: "ab\ncd", language: "text")
    editor.showsOwnScrollbars = false
    editor.lineBackgrounds = [1: .named(.yellow)]
    let buffer = render(editor)
    #expect(buffer[Point(x: 3, y: 1)].style.background == .named(.yellow), "under the text")
    #expect(buffer[Point(x: 20, y: 1)].style.background == .named(.yellow), "past the end of the line")
    #expect(buffer[Point(x: 3, y: 0)].style.background != .named(.yellow))
}

@Test @MainActor func aDiagnosticRangeIsUnderlined() {
    let editor = SyntaxTextView(text: "let x = y", language: "text")
    editor.showsOwnScrollbars = false
    editor.underlinedColumns = [0: [8..<9]]
    let buffer = render(editor)
    // Gutter "1 │" is three cells; column 8 of the text is cell 11.
    #expect(buffer[Point(x: 11, y: 0)].style.flags.contains(.underline))
    #expect(!buffer[Point(x: 10, y: 0)].style.flags.contains(.underline))
}

@Test @MainActor func aGutterClickReportsItsLine() {
    let editor = SyntaxTextView(text: "a\nb\nc", language: "text")
    editor.showsOwnScrollbars = false
    _ = render(editor)
    var clicked: [Int] = []
    editor.onGutterClick = { clicked.append($0) }
    let handled = editor.mouseEvent(MouseInput(position: Point(x: 0, y: 2), action: .press, button: .left))
    #expect(handled)
    #expect(clicked == [2])
}
