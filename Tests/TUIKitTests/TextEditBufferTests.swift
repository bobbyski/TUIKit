import Testing

@testable import TUIKit

// Contract tests for the pure editing engine: selection, editing, undo
// coalescing, and find — no view, no rendering.

@MainActor
struct TextEditBufferTests {
    @Test func shiftMovementSelectsAndPlainMovementClears() {
        let buffer = TextEditBuffer(text: "hello world")

        buffer.moveCursor(to: Point(x: 5, y: 0), extending: true)
        #expect(buffer.selectedText == "hello")

        buffer.moveCursor(to: Point(x: 6, y: 0), extending: false)
        #expect(!buffer.hasSelection)
    }

    @Test func selectionNormalizesWhenMadeBackwards() {
        let buffer = TextEditBuffer(text: "abcdef")

        buffer.moveCursor(to: Point(x: 4, y: 0))
        buffer.moveCursor(to: Point(x: 1, y: 0), extending: true)

        #expect(buffer.selectedText == "bcd")
        #expect(buffer.selectedRange?.start == Point(x: 1, y: 0))
    }

    @Test func multiLineSelectionAndPerLineRanges() {
        let buffer = TextEditBuffer(text: "one\ntwo\nthree")

        buffer.moveCursor(to: Point(x: 2, y: 0))
        buffer.moveCursor(to: Point(x: 3, y: 2), extending: true)

        #expect(buffer.selectedText == "e\ntwo\nthr")
        #expect(buffer.selection(onLine: 0) == 2..<3)
        #expect(buffer.selection(onLine: 1) == 0..<3)
        #expect(buffer.selection(onLine: 2) == 0..<3)
    }

    @Test func insertReplacesTheSelection() {
        let buffer = TextEditBuffer(text: "hello world")

        buffer.moveCursor(to: Point(x: 0, y: 0))
        buffer.moveCursor(to: Point(x: 5, y: 0), extending: true)
        buffer.insert("goodbye")

        #expect(buffer.text == "goodbye world")
        #expect(buffer.cursor == Point(x: 7, y: 0))
    }

    @Test func deleteBackwardRemovesSelectionOrJoinsLines() {
        let buffer = TextEditBuffer(text: "ab\ncd")

        buffer.moveCursor(to: Point(x: 0, y: 1))
        buffer.deleteBackward()
        #expect(buffer.text == "abcd")

        buffer.moveCursor(to: Point(x: 1, y: 0))
        buffer.moveCursor(to: Point(x: 3, y: 0), extending: true)
        buffer.deleteBackward()
        #expect(buffer.text == "ad")
    }

    @Test func selectWordAndSelectLine() {
        let buffer = TextEditBuffer(text: "let answer_42 = value")

        buffer.selectWord(at: Point(x: 7, y: 0))
        #expect(buffer.selectedText == "answer_42")

        buffer.selectLine(0)
        #expect(buffer.selectedText == "let answer_42 = value")
    }

    @Test func typingCoalescesIntoOneUndoStep() {
        let buffer = TextEditBuffer(text: "")

        for character in "hello" {
            buffer.insert(String(character))
        }

        #expect(buffer.text == "hello")

        buffer.undo()
        #expect(buffer.text == "")

        buffer.redo()
        #expect(buffer.text == "hello")
    }

    @Test func movementBreaksTheTypingRun() {
        let buffer = TextEditBuffer(text: "")

        buffer.insert("a")
        buffer.insert("b")
        buffer.moveCursor(to: Point(x: 1, y: 0))
        buffer.moveCursor(to: Point(x: 2, y: 0))
        buffer.insert("c")
        buffer.insert("d")

        buffer.undo()
        #expect(buffer.text == "ab")

        buffer.undo()
        #expect(buffer.text == "")
    }

    @Test func undoRestoresSelectionReplacement() {
        let buffer = TextEditBuffer(text: "one two three")

        buffer.moveCursor(to: Point(x: 4, y: 0))
        buffer.moveCursor(to: Point(x: 7, y: 0), extending: true)
        buffer.insert("2")
        #expect(buffer.text == "one 2 three")

        buffer.undo()
        #expect(buffer.text == "one two three")
        #expect(buffer.selectedText == "two")
    }

    @Test func newEditsClearTheRedoStack() {
        let buffer = TextEditBuffer(text: "")

        buffer.insert("a")
        buffer.undo()
        #expect(buffer.canRedo)

        buffer.insert("b")
        #expect(!buffer.canRedo)
        #expect(buffer.text == "b")
    }

    @Test func multiLineInsertAndUndo() {
        let buffer = TextEditBuffer(text: "start end")

        buffer.moveCursor(to: Point(x: 6, y: 0))
        buffer.insert("mid\ndle ")
        #expect(buffer.text == "start mid\ndle end")
        #expect(buffer.cursor == Point(x: 4, y: 1))

        buffer.undo()
        #expect(buffer.text == "start end")
    }

    @Test func findMatchesAreOrderedAndCaseControlled() {
        let buffer = TextEditBuffer(text: "Cat cat\nconcatenate")

        let insensitive = buffer.matches(of: "cat")
        #expect(insensitive.count == 3)
        #expect(insensitive[0] == TextEditBuffer.Match(line: 0, range: 0..<3))
        #expect(insensitive[2] == TextEditBuffer.Match(line: 1, range: 3..<6))

        let sensitive = buffer.matches(of: "Cat", caseSensitive: true)
        #expect(sensitive.count == 1)
    }

    @Test func replaceAllReplacesEveryMatchAndIsUndoable() {
        let buffer = TextEditBuffer(text: "a b a b a")

        let count = buffer.replaceAll(of: "a", with: "x")
        #expect(count == 3)
        #expect(buffer.text == "x b x b x")

        buffer.undo()
        buffer.undo()
        buffer.undo()
        #expect(buffer.text == "a b a b a")
    }

    @Test func setTextResetsHistoryAndSelection()  {
        let buffer = TextEditBuffer(text: "old")

        buffer.selectAll()
        buffer.insert("new")
        buffer.setText("fresh")

        #expect(!buffer.canUndo)
        #expect(!buffer.hasSelection)
        #expect(buffer.cursor == .zero)
    }
}
