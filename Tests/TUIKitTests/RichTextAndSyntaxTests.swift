import Testing
@testable import TUIKit   // re-exports RichSwift

@MainActor
private func renderedBuffer(_ view: TUIKit.View, size: TUIKit.Size) -> CellBuffer {
    let window = Window(frame: Rect(origin: .zero, size: size))
    view.frame = Rect(origin: .zero, size: size)
    window.addSubview(view)
    return SceneRenderer(root: window).render(size: size)
}

// MARK: - SGR decoding

@Test @MainActor func sgrDecoderRoundTripsRichSwiftMarkup() {
    let ansi = Markup.render("[bold magenta]hi[/] there\nplain", colorEnabled: true)
    let lines = SGRDecoder.lines(from: ansi)

    #expect(lines.count == 2)
    #expect(lines[0].count == 2)
    #expect(lines[0][0].text == "hi")
    #expect(lines[0][0].style.flags.contains(.bold))
    #expect(lines[0][0].style.foreground == .named(.magenta))
    #expect(lines[0][1].text == " there")
    #expect(lines[0][1].style == CellStyle())
    #expect(lines[1][0].text == "plain")
}

@Test @MainActor func sgrDecoderHandlesExtendedColors() {
    let ansi = Markup.render("[#102030]x[/][color(42)]y[/]", colorEnabled: true)
    let runs = SGRDecoder.lines(from: ansi)[0]

    #expect(runs[0].style.foreground == .rgb(red: 0x10, green: 0x20, blue: 0x30))
    #expect(runs[1].style.foreground == .palette(42))
}

// MARK: - RichText

@Test @MainActor func richTextMapsMarkupOntoCells() {
    let view = RichText(markup: "[bold red]Err[/] ok\nnext")

    #expect(view.intrinsicContentSize == TUIKit.Size(width: 6, height: 2))

    let buffer = renderedBuffer(view, size: TUIKit.Size(width: 8, height: 2))
    #expect(buffer.textLines()[0].hasPrefix("Err ok"))
    #expect(buffer.textLines()[1].hasPrefix("next"))

    let error = buffer[TUIKit.Point(x: 0, y: 0)].style
    #expect(error.flags.contains(.bold))
    #expect(error.foreground == .named(.red))

    let plain = buffer[TUIKit.Point(x: 4, y: 0)].style
    #expect(plain == CellStyle())
}

@Test @MainActor func richTextRendersRenderablesThroughSGR() {
    let view = RichText(renderable: Syntax("let x = 42", language: "swift"))
    let buffer = renderedBuffer(view, size: TUIKit.Size(width: 16, height: 1))

    #expect(buffer.textLines()[0].hasPrefix("let x = 42"))

    // "let" is a keyword (bold magenta); "42" is a number (cyan).
    let keyword = buffer[TUIKit.Point(x: 0, y: 0)].style
    #expect(keyword.flags.contains(.bold))
    #expect(keyword.foreground == .named(.magenta))

    let number = buffer[TUIKit.Point(x: 8, y: 0)].style
    #expect(number.foreground == .named(.cyan))
}

// MARK: - MarkdownView

@Test @MainActor func markdownWrapBreaksAtWordBoundaries() {
    let plain = CellStyle()
    let wrapped = MarkdownView.wrap([StyledRun(text: "alpha beta gamma", style: plain)], width: 10)

    #expect(wrapped.map { $0.map(\.text).joined() } == ["alpha beta", "gamma"])

    let hard = MarkdownView.wrap([StyledRun(text: "abcdefghij", style: plain)], width: 4)
    #expect(hard.map { $0.map(\.text).joined() } == ["abcd", "efgh", "ij"])

    // Styles survive the wrap: bold word split from its plain neighbor.
    let styled = MarkdownView.wrap(
        [
            StyledRun(text: "one ", style: plain),
            StyledRun(text: "two", style: CellStyle(flags: .bold)),
        ],
        width: 5
    )
    #expect(styled.count == 2)
    #expect(styled[1] == [StyledRun(text: "two", style: CellStyle(flags: .bold))])
}

@Test @MainActor func markdownViewRendersHeadingsListsAndInlineStyles() {
    let view = MarkdownView(markdown: "# Title\n- item one\nplain **bold** end")
    let buffer = renderedBuffer(view, size: TUIKit.Size(width: 30, height: 4))
    let lines = buffer.textLines()

    #expect(lines[0].hasPrefix("Title"))
    #expect(lines[1].hasPrefix("• item one"))
    #expect(lines[2].hasPrefix("plain bold end"))

    let heading = buffer[TUIKit.Point(x: 0, y: 0)].style
    #expect(heading.flags.contains(.bold))
    #expect(heading.foreground == .named(.cyan))

    let bold = buffer[TUIKit.Point(x: 6, y: 2)].style
    #expect(bold.flags.contains(.bold))
}

@Test @MainActor func markdownViewScrollsAndShowsIndicator() {
    let source = (1...20).map { "- line \($0)" }.joined(separator: "\n")
    let view = MarkdownView(markdown: source)
    view.frame = Rect(x: 0, y: 0, width: 20, height: 4)

    let beforeBuffer = renderedBuffer(view, size: TUIKit.Size(width: 20, height: 4))
    let before = beforeBuffer.textLines()
    #expect(before[0].hasPrefix("• line 1"))
    #expect(
        beforeBuffer[TUIKit.Point(x: 19, y: 0)].style.background == .named(.white),
        "overflowing documents show the solid indicator thumb"
    )

    _ = view.keyDown(KeyInput(key: .end))
    #expect(view.scrollOffset == 16)

    _ = view.keyDown(KeyInput(key: .down))
    #expect(view.scrollOffset == 16, "clamped at the bottom")

    let after = renderedBuffer(view, size: TUIKit.Size(width: 20, height: 4)).textLines()
    #expect(after[3].hasPrefix("• line 20"))

    _ = view.keyDown(KeyInput(key: .home))
    #expect(view.scrollOffset == 0)
}

// MARK: - SyntaxTextView

@Test @MainActor func syntaxEditorTypesSplitsAndJoins() {
    let editor = SyntaxTextView(text: "", language: "swift")
    editor.frame = Rect(x: 0, y: 0, width: 20, height: 5)

    var changes = 0
    editor.onChanged = { _ in changes += 1 }

    for character in "let x" {
        _ = editor.keyDown(KeyInput(key: .character(character)))
    }

    #expect(editor.text == "let x")

    _ = editor.keyDown(KeyInput(key: .enter))
    for character in "y" {
        _ = editor.keyDown(KeyInput(key: .character(character)))
    }

    #expect(editor.text == "let x\ny")
    #expect(editor.lineCount == 2)

    // Backspace at column 0 joins the lines back together.
    _ = editor.keyDown(KeyInput(key: .left))
    _ = editor.keyDown(KeyInput(key: .backspace))
    #expect(editor.text == "let xy")
    #expect(editor.cursorPosition == TUIKit.Point(x: 5, y: 0))

    #expect(changes == 8, "five inserts, return, one insert, and the join each fire")
}

@Test @MainActor func syntaxEditorNavigationWrapsAcrossLines() {
    let editor = SyntaxTextView(text: "ab\ncdef", language: "swift")
    editor.frame = Rect(x: 0, y: 0, width: 20, height: 5)

    _ = editor.keyDown(KeyInput(key: .end))
    #expect(editor.cursorPosition == TUIKit.Point(x: 2, y: 0))

    _ = editor.keyDown(KeyInput(key: .right))
    #expect(editor.cursorPosition == TUIKit.Point(x: 0, y: 1), "right at line end wraps down")

    _ = editor.keyDown(KeyInput(key: .left))
    #expect(editor.cursorPosition == TUIKit.Point(x: 2, y: 0), "left at line start wraps up")

    _ = editor.keyDown(KeyInput(key: .down))
    _ = editor.keyDown(KeyInput(key: .end))
    #expect(editor.cursorPosition == TUIKit.Point(x: 4, y: 1))

    _ = editor.keyDown(KeyInput(key: .up))
    #expect(editor.cursorPosition == TUIKit.Point(x: 2, y: 0), "column clamps to the shorter line")
}

@Test @MainActor func syntaxEditorRendersGutterAndHighlights() {
    let editor = SyntaxTextView(text: "let x = 1\nprint(x)", language: "swift")
    let buffer = renderedBuffer(editor, size: TUIKit.Size(width: 16, height: 3))
    let lines = buffer.textLines()

    #expect(lines[0].hasPrefix("1 │let x = 1"))
    #expect(lines[1].hasPrefix("2 │print(x)"))

    // Keyword cell just after the 3-cell gutter.
    let keyword = buffer[TUIKit.Point(x: 3, y: 0)].style
    #expect(keyword.flags.contains(.bold))
    #expect(keyword.foreground == .named(.magenta))
}

@Test @MainActor func syntaxEditorScrollsToFollowTheCursor() {
    let text = (1...10).map { "line \($0)" }.joined(separator: "\n")
    let editor = SyntaxTextView(text: text, language: "swift")
    editor.frame = Rect(x: 0, y: 0, width: 14, height: 3)

    for _ in 0..<5 {
        _ = editor.keyDown(KeyInput(key: .pageDown))
    }

    #expect(editor.cursorPosition.y == 9, "page-down clamps at the last line")

    let lines = renderedBuffer(editor, size: TUIKit.Size(width: 14, height: 3)).textLines()
    #expect(lines[0].hasPrefix(" 8 │"), "viewport scrolled so line 10 is visible")
    #expect(lines[2].hasPrefix("10 │"))
}

@Test @MainActor func syntaxEditorClickAndTab() {
    let editor = SyntaxTextView(text: "abc\ndefgh", language: "swift")
    editor.frame = Rect(x: 0, y: 0, width: 20, height: 5)

    // Gutter is 3 wide; click content column 2 of line 1.
    _ = editor.mouseEvent(MouseInput(position: TUIKit.Point(x: 5, y: 1), action: .press, button: .left))
    #expect(editor.cursorPosition == TUIKit.Point(x: 2, y: 1))

    _ = editor.keyDown(KeyInput(key: .tab))
    #expect(editor.text == "abc\nde    fgh", "tab inserts spaces at the cursor")
    #expect(editor.cursorPosition == TUIKit.Point(x: 6, y: 1))
}
