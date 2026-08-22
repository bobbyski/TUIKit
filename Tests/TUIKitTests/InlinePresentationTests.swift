import Testing
@testable import TUIKit

// The inline presentation (ANSIDriver.Presentation.inline): the parts that
// are pure — where the prompt lands, how the cursor report parses, and the
// row offset in the wire frame — are pinned here; the pty harness covers
// the rest.

@Test func cursorReportsParseOutOfSurroundingInput() {
    #expect(ANSIDriver.parseCursorReport(Array("\u{1b}[12;1R".utf8))! == (12, 1))
    #expect(ANSIDriver.parseCursorReport(Array("junk\u{1b}[3;40Rmore".utf8))! == (3, 40))
    #expect(ANSIDriver.parseCursorReport(Array("\u{1b}[12;".utf8)) == nil, "incomplete")
    #expect(ANSIDriver.parseCursorReport(Array("\u{1b}[A".utf8)) == nil, "an arrow is not a report")
}

@Test func inlinePromptsLandAtTheCursorOrScrollToFit() {
    // Plenty of room: start on the cursor's line.
    let roomy = ANSIDriver.inlinePlacement(cursorRow: 5, cursorColumn: 1, terminalRows: 40, rows: 7)
    #expect(roomy == (origin: 4, height: 7, newlines: 0))

    // Mid-line cursor: the prompt begins on the next line.
    let partial = ANSIDriver.inlinePlacement(cursorRow: 5, cursorColumn: 12, terminalRows: 40, rows: 7)
    #expect(partial.origin == 5 && partial.newlines == 0)

    // Near the bottom: scroll just enough so the prompt ends on the last row.
    let low = ANSIDriver.inlinePlacement(cursorRow: 38, cursorColumn: 1, terminalRows: 40, rows: 7)
    #expect(low == (origin: 33, height: 7, newlines: 4))

    // Taller than the terminal: clamp to the terminal.
    let tall = ANSIDriver.inlinePlacement(cursorRow: 1, cursorColumn: 1, terminalRows: 5, rows: 20)
    #expect(tall == (origin: 0, height: 5, newlines: 0))
}

@Test func framesCanBeOffsetToAnOriginRow() {
    let esc = "\u{1b}"
    #expect(ANSIEncoder.frame(lines: ["a", "b"], previous: nil, originRow: 10) == "\(esc)[11;1Ha\(esc)[12;1Hb")
    #expect(ANSIEncoder.frame(lines: ["a", "b"], previous: ["a", "x"], originRow: 10) == "\(esc)[12;1Hb")
}
