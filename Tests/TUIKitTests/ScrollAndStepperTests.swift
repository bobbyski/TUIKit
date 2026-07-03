import Testing
@testable import TUIKit

// A fixed-size document that paints its row number on every line, so tests
// can read which part of the content is visible.
@MainActor
private final class NumberedDocument: View {
    let size: Size

    init(size: Size) {
        self.size = size
        super.init(frame: .zero)
    }

    override var intrinsicContentSize: Size? {
        size
    }

    override func draw(_ painter: Painter) {
        for row in 0..<size.height {
            let text = String(repeating: "\(row % 10)", count: size.width)
            painter.write(text, at: Point(x: 0, y: row))
        }
    }
}

@MainActor
private func makeScroll(
    content: Size,
    viewport: Size
) -> (ScrollView, Window) {
    let scroll = ScrollView(document: NumberedDocument(size: content))
    let window = Window(frame: Rect(origin: .zero, size: viewport))
    scroll.frame = window.bounds
    window.addSubview(scroll)
    window.layoutIfNeeded()
    return (scroll, window)
}

@MainActor
private func lines(_ window: Window) -> [String] {
    SceneRenderer(root: window).render(size: window.frame.size).textLines()
}

// MARK: - ScrollView

@Test @MainActor func scrollViewShowsTopOfDocumentAndIndicator() {
    let (_, window) = makeScroll(
        content: Size(width: 8, height: 20),
        viewport: Size(width: 10, height: 4)
    )

    let rendered = lines(window)

    // Rows 0-3 visible; the reserved last column carries the indicator.
    #expect(rendered[0].hasPrefix("00000000"))
    #expect(rendered[3].hasPrefix("33333333"))
    #expect(rendered[0].hasSuffix("█"))
    #expect(rendered[3].hasSuffix("░"))
}

@Test @MainActor func scrollViewScrollsWithKeysAndClamps() {
    let (scroll, window) = makeScroll(
        content: Size(width: 8, height: 20),
        viewport: Size(width: 10, height: 4)
    )

    var offsets: [Point] = []
    scroll.onOffsetChanged = { offsets.append($0) }

    _ = scroll.keyDown(KeyInput(key: .down))
    #expect(scroll.contentOffset == Point(x: 0, y: 1))
    #expect(lines(window)[0].hasPrefix("11111111"))

    _ = scroll.keyDown(KeyInput(key: .end))
    #expect(scroll.contentOffset == Point(x: 0, y: 16), "end clamps to content minus viewport")
    #expect(lines(window)[3].hasPrefix("99999999"))

    // Scrolling past the bottom stays clamped and emits nothing.
    _ = scroll.keyDown(KeyInput(key: .down))
    #expect(scroll.contentOffset == Point(x: 0, y: 16))

    _ = scroll.keyDown(KeyInput(key: .home))
    #expect(scroll.contentOffset == .zero)

    #expect(offsets == [Point(x: 0, y: 1), Point(x: 0, y: 16), .zero])
}

@Test @MainActor func scrollViewPagesByViewportHeight() {
    let (scroll, _) = makeScroll(
        content: Size(width: 8, height: 20),
        viewport: Size(width: 10, height: 5)
    )

    _ = scroll.keyDown(KeyInput(key: .pageDown))
    #expect(scroll.contentOffset.y == 4, "one page is the viewport height minus one")

    _ = scroll.keyDown(KeyInput(key: .pageUp))
    #expect(scroll.contentOffset.y == 0)
}

@Test @MainActor func scrollViewWheelScrollsWithoutFocus() {
    let (scroll, _) = makeScroll(
        content: Size(width: 8, height: 20),
        viewport: Size(width: 10, height: 4)
    )

    _ = scroll.mouseEvent(MouseInput(position: Point(x: 2, y: 2), action: .scrollDown, button: .none))
    _ = scroll.mouseEvent(MouseInput(position: Point(x: 2, y: 2), action: .scrollDown, button: .none))
    #expect(scroll.contentOffset.y == 2)

    _ = scroll.mouseEvent(MouseInput(position: Point(x: 2, y: 2), action: .scrollUp, button: .none))
    #expect(scroll.contentOffset.y == 1)
}

@Test @MainActor func scrollViewScrollsHorizontallyAndReservesBottomRow() {
    let (scroll, window) = makeScroll(
        content: Size(width: 30, height: 3),
        viewport: Size(width: 10, height: 4)
    )

    // No vertical overflow (3 content rows in a 3-row viewport after the
    // horizontal bar takes the bottom row), so the full width is content.
    let before = lines(window)
    #expect(before[0].hasPrefix("0000000000"))
    #expect(before[3].contains("█"))
    #expect(before[3].contains("░"))

    _ = scroll.keyDown(KeyInput(key: .right))
    #expect(scroll.contentOffset == Point(x: 1, y: 0))

    _ = scroll.keyDown(KeyInput(key: .left))
    _ = scroll.keyDown(KeyInput(key: .left))
    #expect(scroll.contentOffset == .zero, "left clamps at the origin")
}

@Test @MainActor func scrollViewFitsSmallDocumentWithoutIndicators() {
    let (scroll, window) = makeScroll(
        content: Size(width: 6, height: 2),
        viewport: Size(width: 10, height: 4)
    )

    let rendered = lines(window)
    #expect(!rendered.joined().contains("█"), "no overflow, no indicator")

    _ = scroll.keyDown(KeyInput(key: .down))
    #expect(scroll.contentOffset == .zero, "nothing to scroll")
}

@Test @MainActor func scrollViewSilentProgrammaticOffset() {
    let (scroll, window) = makeScroll(
        content: Size(width: 8, height: 20),
        viewport: Size(width: 10, height: 4)
    )

    var events: [Point] = []
    scroll.onOffsetChanged = { events.append($0) }

    scroll.setOffset(Point(x: 0, y: 50))
    #expect(scroll.contentOffset == Point(x: 0, y: 16), "programmatic offsets clamp too")
    #expect(events.isEmpty)
    #expect(lines(window)[3].hasPrefix("99999999"))
}

// MARK: - Stepper

@MainActor
private func renderedLine(_ stepper: Stepper, focused: Bool = false) -> String {
    let size = stepper.intrinsicContentSize ?? Size(width: 12, height: 1)
    let window = Window(frame: Rect(origin: .zero, size: size))
    stepper.frame = window.bounds
    window.addSubview(stepper)

    if focused {
        window.makeFirstResponder(stepper)
    }

    return SceneRenderer(root: window).render(size: size).textLines()[0]
}

@Test @MainActor func stepperRendersValueBetweenButtons() {
    let stepper = Stepper(value: 42, in: 0...100)

    // "[-] " + 3-wide field + " [+]" = 11.
    #expect(stepper.intrinsicContentSize == Size(width: 11, height: 1))
    #expect(renderedLine(stepper) == "[-]  42 [+]")
}

@Test @MainActor func stepperStepsWithKeysAndClampsAtBounds() {
    let stepper = Stepper(value: 9, in: 0...10, step: 2)
    var events: [Int] = []
    stepper.onValueChanged = { events.append($0) }

    _ = stepper.keyDown(KeyInput(key: .up))
    #expect(stepper.value == 10, "step clamps into range")

    _ = stepper.keyDown(KeyInput(key: .up))
    #expect(stepper.value == 10, "at the bound nothing changes or fires")

    _ = stepper.keyDown(KeyInput(key: .character("-")))
    #expect(stepper.value == 8)

    _ = stepper.keyDown(KeyInput(key: .home))
    #expect(stepper.value == 0)

    _ = stepper.keyDown(KeyInput(key: .end))
    #expect(stepper.value == 10)

    #expect(events == [10, 8, 0, 10])
}

@Test @MainActor func stepperClicksOnBracketButtons() {
    let stepper = Stepper(value: 5, in: 0...9)
    stepper.frame = Rect(x: 0, y: 0, width: 11, height: 1)

    // "[-] 5 [+]" — decrement x0..2, value field x4, increment x6..8.
    _ = stepper.mouseEvent(MouseInput(position: Point(x: 1, y: 0), action: .press, button: .left))
    #expect(stepper.value == 4)

    _ = stepper.mouseEvent(MouseInput(position: Point(x: 7, y: 0), action: .press, button: .left))
    _ = stepper.mouseEvent(MouseInput(position: Point(x: 7, y: 0), action: .press, button: .left))
    #expect(stepper.value == 6)

    // A click on the value field does nothing.
    _ = stepper.mouseEvent(MouseInput(position: Point(x: 4, y: 0), action: .press, button: .left))
    #expect(stepper.value == 6)
}

@Test @MainActor func stepperSilentProgrammaticValue() {
    let stepper = Stepper(value: 0, in: -50...50)
    var events: [Int] = []
    stepper.onValueChanged = { events.append($0) }

    stepper.setValue(75)
    #expect(stepper.value == 50, "programmatic values clamp")
    #expect(events.isEmpty)

    stepper.setValue(-10, notify: true)
    #expect(events == [-10])
}

@Test @MainActor func stepperFieldWidthFollowsRangeBounds() {
    let stepper = Stepper(value: -5, in: -100...100)

    // "[-] " + 4-wide field ("-100") + " [+]" = 12.
    #expect(stepper.intrinsicContentSize == Size(width: 12, height: 1))
    #expect(renderedLine(stepper) == "[-]   -5 [+]")
}
