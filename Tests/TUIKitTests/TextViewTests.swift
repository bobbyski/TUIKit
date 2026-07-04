import Testing
@testable import TUIKit

@MainActor
private func render(_ view: TUIView, size: Size) -> [String] {
    let window = Window(frame: Rect(origin: .zero, size: size))
    view.frame = Rect(origin: .zero, size: size)
    window.addSubview(view)
    return SceneRenderer(root: window).render(size: size).textLines()
}

@Test @MainActor func textViewWrapsLongLinesAtWordBoundaries() {
    let view = TextView(text: "the quick brown fox jumps")
    view.frame = Rect(x: 0, y: 0, width: 12, height: 4)

    let lines = render(view, size: Size(width: 12, height: 4))
    #expect(lines[0].hasPrefix("the quick"))
    #expect(lines[1].hasPrefix("brown fox"))
    #expect(lines[2].hasPrefix("jumps"))
}

@Test @MainActor func textViewDownArrowMovesByVisualRow() {
    let view = TextView(text: "the quick brown fox jumps")
    view.frame = Rect(x: 0, y: 0, width: 12, height: 4)
    _ = render(view, size: Size(width: 12, height: 4))

    // Cursor starts at (0,0); down drops to the second wrapped row, same
    // logical line.
    _ = view.keyDown(KeyInput(key: .down))
    #expect(view.cursorPosition == Point(x: 10, y: 0))
}

@Test @MainActor func textViewClickMapsToLogicalColumn() {
    let view = TextView(text: "the quick brown fox jumps")
    view.frame = Rect(x: 0, y: 0, width: 12, height: 4)
    _ = render(view, size: Size(width: 12, height: 4))

    // Click on the third wrapped row ("jumps"), column 2.
    _ = view.mouseEvent(MouseInput(position: Point(x: 2, y: 2), action: .press, button: .left))
    #expect(view.cursorPosition == Point(x: 22, y: 0))
}

@Test @MainActor func textViewEditingStaysLineOriented() {
    let view = TextView(text: "hello world")
    view.frame = Rect(x: 0, y: 0, width: 20, height: 3)

    var changes: [String] = []
    view.onChanged = { changes.append($0) }

    // Split into two paragraphs at the space, then type into the second.
    _ = view.mouseEvent(MouseInput(position: Point(x: 5, y: 0), action: .press, button: .left))
    _ = view.keyDown(KeyInput(key: .delete))    // remove the space
    _ = view.keyDown(KeyInput(key: .enter))     // new paragraph
    #expect(view.text == "hello\nworld")
    #expect(view.cursorPosition == Point(x: 0, y: 1))

    _ = view.keyDown(KeyInput(key: .character("!")))
    #expect(view.text == "hello\n!world")
    #expect(changes.last == "hello\n!world")
}

@Test @MainActor func textViewTabIsLeftForFocusMovement() {
    let view = TextView(text: "hi")
    view.frame = Rect(x: 0, y: 0, width: 10, height: 2)

    // Tab is not consumed, so the responder chain can move focus.
    #expect(view.keyDown(KeyInput(key: .tab)) == false)
    #expect(view.text == "hi")
}

@Test @MainActor func readOnlyTextViewIgnoresEditsButStillScrolls() {
    let view = TextView(text: "one two three four five six")
    view.isEditable = false
    view.frame = Rect(x: 0, y: 0, width: 8, height: 2)
    _ = render(view, size: Size(width: 8, height: 2))

    #expect(view.keyDown(KeyInput(key: .character("x"))) == false)
    #expect(view.text == "one two three four five six")

    // The wheel still scrolls a read-only view.
    _ = view.mouseEvent(MouseInput(position: .zero, action: .scrollDown, button: .left))
    let lines = render(view, size: Size(width: 8, height: 2))
    #expect(!lines[0].hasPrefix("one"), "scrolled past the first visual row")
}
