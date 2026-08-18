import CodeEditorCore
import Testing
import TUIKit
@testable import TUICodeEditor

// The Mac ladder: word → line → everything → nothing.

@MainActor
private func editor(_ text: String) -> CodeEditorView {
    let view = CodeEditorView(text: text, language: "swift")
    view.frame = Rect(x: 0, y: 0, width: 60, height: 10)
    view.layoutIfNeeded()
    return view
}

@MainActor
private func doubleClick(_ editor: CodeEditorView, atColumn column: Int, line: Int) {
    let point = Point(x: editor.gutterWidth + column, y: line)
    _ = editor.mouseEvent(MouseInput(position: point, action: .press, button: .left))
    _ = editor.mouseEvent(MouseInput(position: point, action: .click, button: .left, clickCount: 2))
}

@Test @MainActor func doubleClickingWalksWordThenLineThenEverything() {
    let view = editor("let answer = 42\nlet other = 7")

    doubleClick(view, atColumn: 5, line: 0)
    #expect(view.selectedText == "answer", "the word under the pointer")

    doubleClick(view, atColumn: 5, line: 0)
    #expect(view.selectedText == "let answer = 42", "again: its line")

    doubleClick(view, atColumn: 5, line: 0)
    #expect(view.selectedText == "let answer = 42\nlet other = 7", "again: everything")

    doubleClick(view, atColumn: 5, line: 0)
    #expect(view.hasSelection == false, "and again: nothing")
    #expect(view.cursorPosition.y == 0, "the caret stays where it was clicked")
}

@Test @MainActor func theLadderStartsOverWhenAnotherWordIsClicked() {
    let view = editor("alpha beta gamma")

    doubleClick(view, atColumn: 0, line: 0)
    #expect(view.selectedText == "alpha")

    // A different word is a fresh start, not the next rung — the escalation
    // is about what is selected, not about how many times a mouse was hit.
    doubleClick(view, atColumn: 6, line: 0)
    #expect(view.selectedText == "beta")
}

@Test @MainActor func theLadderPicksUpFromASelectionMadeAnyOtherWay() {
    // No click counter to get out of step: select all from the keyboard, then
    // double-click, and the ladder knows it is already at the top.
    let view = editor("alpha beta")
    view.selectAll()

    doubleClick(view, atColumn: 0, line: 0)
    #expect(view.hasSelection == false)
}

@Test @MainActor func tripleClickStillTakesTheLineOutright() {
    let view = editor("let answer = 42\nlet other = 7")
    let point = Point(x: view.gutterWidth + 4, y: 1)
    _ = view.mouseEvent(MouseInput(position: point, action: .press, button: .left))
    _ = view.mouseEvent(MouseInput(position: point, action: .click, button: .left, clickCount: 3))

    #expect(view.selectedText == "let other = 7")
}

@Test func theRuleWidensAndThenLetsGo() {
    #expect(SelectionEscalation.nextScope(isWord: false, isLine: false, isAll: false) == .word)
    #expect(SelectionEscalation.nextScope(isWord: true, isLine: false, isAll: false) == .line)
    #expect(SelectionEscalation.nextScope(isWord: false, isLine: true, isAll: false) == .all)
    #expect(SelectionEscalation.nextScope(isWord: false, isLine: false, isAll: true) == .none)

    // A single-line control passes the same range for line and all, so the
    // ladder has one rung fewer rather than a loop in it.
    #expect(SelectionEscalation.nextScope(isWord: false, isLine: true, isAll: true) == .none)
    #expect(SelectionEscalation.nextScope(isWord: true, isLine: false, isAll: true) == .none)
}
