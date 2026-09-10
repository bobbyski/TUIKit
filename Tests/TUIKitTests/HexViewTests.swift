import Foundation
import Testing
@testable import TUIKit

// A hex dump is three columns of fixed-width text, which is the one shape a
// terminal renders better than a canvas. Parity target: AUIHexView — the
// control bar, read-only and edit modes, fit to window, and a text column
// that reads ASCII, EBCDIC, UTF-8 or UTF-16.

@MainActor
private func render(_ view: TUIView, width: Int, height: Int) -> [String] {
    let window = Window(frame: Rect(x: 0, y: 0, width: width, height: height))
    view.frame = Rect(x: 0, y: 0, width: width, height: height)
    window.addSubview(view)
    return SceneRenderer(root: window).render(size: Size(width: width, height: height)).textLines()
}

@MainActor
private func styles(_ view: TUIView, width: Int, height: Int, row: Int) -> [CellStyle] {
    let window = Window(frame: Rect(x: 0, y: 0, width: width, height: height))
    view.frame = Rect(x: 0, y: 0, width: width, height: height)
    window.addSubview(view)
    let buffer = SceneRenderer(root: window).render(size: Size(width: width, height: height))
    return (0..<width).map { buffer[Point(x: $0, y: row)].style }
}

/// A grid-only view: the bar is its own set of tests.
@MainActor
private func bareView(_ bytes: [UInt8], baseAddress: UInt64 = 0) -> HexView {
    let view = HexView(bytes: bytes, baseAddress: baseAddress)
    view.showsControlBar = false
    return view
}

// MARK: - The grid

@Test @MainActor func aHexViewDrawsAddressBytesAndText() {
    let view = bareView(Array("Hi!".utf8), baseAddress: 0x1000)
    view.bytesPerRow = 8

    let line = render(view, width: 60, height: 2)[0]
    #expect(line.hasPrefix("1000"))
    #expect(line.contains("48 69 21"))
    #expect(line.contains("Hi!"))
}

@Test @MainActor func unprintableBytesTakeTheirPlaceholder() {
    let view = bareView([0x00, 0x1B, 0x41])
    view.bytesPerRow = 4

    let line = render(view, width: 40, height: 1)[0]
    #expect(line.contains("00 1B 41"))
    #expect(line.contains("..A"))
}

@Test @MainActor func theRowWidthFitsTheViewUnlessItIsPinned() {
    let view = bareView(Array(repeating: 0xAA, count: 64))
    view.fitSnapsToGroups = false

    // Four columns per byte over the address and gaps.
    #expect(view.bytesThatFit(width: 4 + 4 - 1 + 4 * 10) == 10)

    view.bytesPerRow = 16
    #expect(view.bytesThatFit(width: 30) == 16, "pinned wins, and the row scrolls off instead")
}

@Test @MainActor func aFittedRowHoldsAWholeNumberOfGroups() {
    let view = bareView(Array(repeating: 0x55, count: 64))

    let raw = view.bytesThatFit(width: 4 + 3 + 4 * 11)
    view.fitSnapsToGroups = false
    let free = view.bytesThatFit(width: 4 + 3 + 4 * 11)

    #expect(free == 11)
    #expect(raw == 8, "snapped down to the group, so the addresses step by round numbers")
}

@Test @MainActor func hidingTheTextColumnBuysHexWidth() {
    let view = bareView(Array(repeating: 0x55, count: 64))
    view.fitSnapsToGroups = false
    let with = view.bytesThatFit(width: 43)

    view.showsTextColumn = false
    let without = view.bytesThatFit(width: 43)

    #expect(without > with, "three columns per byte instead of four")
    #expect(!render(view, width: 43, height: 2)[0].contains("UUU"), "no text column drawn")
}

// MARK: - Caret and stepping

@Test @MainActor func arrowsStepByNibbleInHexAndByRowVertically() {
    let view = bareView(Array(0..<32))
    view.bytesPerRow = 8
    _ = render(view, width: 60, height: 4)

    _ = view.keyDown(KeyInput(key: .right))
    #expect(view.caret == 0 && view.caretNibble == 1, "right crosses the byte's low nibble first")

    _ = view.keyDown(KeyInput(key: .right))
    #expect(view.caret == 1 && view.caretNibble == 0)

    _ = view.keyDown(KeyInput(key: .down))
    #expect(view.caret == 9, "a row down")

    _ = view.keyDown(KeyInput(key: .end))
    #expect(view.caret == 15, "End is the row's edge — a dump is read a row at a time")

    _ = view.keyDown(KeyInput(key: .home))
    #expect(view.caret == 8)

    _ = view.keyDown(KeyInput(key: .left))
    #expect(view.caret == 7 && view.caretNibble == 1, "back onto the previous byte's low half")
}

@Test @MainActor func typingHexDigitsWritesNibbleByNibble() {
    let view = bareView([0x00, 0x00])
    view.bytesPerRow = 8
    _ = render(view, width: 60, height: 1)

    var edits: [(Int, UInt8)] = []
    view.onEdit = { edits.append(($0, $1)) }

    _ = view.keyDown(KeyInput(key: .character("4")))
    #expect(view.bytes[0] == 0x40, "high nibble lands at once, the way hex editors type")

    _ = view.keyDown(KeyInput(key: .character("1")))
    #expect(view.bytes[0] == 0x41)
    #expect(view.caret == 1 && view.caretNibble == 0, "a finished byte steps on")
    #expect(edits.map(\.1) == [0x40, 0x41])

    _ = view.keyDown(KeyInput(key: .character("g")))
    #expect(view.bytes[1] == 0x00, "not a hex digit")
}

@Test @MainActor func clickingAByteInEitherColumnPutsTheCaretOnIt() {
    let view = bareView(Array(0..<32))
    view.bytesPerRow = 8
    _ = render(view, width: 60, height: 4)

    // Row 1, third byte, low nibble: address(4) + 2 + byte 2's second digit.
    _ = view.mouseEvent(MouseInput(position: Point(x: 4 + 2 + 2 * 3 + 1, y: 1), action: .press, button: .left))
    #expect(view.caret == 10 && view.caretNibble == 1 && !view.isEditingText)

    // Text column of row 1: 4 + 2 + 23 + 2 + column 3.
    _ = view.mouseEvent(MouseInput(position: Point(x: 4 + 2 + 23 + 2 + 3, y: 1), action: .press, button: .left))
    #expect(view.caret == 11 && view.isEditingText)
}

// MARK: - Read-only and edit modes

@Test @MainActor func aReadOnlyViewKeepsTheCaretButDrawsNoCursorAndTakesNoTyping() {
    let view = bareView([0x00, 0x01])
    view.bytesPerRow = 8

    var moved: [Int] = []
    view.onCaretMoved = { moved.append($0) }

    // Editable: the block cursor inverts the caret's nibble cell.
    #expect(styles(view, width: 40, height: 1, row: 0)[6] != CellStyle(), "an edit cursor is drawn")

    view.isEditable = false
    _ = view.keyDown(KeyInput(key: .character("F")))
    #expect(view.bytes == [0x00, 0x01], "typing changes nothing")

    _ = view.keyDown(KeyInput(key: .right))
    _ = view.keyDown(KeyInput(key: .right))
    #expect(moved == [1], "the caret and its callback keep working — that is what a viewer is for")

    let row = styles(view, width: 40, height: 1, row: 0)
    #expect(row[6] == CellStyle() && row[9] == CellStyle(),
            "no cursor anywhere: a cursor is a promise that typing will land")
}

@Test @MainActor func theUnderlineCursorIsABarNotABlock() {
    let view = bareView([0xAB])
    view.bytesPerRow = 8
    view.cursorStyle = .underline

    let cell = styles(view, width: 40, height: 1, row: 0)[6]
    #expect(cell.flags.contains(.underline))
    #expect(cell.background == CellStyle().background, "the cell is not filled")
}

// MARK: - Encodings

@Test func ebcdicReadsCodePage037() {
    let cells = ByteEncoding.ebcdic.cells(for: [0x40, 0xC1, 0x81, 0xF1, 0x00])
    #expect(cells.map(\.character) == [" ", "A", "a", "1", nil],
            "0x40 is the space and the letters are where 037 puts them")
    #expect(ByteEncoding.ebcdic.byte(for: "A") == 0xC1, "and typing goes back the same way")
}

@Test func utf8CellsSpanTheirBytes() {
    // "aé€" is 1 + 2 + 3 bytes.
    let cells = ByteEncoding.utf8.cells(for: Array("aé€".utf8))
    #expect(cells.map(\.character) == ["a", "é", "€"])
    #expect(cells.map(\.byteCount) == [1, 2, 3], "a character is drawn across its own bytes")

    // A continuation byte alone is not a character.
    #expect(ByteEncoding.utf8.cells(for: [0xA9]).first?.character == nil)

    // The window backs up to the lead byte, at most three bytes.
    let bytes = Array("aé".utf8)   // 61 C3 A9
    #expect(ByteEncoding.utf8.windowStart(before: 2, in: bytes) == 1)
}

@Test func utf16ReadsUnitsAndSurrogatePairs() {
    // "A" LE, then 𝄞 (surrogate pair) — D834 DD1E.
    let bytes: [UInt8] = [0x41, 0x00, 0x34, 0xD8, 0x1E, 0xDD]
    let cells = ByteEncoding.utf16.cells(for: bytes)
    #expect(cells.map(\.byteCount) == [2, 4])
    #expect(cells[0].character == "A")
    #expect(cells[1].character == "𝄞", "one character written on four bytes")

    let big = ByteEncoding.utf16BigEndian.cells(for: [0x00, 0x41])
    #expect(big.first?.character == "A")
    #expect(ByteEncoding.utf16.windowStart(before: 5, in: bytes) == 4, "alignment from the start of the data")
}

@Test @MainActor func theTextColumnDrawsAMultiByteCharacterAcrossItsBytes() {
    let view = bareView(Array("aé!".utf8))   // 61 C3 A9 21
    view.bytesPerRow = 8
    view.encoding = .utf8

    let line = render(view, width: 60, height: 1)[0]
    #expect(line.contains("61 C3 A9 21"))

    // Text column: 'a', then 'é' over its two bytes, then '!' — never a
    // dot for a continuation byte of a character that decoded.
    let text = String(line.dropFirst(4 + 2 + 23 + 2))
    #expect(text.contains("a") && text.contains("é") && text.contains("!"))
    #expect(!text.contains("."), "no rubbish where the decoder was in step")
}

@Test @MainActor func theTextColumnRefusesTheCaretInAMultiByteEncoding() {
    let view = bareView(Array("hello".utf8))
    view.bytesPerRow = 8
    view.encoding = .utf8
    _ = render(view, width: 60, height: 1)

    #expect(view.keyDown(KeyInput(key: .tab)) == false, "Tab has nothing to cross to")

    _ = view.mouseEvent(MouseInput(position: Point(x: 4 + 2 + 23 + 2 + 1, y: 0), action: .press, button: .left))
    #expect(view.caret == 1 && !view.isEditingText, "a click moves the caret but stays in hex")

    // And crossing works again the moment the encoding is single-byte.
    view.encoding = .ebcdic
    #expect(view.keyDown(KeyInput(key: .tab)) == true)
}

@Test @MainActor func typingInTheTextColumnWritesTheEncodingsByte() {
    let view = bareView([0x00, 0x00])
    view.bytesPerRow = 8
    view.encoding = .ebcdic
    _ = render(view, width: 60, height: 1)

    _ = view.keyDown(KeyInput(key: .tab))
    _ = view.keyDown(KeyInput(key: .character("A")))

    #expect(view.bytes[0] == 0xC1, "'A' through EBCDIC, not through ASCII")
    #expect(view.caret == 1, "a typed character steps a whole byte")
}

// MARK: - The control bar

@Test @MainActor func theControlBarOffersWidthAndEncodingAndTracksTheProperties() {
    let view = HexView(bytes: Array("Hello".utf8))
    let rows = render(view, width: 60, height: 4)

    #expect(rows[0].contains("Bytes") && rows[0].contains("Fit") && rows[0].contains("Text") && rows[0].contains("ASCII"))
    #expect(rows[1].contains("48 65 6C 6C 6F"), "the grid starts under the bar")

    let pickers = view.subviews.compactMap { $0 as? PopUpButton }
    let width = pickers.first { $0.items.contains("Fit") }!
    let text = pickers.first { $0.items.contains("EBCDIC") }!

    width.select(HexView.widthChoices.firstIndex(of: 8)!, notify: true)
    #expect(view.bytesPerRow == 8)

    text.select(1, notify: true)
    #expect(view.encoding == .ebcdic)

    // The pickers are views of the properties, not second copies.
    view.bytesPerRow = 16
    #expect(width.selectedIndex == HexView.widthChoices.firstIndex(of: 16))
    view.encoding = .utf8
    #expect(text.selectedIndex == 2)
}

@Test @MainActor func noChromeMeansExactlyTheGrid() {
    let view = HexView(bytes: Array(0..<24))
    view.showsControlBar = false
    view.bytesPerRow = 8
    view.rowsShown = 3

    #expect(view.intrinsicContentSize == Size(width: 4 + 2 + 23 + 2 + 8, height: 3),
            "as big as it says, and no bar row")

    view.showsControlBar = true
    #expect(view.intrinsicContentSize?.height == 4, "the bar takes its row back")

    let rows = render(view, width: 60, height: 4)
    #expect(rows[1].hasPrefix("0000"), "grid under the bar")
}
