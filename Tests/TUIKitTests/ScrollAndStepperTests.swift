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

    let buffer = SceneRenderer(root: window).render(size: window.frame.size)
    let rendered = buffer.textLines()

    // Rows 0-3 visible; the reserved last column carries the indicator.
    #expect(rendered[0].hasPrefix("00000000"))
    #expect(rendered[3].hasPrefix("33333333"))

    // Solid indicator: white thumb on top, gray track below — explicit
    // colors, visibly distinct from the window background and each other.
    #expect(buffer[Point(x: 9, y: 0)].style.background == .named(.white))
    #expect(buffer[Point(x: 9, y: 3)].style.background == .named(.brightBlack))
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
    let buffer = SceneRenderer(root: window).render(size: window.frame.size)
    #expect(buffer.textLines()[0].hasPrefix("0000000000"))
    #expect(buffer[Point(x: 0, y: 3)].style.background == .named(.white), "thumb at the left")
    #expect(buffer[Point(x: 5, y: 3)].style.background == .named(.brightBlack), "track past the thumb")

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

    let buffer = SceneRenderer(root: window).render(size: window.frame.size)
    #expect(buffer[Point(x: 9, y: 0)].style.background == .standard, "no overflow, no indicator")

    _ = scroll.keyDown(KeyInput(key: .down))
    #expect(scroll.contentOffset == .zero, "nothing to scroll")
}

@Test @MainActor func monoThemeIndicatorFallsBackToVideoAttributes() {
    let (scroll, window) = makeScroll(
        content: Size(width: 8, height: 40),
        viewport: Size(width: 10, height: 4)
    )
    window.theme = .mono

    let buffer = SceneRenderer(root: window).render(size: window.frame.size)
    #expect(buffer[Point(x: 9, y: 0)].style.flags.contains(.inverse), "colorless themes use attribute blocks")
    #expect(buffer[Point(x: 9, y: 3)].style.flags.contains(.dim))
    _ = scroll
}

@Test @MainActor func scrollViewFitsDocumentWidthScrollsVerticallyOnly() {
    let scroll = ScrollView(document: NumberedDocument(size: Size(width: 30, height: 10)))
    scroll.fitsDocumentWidth = true

    let window = Window(frame: Rect(x: 0, y: 0, width: 12, height: 4))
    scroll.frame = window.bounds
    window.addSubview(scroll)
    window.layoutIfNeeded()

    // The 30-wide document reflows to the viewport (12 minus the bar).
    #expect(scroll.documentView?.frame.size == Size(width: 11, height: 10))

    _ = scroll.keyDown(KeyInput(key: .right))
    #expect(scroll.contentOffset == .zero, "no horizontal scrolling in fitted mode")

    _ = scroll.keyDown(KeyInput(key: .down))
    #expect(scroll.contentOffset == Point(x: 0, y: 1), "vertical scrolling still works")
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

// MARK: - Scrollbar interaction

// Geometry used below: viewport 10x4 → bar column x9, bar length 4;
// content height 40 → 2-cell thumb (rounded, min 2), maxThumbStart 2,
// maxOffset 36.

@Test @MainActor func scrollBarTrackClickPagesTowardClick() {
    let (scroll, _) = makeScroll(
        content: Size(width: 8, height: 40),
        viewport: Size(width: 10, height: 4)
    )

    _ = scroll.mouseEvent(MouseInput(position: Point(x: 9, y: 3), action: .press, button: .left))
    #expect(scroll.contentOffset.y == 3, "click below the thumb pages down")

    scroll.setOffset(Point(x: 0, y: 18))   // thumb now sits at bar cells 1-2
    _ = scroll.mouseEvent(MouseInput(position: Point(x: 9, y: 0), action: .press, button: .left))
    #expect(scroll.contentOffset.y == 15, "click above the thumb pages up")
}

@Test @MainActor func scrollBarThumbDragsProportionally() {
    let (scroll, _) = makeScroll(
        content: Size(width: 8, height: 40),
        viewport: Size(width: 10, height: 4)
    )

    _ = scroll.mouseEvent(MouseInput(position: Point(x: 9, y: 0), action: .press, button: .left))
    #expect(scroll.contentOffset.y == 0, "grabbing the thumb does not scroll")

    _ = scroll.mouseEvent(MouseInput(position: Point(x: 9, y: 1), action: .drag, button: .left))
    #expect(scroll.contentOffset.y == 18, "thumb start 1 of 2 maps to offset 18 of 36")

    _ = scroll.mouseEvent(MouseInput(position: Point(x: 9, y: 9), action: .drag, button: .left))
    #expect(scroll.contentOffset.y == 36, "dragging past the end clamps to the bottom")

    _ = scroll.mouseEvent(MouseInput(position: Point(x: 9, y: 9), action: .release, button: .left))
    _ = scroll.mouseEvent(MouseInput(position: Point(x: 9, y: 0), action: .drag, button: .left))
    #expect(scroll.contentOffset.y == 36, "after release the drag is over")
}

@Test @MainActor func windowCapturesTheDragForTheGrabbedThumb() {
    let (scroll, window) = makeScroll(
        content: Size(width: 8, height: 40),
        viewport: Size(width: 10, height: 4)
    )

    window.route(.mouse(MouseInput(position: Point(x: 9, y: 0), action: .press, button: .left)))
    window.route(.mouse(MouseInput(position: Point(x: 3, y: 1), action: .drag, button: .left)))
    #expect(scroll.contentOffset.y == 18, "the drag stays captured even off the bar column")

    window.route(.mouse(MouseInput(position: Point(x: 3, y: 1), action: .release, button: .left)))
    window.route(.mouse(MouseInput(position: Point(x: 9, y: 0), action: .drag, button: .left)))
    #expect(scroll.contentOffset.y == 18, "release ends the capture")
}

@Test @MainActor func buttonReleaseOutsideCancelsThroughCapture() {
    var activated = false
    let button = Button("OK") { activated = true }
    button.frame = Rect(x: 0, y: 0, width: 8, height: 1)

    let window = Window(frame: Rect(x: 0, y: 0, width: 20, height: 5))
    window.addSubview(button)

    window.route(.mouse(MouseInput(position: Point(x: 1, y: 0), action: .press, button: .left)))
    #expect(button.isPressed)

    window.route(.mouse(MouseInput(position: Point(x: 15, y: 3), action: .release, button: .left)))
    #expect(!activated, "a release outside the button cancels the press")
    #expect(!button.isPressed)
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
