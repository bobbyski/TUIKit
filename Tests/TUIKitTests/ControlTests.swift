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

@Test @MainActor func turboButtonsCastADropShadowAndPressOntoIt() {
    let black = TerminalColor.rgb(red: 0, green: 0, blue: 0)
    let green = TerminalColor.rgb(red: 0, green: 170, blue: 0)

    let button = Button("OK")
    button.role = .default
    let window = Window(frame: Rect(x: 0, y: 0, width: 8, height: 3))
    window.theme = .turbo
    window.addSubview(button)

    // Under Turbo the intrinsic grows one column and one row for the shadow.
    #expect(button.intrinsicContentSize == Size(width: 5, height: 2))
    button.frame = Rect(x: 0, y: 0, width: 5, height: 2)

    let renderer = SceneRenderer(root: window)
    var buffer = renderer.render(size: Size(width: 8, height: 3))

    // At rest: the face on row 0, the shadow below it shifted one right —
    // below only, never on the face's own row (the Borland look).
    #expect(buffer[Point(x: 1, y: 0)].style.background == green, "face")
    #expect(buffer[Point(x: 4, y: 0)].style.background != black, "no shadow beside the face")
    #expect(buffer[Point(x: 2, y: 1)].style.background == black, "shadow under the face")
    #expect(buffer[Point(x: 4, y: 1)].style.background == black, "shadow overhangs one right")
    #expect(buffer[Point(x: 0, y: 1)].style.background != black, "shadow is shifted, not a full row")

    // Pressing animates the face ONTO the shadow position; the shadow hides
    // and the face keeps its color (the motion is the cue, no inverse).
    _ = button.mouseEvent(MouseInput(position: Point(x: 1, y: 0), action: .press, button: .left))
    buffer = renderer.render(size: Size(width: 8, height: 3))
    #expect(buffer[Point(x: 2, y: 1)].style.background == green, "face pressed down onto the shadow")
    #expect(buffer[Point(x: 1, y: 0)].style.background != green, "old face position vacated")

    // Release pops it back.
    _ = button.mouseEvent(MouseInput(position: Point(x: 1, y: 0), action: .release, button: .left))
    buffer = renderer.render(size: Size(width: 8, height: 3))
    #expect(buffer[Point(x: 1, y: 0)].style.background == green)
    #expect(buffer[Point(x: 2, y: 1)].style.background == black)

    // Themes without a shadow color are untouched: flat one-row buttons.
    window.theme = .ocean
    #expect(button.intrinsicContentSize == Size(width: 4, height: 1), "no shadow slot → no extra cells")
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

// MARK: - The escalating double-click in a text field

@MainActor
private func doubleClickField(_ field: TextField, atColumn column: Int) {
    _ = field.mouseEvent(MouseInput(position: Point(x: column, y: 0), action: .press, button: .left))
    _ = field.mouseEvent(MouseInput(position: Point(x: column, y: 0), action: .click, button: .left, clickCount: 2))
}

@Test @MainActor func aFieldsDoubleClickWalksWordThenEverythingThenNothing() {
    let field = TextField(text: "alpha beta gamma")
    field.frame = Rect(x: 0, y: 0, width: 20, height: 1)

    doubleClickField(field, atColumn: 7)
    #expect(field.selectedText == "beta")

    // A one-line field's line IS everything, so the ladder is one rung
    // shorter than an editor's rather than looping.
    doubleClickField(field, atColumn: 7)
    #expect(field.selectedText == "alpha beta gamma")

    doubleClickField(field, atColumn: 7)
    #expect(field.selectedText == nil)
}

@Test @MainActor func aFieldsSelectionIsWhatCopyTakesAndTypingReplaces() {
    let pasteboard = Pasteboard()
    let field = TextField(text: "alpha beta")
    field.frame = Rect(x: 0, y: 0, width: 20, height: 1)
    field.pasteboard = pasteboard

    doubleClickField(field, atColumn: 0)
    #expect(field.selectedText == "alpha")

    field.clipboardCopy()
    #expect(pasteboard.string == "alpha", "the selection, not the whole field")

    _ = field.keyDown(KeyInput(key: .character("X")))
    #expect(field.text == "X beta", "typing replaces the selection")
    #expect(field.selectedText == nil)

    // And with only a caret, copy still means the whole one-line box.
    field.clipboardCopy()
    #expect(pasteboard.string == "X beta")
}

@Test @MainActor func aFieldsCutTakesTheSelectionWhenThereIsOne() {
    let pasteboard = Pasteboard()
    let field = TextField(text: "alpha beta")
    field.frame = Rect(x: 0, y: 0, width: 20, height: 1)
    field.pasteboard = pasteboard

    doubleClickField(field, atColumn: 6)
    field.clipboardCut()

    #expect(pasteboard.string == "beta")
    #expect(field.text == "alpha ")

    // Nothing selected: cut still empties the box, as it always did.
    field.clipboardCut()
    #expect(field.text.isEmpty)
}

@Test @MainActor func movingTheCaretDropsAFieldsSelection() {
    let field = TextField(text: "alpha beta")
    field.frame = Rect(x: 0, y: 0, width: 20, height: 1)

    doubleClickField(field, atColumn: 0)
    #expect(field.selectedText == "alpha")

    _ = field.keyDown(KeyInput(key: .right))
    #expect(field.selectedText == nil, "an arrow key is a new place, not a wider one")
}

@Test @MainActor func aFieldsSelectionDraws() {
    let field = TextField(text: "alpha beta")
    field.frame = Rect(x: 0, y: 0, width: 20, height: 1)
    doubleClickField(field, atColumn: 0)

    let buffer = SceneRenderer(root: field).render(size: Size(width: 20, height: 1))
    let selected = (0..<5).map { buffer[Point(x: $0, y: 0)].style }
    let unselected = buffer[Point(x: 7, y: 0)].style

    #expect(selected.allSatisfy { $0 != unselected }, "a selection you cannot see is not a selection")
}

@Test func aBorderStyleWillTellYouItsGlyphs() {
    // Public so a control outside this package can draw a frame that MATCHES
    // a themed one; restating the table is a second copy that goes stale the
    // first time a style is added.
    #expect(BorderStyle.double.characters?.topLeft == "╔")
    #expect(BorderStyle.rounded.characters?.topLeft == "╭")
    #expect(BorderStyle.heavy.characters?.vertical == "┃")
    #expect(BorderStyle.none.characters == nil)

    #expect(BorderStyle.single.junctions?.cross == "┼")
    #expect(BorderStyle.rounded.junctions?.cross == "┼", "rounded borders use the single-line tees")
    #expect(BorderStyle.double.junctions?.teeLeft == "╠")
    #expect(BorderStyle.none.junctions == nil)
}

@Test @MainActor func theMultiClickWindowIsLongerThanADesktopsAndSettable() {
    let app = App(driver: HeadlessDriver(size: Size(width: 20, height: 5)))

    // 420 ms rather than the 280 ms desktop convention: a window manager sees
    // the second press when it happens, while here it travels as bytes
    // through a tty, and the slack in that path turned real double-clicks
    // into two singles.
    #expect(app.multiClickIntervalMilliseconds == 420)
    #expect(app.multiClickInterval == .milliseconds(420))

    app.multiClickIntervalMilliseconds = 600
    #expect(app.multiClickInterval == .milliseconds(600))
    #expect(app.multiClickIntervalMilliseconds == 600)

    // A host that thinks in Durations and one that thinks in milliseconds
    // read the same value.
    app.multiClickInterval = .milliseconds(250)
    #expect(app.multiClickIntervalMilliseconds == 250)

    app.multiClickIntervalMilliseconds = -1
    #expect(app.multiClickIntervalMilliseconds == 0, "a negative window is no window")
}

// MARK: - Vertical sliders

@MainActor
private func sliderRows(_ slider: Slider, width: Int, height: Int) -> [String] {
    slider.frame = Rect(x: 0, y: 0, width: width, height: height)
    let buffer = SceneRenderer(root: slider).render(size: Size(width: width, height: height))

    return (0..<height).map { row in
        String((0..<width).map { buffer[Point(x: $0, y: row)].character })
    }
}

@Test @MainActor func aVerticalSliderRunsLowAtTheBottom() {
    // It is a fader: up is more. A vertical control that grew downwards would
    // be the only one in the world.
    let slider = Slider(value: 0, in: 0...100, orientation: .vertical)
    let low = sliderRows(slider, width: 1, height: 7)

    #expect(low.last == "┴", "the track's caps are the theme's own junctions")
    #expect(low.first == "┬")
    #expect(low[5] == "█", "value 0 sits at the bottom")

    slider.setValue(100)
    let high = sliderRows(slider, width: 1, height: 7)
    #expect(high[1] == "█", "and 100 at the top")
}

@Test @MainActor func aVerticalSliderTakesUpAndDown() {
    let slider = Slider(value: 50, in: 0...100, step: 10, orientation: .vertical)
    slider.frame = Rect(x: 0, y: 0, width: 1, height: 8)

    #expect(slider.keyDown(KeyInput(key: .up)))
    #expect(slider.value == 60, "up is more")

    #expect(slider.keyDown(KeyInput(key: .down)))
    #expect(slider.value == 50)

    // The other axis is not its business — left/right belong to whatever the
    // focus would move to.
    #expect(!slider.keyDown(KeyInput(key: .left)))
    #expect(!slider.keyDown(KeyInput(key: .right)))

    // Home and End mean the bounds either way round.
    #expect(slider.keyDown(KeyInput(key: .end)))
    #expect(slider.value == 100)
}

@Test @MainActor func clickingAVerticalTrackPositionsTheHandleFromTheBottom() {
    let slider = Slider(value: 0, in: 0...100, orientation: .vertical)
    slider.frame = Rect(x: 0, y: 0, width: 1, height: 12)

    var reported: [Int] = []
    slider.onValueChanged = { reported.append($0) }

    _ = slider.mouseEvent(MouseInput(position: Point(x: 0, y: 1), action: .press, button: .left))
    #expect(slider.value == 100, "a click near the top is a high value")

    _ = slider.mouseEvent(MouseInput(position: Point(x: 0, y: 10), action: .drag, button: .left))
    #expect(slider.value == 0, "and near the bottom, a low one")
    #expect(reported == [100, 0])
}

@Test @MainActor func aSliderKeepsItsHorizontalBehaviour() {
    let slider = Slider(value: 40, in: 0...100, step: 5)
    let rows = sliderRows(slider, width: 12, height: 1)

    #expect(rows[0].hasPrefix("├"))
    #expect(rows[0].hasSuffix("┤"))
    #expect(rows[0].contains("█"))

    #expect(slider.keyDown(KeyInput(key: .right)))
    #expect(slider.value == 45)
    #expect(!slider.keyDown(KeyInput(key: .up)), "up is not the axis of a horizontal slider")

    #expect(slider.intrinsicContentSize == Size(width: 16, height: 1))
    #expect(Slider(orientation: .vertical).intrinsicContentSize == Size(width: 1, height: 8))
}
