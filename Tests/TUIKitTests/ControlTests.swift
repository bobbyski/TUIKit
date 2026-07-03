import Testing
@testable import TUIKit

// Renders a single control inside a window and returns the text projection.
@MainActor
private func renderedLines(_ view: View, size: Size, focused: Bool = false) -> [String] {
    let window = Window(frame: Rect(origin: .zero, size: size))
    view.frame = Rect(origin: .zero, size: size)
    window.addSubview(view)

    if focused {
        window.makeFirstResponder(view)
    }

    return SceneRenderer(root: window).render(size: size).textLines()
}

private func press(_ character: Character) -> KeyInput {
    KeyInput(key: .character(character))
}

// MARK: - Label

@Test @MainActor func labelRendersAlignedText() {
    #expect(renderedLines(Label("hi"), size: Size(width: 6, height: 1)) == ["hi    "])

    let centered = Label("hi", alignment: .center)
    #expect(renderedLines(centered, size: Size(width: 6, height: 1)) == ["  hi  "])

    let trailing = Label("hi", alignment: .trailing)
    #expect(renderedLines(trailing, size: Size(width: 6, height: 1)) == ["    hi"])
}

@Test @MainActor func labelTruncatesWithEllipsis() {
    let label = Label("hello world")

    #expect(renderedLines(label, size: Size(width: 7, height: 1)) == ["hello …"])
    #expect(label.intrinsicContentSize == Size(width: 11, height: 1))
}

// MARK: - Button

@Test @MainActor func buttonRendersTitleAndReportsSize() {
    let button = Button("OK")

    #expect(renderedLines(button, size: Size(width: 6, height: 1)) == ["[ OK ]"])
    #expect(button.intrinsicContentSize == Size(width: 6, height: 1))
}

@Test @MainActor func buttonActivatesOnEnterSpaceAndClickRelease() {
    var activations = 0
    let button = Button("Go") { activations += 1 }
    button.frame = Rect(x: 0, y: 0, width: 6, height: 1)

    #expect(button.keyDown(KeyInput(key: .enter)))
    #expect(button.keyDown(press(" ")))
    #expect(activations == 2)

    // Press-then-release inside activates once.
    #expect(button.mouseEvent(MouseInput(position: .zero, action: .press, button: .left)))
    #expect(button.isPressed)
    #expect(button.mouseEvent(MouseInput(position: .zero, action: .release, button: .left)))
    #expect(activations == 3)

    // Press then release outside cancels.
    _ = button.mouseEvent(MouseInput(position: .zero, action: .press, button: .left))
    _ = button.mouseEvent(MouseInput(position: Point(x: 40, y: 0), action: .release, button: .left))
    #expect(activations == 3)
}

@Test @MainActor func buttonDeclinesModifiedKeys() {
    let button = Button("Go")

    #expect(!button.keyDown(KeyInput(key: .enter, modifiers: .control)))
}

// MARK: - TextField

@Test @MainActor func textFieldTypesEditsAndSubmits() {
    let field = TextField()
    field.frame = Rect(x: 0, y: 0, width: 10, height: 1)

    var changes: [String] = []
    var submitted: String?
    field.onChanged = { changes.append($0) }
    field.onSubmit = { submitted = $0 }

    _ = field.keyDown(press("h"))
    _ = field.keyDown(press("i"))
    _ = field.keyDown(press("!"))
    #expect(field.text == "hi!")

    _ = field.keyDown(KeyInput(key: .backspace))
    #expect(field.text == "hi")

    // Insert in the middle: left, then type.
    _ = field.keyDown(KeyInput(key: .left))
    _ = field.keyDown(press("e"))
    #expect(field.text == "hei")

    // Home + forward delete removes the first character.
    _ = field.keyDown(KeyInput(key: .home))
    _ = field.keyDown(KeyInput(key: .delete))
    #expect(field.text == "ei")

    _ = field.keyDown(KeyInput(key: .enter))
    #expect(submitted == "ei")
    #expect(changes.count == 6, "every edit reported")
}

@Test @MainActor func textFieldShowsPlaceholderUntilFocused() {
    let field = TextField(placeholder: "name")

    #expect(renderedLines(field, size: Size(width: 6, height: 1)) == ["name  "])

    let focusedLines = renderedLines(field, size: Size(width: 6, height: 1), focused: true)
    #expect(focusedLines == ["      "], "focused empty field shows no placeholder")
}

@Test @MainActor func textFieldScrollsLongText() {
    let field = TextField(text: "abcdefghij")
    field.frame = Rect(x: 0, y: 0, width: 5, height: 1)

    // Cursor is at the end; the visible window shows the tail.
    let lines = renderedLines(field, size: Size(width: 5, height: 1), focused: true)
    #expect(lines == ["ghij "], "scrolled to keep the end-of-text cursor visible")
}

@Test @MainActor func textFieldClickPlacesCursor() {
    let field = TextField(text: "abcdef")
    field.frame = Rect(x: 0, y: 0, width: 10, height: 1)

    _ = field.mouseEvent(MouseInput(position: Point(x: 2, y: 0), action: .press, button: .left))
    _ = field.keyDown(press("X"))

    #expect(field.text == "abXcdef")
}

// MARK: - Checkbox

@Test @MainActor func checkboxTogglesAndReports() {
    let box = Checkbox("Wrap")
    var events: [Bool] = []
    box.onChange = { events.append($0) }

    _ = box.keyDown(press(" "))
    #expect(box.isChecked)

    _ = box.mouseEvent(MouseInput(position: .zero, action: .press, button: .left))
    #expect(!box.isChecked)
    #expect(events == [true, false])

    box.setChecked(true)
    #expect(box.isChecked)
    #expect(events == [true, false], "programmatic set is silent by default")
}

@Test @MainActor func checkboxRendersState() {
    let box = Checkbox("Wrap", isChecked: true)

    #expect(renderedLines(box, size: Size(width: 8, height: 1)) == ["[x] Wrap"])

    box.setChecked(false)
    #expect(renderedLines(box, size: Size(width: 8, height: 1)) == ["[ ] Wrap"])
}

// MARK: - RadioGroup

@Test @MainActor func radioGroupSelectsWithArrowsAndClicks() {
    let group = RadioGroup(["One", "Two", "Three"])
    group.frame = Rect(x: 0, y: 0, width: 10, height: 3)

    var events: [Int] = []
    group.onSelectionChanged = { events.append($0) }

    _ = group.keyDown(KeyInput(key: .down))
    #expect(group.selectedIndex == 0)

    _ = group.keyDown(KeyInput(key: .down))
    #expect(group.selectedIndex == 1)

    _ = group.keyDown(KeyInput(key: .up))
    #expect(group.selectedIndex == 0)

    _ = group.mouseEvent(MouseInput(position: Point(x: 1, y: 2), action: .press, button: .left))
    #expect(group.selectedIndex == 2)
    #expect(events == [0, 1, 0, 2])
}

@Test @MainActor func radioGroupRendersSelection() {
    let group = RadioGroup(["A", "B"], selectedIndex: 1)

    #expect(renderedLines(group, size: Size(width: 5, height: 2)) == [
        "( ) A",
        "(•) B",
    ])
}

@Test @MainActor func radioGroupReportsIntrinsicSize() {
    let group = RadioGroup(["Fast", "Balanced"])

    #expect(group.intrinsicContentSize == Size(width: 12, height: 2))
}
