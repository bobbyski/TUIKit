import Testing
@testable import TUIKit

// Renders a single control inside a window and returns the text projection.
@MainActor
private func renderedLines(_ view: TUIView, size: Size, focused: Bool = false) -> [String] {
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

    // Default: tinted — color carries the affordance, no brackets.
    #expect(button.intrinsicContentSize == Size(width: 4, height: 1))
    #expect(renderedLines(button, size: Size(width: 4, height: 1)) == [" OK "])

    // Bordered keeps the classic bracketed look.
    button.style = .bordered
    #expect(button.intrinsicContentSize == Size(width: 6, height: 1))
    #expect(renderedLines(button, size: Size(width: 6, height: 1)) == ["[ OK ]"])
}

@Test @MainActor func ordinaryButtonsRestOnTheThemeButtonSlot() {
    func cell(_ theme: Theme, context: ThemeContext?) -> CellStyle {
        let button = Button("Reset")   // no mnemonic, so no accelerator overlay
        let window = Window(frame: Rect(x: 0, y: 0, width: 8, height: 1))
        window.theme = theme
        window.themeContext = context
        button.frame = window.bounds
        window.addSubview(button)
        // Column 1 is the 'R' inside " Reset ".
        return SceneRenderer(root: window).render(size: Size(width: 8, height: 1))[Point(x: 1, y: 0)].style
    }

    // Turbo gives ordinary buttons a distinct dark-gray pill with white text,
    // so Reset reads as a button, not a low-contrast label.
    let turbo = cell(.turbo, context: .secondaryWindows)
    #expect(turbo.foreground == .rgb(red: 255, green: 255, blue: 255))
    #expect(turbo.background == .rgb(red: 85, green: 85, blue: 85))

    // Surface themes keep the minimal look: accent text on the window's own
    // background (an invisible pill), unchanged from before.
    let ocean = cell(.ocean, context: nil)
    #expect(ocean.foreground == .rgb(red: 126, green: 190, blue: 255))
    #expect(ocean.background == .rgb(red: 34, green: 79, blue: 188), "fill is the window surface")
}

@Test @MainActor func defaultAndDestructiveButtonsFillFromTheirThemeSlots() {
    func fill(_ role: Button.Role) -> CellStyle {
        let button = Button("OK")
        button.role = role
        let window = Window(frame: Rect(x: 0, y: 0, width: 4, height: 1))
        window.theme = .turbo
        button.frame = window.bounds
        window.addSubview(button)
        // Column 1 is inside the " OK " pill, past the leading pad.
        return SceneRenderer(root: window).render(size: Size(width: 4, height: 1))[Point(x: 1, y: 0)].style
    }

    // Turbo: default is a solid green pill, destructive a solid red one.
    let def = fill(.default)
    #expect(def.background == .rgb(red: 0, green: 170, blue: 0))
    #expect(def.foreground == .rgb(red: 255, green: 255, blue: 255))

    let bad = fill(.destructive)
    #expect(bad.background == .rgb(red: 170, green: 0, blue: 0))
    #expect(bad.foreground == .rgb(red: 255, green: 255, blue: 255))
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

@Test @MainActor func textFieldWellUsesTheThemeFieldSlot() {
    // Standard: underline marks the well, no color.
    let plain = TextField(text: "hi")
    let w1 = Window(frame: Rect(x: 0, y: 0, width: 6, height: 1))
    plain.frame = w1.bounds
    w1.addSubview(plain)
    let a = SceneRenderer(root: w1).render(size: Size(width: 6, height: 1))[Point(x: 0, y: 0)].style
    #expect(a.flags.contains(.underline))

    // Turbo: a solid blue well with yellow text, no underline.
    let turbo = TextField(text: "hi")
    let w2 = Window(frame: Rect(x: 0, y: 0, width: 6, height: 1))
    w2.theme = .turbo
    turbo.frame = w2.bounds
    w2.addSubview(turbo)
    let b = SceneRenderer(root: w2).render(size: Size(width: 6, height: 1))[Point(x: 0, y: 0)].style
    #expect(b.background == .rgb(red: 0, green: 0, blue: 170), "blue field well")
    #expect(b.foreground == .rgb(red: 255, green: 255, blue: 85), "yellow field text")
    #expect(!b.flags.contains(.underline), "the color is the cue in Turbo, not an underline")
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
