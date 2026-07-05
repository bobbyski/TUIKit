import Testing

@testable import TUIKit

// View-level contract tests for SyntaxTextView's selection, clipboard,
// undo, and find surfaces — keys go through keyDown, clipboard through an
// injected Pasteboard, no rendering required.

@MainActor
private func makeEditor(_ text: String) -> (SyntaxTextView, Pasteboard) {
    let editor = SyntaxTextView(text: text, language: "text")
    editor.frame = Rect(x: 0, y: 0, width: 40, height: 10)

    let pasteboard = Pasteboard()
    editor.pasteboard = pasteboard
    return (editor, pasteboard)
}

@MainActor
private func press(_ editor: SyntaxTextView, _ key: Key, _ modifiers: KeyModifiers = []) {
    _ = editor.keyDown(KeyInput(key: key, modifiers: modifiers))
}

@MainActor
struct EditorSelectionTests {
    @Test func shiftArrowsSelectAndControlCCopies() {
        let (editor, pasteboard) = makeEditor("hello world")

        for _ in 0..<5 {
            press(editor, .right, .shift)
        }

        #expect(editor.selectedText == "hello")

        press(editor, .character("c"), .control)
        #expect(pasteboard.string == "hello")
    }

    @Test func controlCWithoutSelectionIsNotConsumed() {
        let (editor, _) = makeEditor("hello")

        let consumed = editor.keyDown(KeyInput(key: .character("c"), modifiers: .control))

        #expect(!consumed, "no selection: ^C must bubble (apps may quit on it)")
    }

    @Test func cutPasteRoundTripsThroughThePasteboard() {
        let (editor, pasteboard) = makeEditor("cut me please")

        for _ in 0..<6 {
            press(editor, .right, .shift)
        }

        press(editor, .character("x"), .control)
        #expect(editor.text == " please")
        #expect(pasteboard.string == "cut me")

        press(editor, .end)
        press(editor, .character("v"), .control)
        #expect(editor.text == " pleasecut me")
    }

    @Test func classicInsertDeleteChordsWork() {
        let (editor, pasteboard) = makeEditor("classic")

        press(editor, .end, .shift)
        press(editor, .insert, .control)   // copy
        #expect(pasteboard.string == "classic")

        press(editor, .delete, .shift)     // cut
        #expect(editor.text == "")

        press(editor, .insert, .shift)     // paste
        #expect(editor.text == "classic")
    }

    @Test func typingUndoesAsOneRunViaControlZ() {
        let (editor, _) = makeEditor("")

        for character in "abc" {
            press(editor, .character(character))
        }

        press(editor, .character("z"), .control)
        #expect(editor.text == "")

        press(editor, .character("y"), .control)
        #expect(editor.text == "abc")
    }

    @Test func readOnlyEditorSelectsAndCopiesButNeverEdits() {
        let (editor, pasteboard) = makeEditor("view only")
        editor.isEditable = false

        press(editor, .end, .shift)
        press(editor, .character("c"), .control)
        #expect(pasteboard.string == "view only")

        press(editor, .character("x"), .control)
        press(editor, .backspace)
        #expect(editor.text == "view only")
    }

    @Test func findNextWrapsAndSelectsMatches() {
        let (editor, _) = makeEditor("alpha beta alpha")

        let count = editor.findMatches(of: "alpha")
        #expect(count == 2)

        #expect(editor.findNext())
        #expect(editor.selectedText == "alpha")
        #expect(editor.cursorPosition == Point(x: 5, y: 0))

        #expect(editor.findNext())
        #expect(editor.cursorPosition == Point(x: 16, y: 0))

        #expect(editor.findNext())   // wraps to the first
        #expect(editor.cursorPosition == Point(x: 5, y: 0))
    }

    @Test func replaceAllMatchesRewritesAndReports() {
        let (editor, _) = makeEditor("x + x + x")
        var changed = ""
        editor.onChanged = { changed = $0 }

        editor.findMatches(of: "x")
        let replaced = editor.replaceAllMatches(with: "y")

        #expect(replaced == 3)
        #expect(editor.text == "y + y + y")
        #expect(changed == "y + y + y")
    }

    @Test func scrollToCentersTheTarget() {
        let lines = (1...100).map { "line \($0)" }.joined(separator: "\n")
        let (editor, _) = makeEditor(lines)

        editor.scrollTo(line: 50, column: 2)

        #expect(editor.cursorPosition == Point(x: 2, y: 50))
        #expect(editor.verticalScrollSpan.map { $0.offset > 40 && $0.offset < 50 } == true)
    }

    @Test func pasteIsOneUndoStep() {
        let (editor, pasteboard) = makeEditor("")
        pasteboard.copy("pasted text")

        press(editor, .character("a"))
        press(editor, .character("v"), .control)
        #expect(editor.text == "apasted text")

        press(editor, .character("z"), .control)
        #expect(editor.text == "a")
    }
}
