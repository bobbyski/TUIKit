import Testing
@testable import TUIKit

@Test func newBufferIsBlank() {
    let buffer = CellBuffer(size: Size(width: 4, height: 2))

    #expect(buffer.textLines() == ["    ", "    "])
    #expect(buffer[Point(x: 0, y: 0)] == .blank)
}

@Test func subscriptReadsAndWritesInsideBounds() {
    var buffer = CellBuffer(size: Size(width: 3, height: 3))
    let cell = TerminalCell(character: "X", style: CellStyle(flags: .bold))

    buffer[Point(x: 1, y: 2)] = cell

    #expect(buffer[Point(x: 1, y: 2)] == cell)
    #expect(buffer.text(row: 2) == " X ")
}

@Test func subscriptIgnoresWritesOutsideBounds() {
    var buffer = CellBuffer(size: Size(width: 2, height: 2))

    buffer[Point(x: -1, y: 0)] = TerminalCell(character: "A")
    buffer[Point(x: 2, y: 0)] = TerminalCell(character: "B")
    buffer[Point(x: 0, y: 5)] = TerminalCell(character: "C")

    #expect(buffer.textLines() == ["  ", "  "])
    #expect(buffer[Point(x: 9, y: 9)] == .blank)
}

@Test func writeClipsAtTheRightEdge() {
    var buffer = CellBuffer(size: Size(width: 5, height: 1))

    buffer.write("clipped", at: Point(x: 2, y: 0))

    #expect(buffer.text(row: 0) == "  cli")
}

@Test func fillClipsToBufferBounds() {
    var buffer = CellBuffer(size: Size(width: 4, height: 3))

    buffer.fill(
        Rect(x: 2, y: 1, width: 10, height: 10),
        with: TerminalCell(character: "#")
    )

    #expect(buffer.textLines() == ["    ", "  ##", "  ##"])
}

@Test func textProjectionIgnoresStyle() {
    var buffer = CellBuffer(size: Size(width: 3, height: 1))

    buffer.write(
        "abc",
        at: .zero,
        style: CellStyle(foreground: .named(.red), flags: [.bold, .underline])
    )

    #expect(buffer.text(row: 0) == "abc")
    #expect(buffer.text(row: 7) == "")
}
