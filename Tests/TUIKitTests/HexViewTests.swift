import Foundation
import Testing
@testable import TUIKit

// A hex dump is three columns of fixed-width text, which is the one shape a
// terminal renders better than a canvas — and the shape ActiveUI had been
// composing into a `Label`, which reads correctly and cannot carry a caret.

@MainActor
private func render(_ view: TUIView, width: Int, height: Int) -> [String] {
    let window = Window(frame: Rect(x: 0, y: 0, width: width, height: height))
    view.frame = Rect(x: 0, y: 0, width: width, height: height)
    window.addSubview(view)
    return SceneRenderer(root: window).render(size: Size(width: width, height: height)).textLines()
}

@Test @MainActor func aHexViewDrawsAddressBytesAndText() {
    let view = HexView(bytes: Array("Hi!".utf8), baseAddress: 0x1000)
    view.bytesPerRow = 8

    let line = render(view, width: 60, height: 2)[0]
    #expect(line.hasPrefix("1000"), "the address, at the width the last one needs")
    #expect(line.contains("48 69 21"), "the bytes, in hex")
    #expect(line.contains("Hi!"), "and what they say")
}

@Test @MainActor func unprintableBytesTakeTheirPlaceholder() {
    let view = HexView(bytes: [0x00, 0x1B, 0x41])
    view.bytesPerRow = 4

    let line = render(view, width: 40, height: 1)[0]
    #expect(line.contains("00 1B 41"))
    #expect(line.hasSuffix("..A") || line.contains("..A"), "two unprintables and an A")
}

@Test @MainActor func theRowWidthFitsTheViewUnlessItIsPinned() {
    let view = HexView(bytes: [UInt8](repeating: 0, count: 64))

    // Every byte costs four columns: two hex digits, the space after them,
    // and one character in the text column.
    #expect(view.bytesThatFit(width: 40) > view.bytesThatFit(width: 24))

    view.bytesPerRow = 16
    #expect(view.bytesThatFit(width: 24) == 16, "pinned means pinned, whatever the width")
}

@Test @MainActor func aFittedRowHoldsAWholeNumberOfGroups() {
    let view = HexView(bytes: [UInt8](repeating: 0, count: 256))

    // 80 columns has room for 18 bytes, which would step the address column by
    // 0x12 -- 0000, 0012, 0024. A hex dump is read by counting across a row, so
    // the leftover columns stay empty and the row holds two groups of eight.
    #expect(view.bytesThatFit(width: 80) == 16)
    #expect(view.bytesThatFit(width: 60) == 8)

    // Narrower than one whole group shows what it can rather than nothing.
    #expect(view.bytesThatFit(width: 20) == 3)

    // And a caller who wants the width back can have it.
    view.fitSnapsToGroups = false
    #expect(view.bytesThatFit(width: 80) == 18)
}

@Test @MainActor func arrowsMoveTheCaretByOneByteAndOneRow() {
    let view = HexView(bytes: [UInt8](repeating: 0, count: 64))
    view.bytesPerRow = 8
    view.frame = Rect(x: 0, y: 0, width: 60, height: 8)

    _ = view.keyDown(KeyInput(key: .right))
    #expect(view.caret == 1)

    _ = view.keyDown(KeyInput(key: .down))
    #expect(view.caret == 9, "one row is one row of bytes")

    _ = view.keyDown(KeyInput(key: .home))
    #expect(view.caret == 0)

    _ = view.keyDown(KeyInput(key: .left))
    #expect(view.caret == 0, "and it stops at the start rather than wrapping")
}

@Test @MainActor func typingTwoHexDigitsWritesOneByte() {
    let view = HexView(bytes: [0x00, 0x00])
    view.bytesPerRow = 8
    view.isEditable = true
    view.frame = Rect(x: 0, y: 0, width: 60, height: 2)

    var edits: [(Int, UInt8)] = []
    view.onEdit = { edits.append(($0, $1)) }

    _ = view.keyDown(KeyInput(key: .character("4")))
    #expect(view.bytes[0] == 0x00, "one digit is half a byte — nothing is written yet")
    #expect(edits.isEmpty)

    _ = view.keyDown(KeyInput(key: .character("1")))
    #expect(view.bytes[0] == 0x41)
    #expect(edits.count == 1)
    #expect(view.caret == 1, "and the caret steps on to the next byte")
}

@Test @MainActor func aReadOnlyViewIgnoresTyping() {
    let view = HexView(bytes: [0x00])
    view.frame = Rect(x: 0, y: 0, width: 60, height: 1)

    _ = view.keyDown(KeyInput(key: .character("4")))
    _ = view.keyDown(KeyInput(key: .character("1")))
    #expect(view.bytes == [0x00])
}

@Test @MainActor func tabCrossesToTheTextColumnRatherThanLeaving() {
    let view = HexView(bytes: [0x41])
    view.frame = Rect(x: 0, y: 0, width: 60, height: 1)

    #expect(view.isEditingText == false)
    #expect(view.keyDown(KeyInput(key: .tab)))
    #expect(view.isEditingText, "the two halves of a hex editor are one control")
}

@Test @MainActor func clickingAByteInEitherColumnPutsTheCaretOnIt() {
    let view = HexView(bytes: [UInt8](repeating: 0, count: 32), baseAddress: 0)
    view.bytesPerRow = 8
    view.frame = Rect(x: 0, y: 0, width: 60, height: 4)

    // Address is four digits, then two spaces: the third byte's hex pair
    // starts at 4 + 2 + 2*3.
    _ = view.mouseEvent(MouseInput(position: Point(x: 12, y: 1), action: .press, button: .left))
    #expect(view.caret == 10, "row one, byte two")
    #expect(view.isEditingText == false)

    // The text column for the same row.
    _ = view.mouseEvent(MouseInput(position: Point(x: 4 + 2 + 8 * 3 - 1 + 2 + 3, y: 1),
                                   action: .press, button: .left))
    #expect(view.isEditingText, "a click in the text column edits text")
    #expect(view.caret == 11)
}
