import Testing
@testable import TUIKit

// R8 — the HTML/JavaScript/CSS lexers and the SyntaxHighlighting seam.
// Lexers are tested as pure functions (line in, spans out, state through);
// the view integration is tested by rendering a SyntaxTextView.

// Convenience: kinds by character position for one line.
private func kinds(
    _ line: String,
    _ highlighter: any SyntaxHighlighting,
    state: inout HighlightState
) -> [HighlightKind] {
    var result = [HighlightKind](repeating: .plain, count: line.count)

    for span in highlighter.highlight(line: line, state: &state) {
        for offset in span.start..<min(span.start + span.length, line.count) {
            result[offset] = span.kind
        }
    }

    return result
}

private func kind(at index: Int, of line: String, _ highlighter: any SyntaxHighlighting) -> HighlightKind {
    var state = HighlightState.initial
    return kinds(line, highlighter, state: &state)[index]
}

// MARK: - JavaScript (R8a)

@Test func javaScriptLexesKeywordsStringsNumbersAndComments() {
    let js = JavaScriptHighlighter()
    let line = #"return count + 42; // done"#
    var state = HighlightState.initial
    let byPosition = kinds(line, js, state: &state)

    #expect(byPosition[0] == .keyword, "return")
    #expect(byPosition[7] == .plain, "count is an identifier")
    #expect(byPosition[15] == .number, "42")
    #expect(byPosition[19] == .comment, "// done")
    #expect(state == .initial, "nothing crosses the line")
}

@Test func javaScriptTellsRegexFromDivision() {
    let js = JavaScriptHighlighter()

    // After `(` a slash starts a pattern…
    #expect(kind(at: 6, of: "match(/ab+c/g)", js) == .regex)

    // …after a value it is division.
    #expect(kind(at: 8, of: "let x = a / b / c", js) == .plain)

    // `return` puts the lexer back at expression position.
    #expect(kind(at: 7, of: "return /re/;", js) == .regex)

    // A character class hides the closing slash.
    var state = HighlightState.initial
    let byPosition = kinds("x = /a[/]b/;", js, state: &state)
    #expect(byPosition[4] == .regex && byPosition[10] == .regex, "the [/] does not end the pattern")
    #expect(byPosition[11] == .plain, "the ; is past it")
}

@Test func javaScriptBlockCommentsAndTemplatesCrossLines() {
    let js = JavaScriptHighlighter()
    var state = HighlightState.initial

    // A comment opened here…
    _ = js.highlight(line: "let a = 1; /* begins", state: &state)
    #expect(state != .initial, "the open comment carries")

    // …colours the whole next line until it closes.
    let second = kinds("still comment */ let b = 2;", js, state: &state)
    #expect(second[0] == .comment)
    #expect(second[15] == .comment, "up through the */")
    #expect(second[17] == .keyword, "let resumes after it")
    #expect(state == .initial)

    // Template literal with an interpolated expression.
    var template = HighlightState.initial
    let line = "`total ${n + 1} items`"
    let byPosition = kinds(line, js, state: &template)
    #expect(byPosition[1] == .string, "template text")
    #expect(byPosition[11] == .plain, "the ${…} interior is code")
    #expect(byPosition[16] == .string, "text resumes after the }")
    #expect(template == .initial, "the backtick closed")

    // An unterminated template carries to the next line.
    var open = HighlightState.initial
    _ = js.highlight(line: "const s = `line one", state: &open)
    let continued = kinds("line two`", js, state: &open)
    #expect(continued[0] == .string)
    #expect(open == .initial)
}

@Test func javaScriptStringsInBothQuoteFormsWithEscapes() {
    let js = JavaScriptHighlighter()
    let byPosition = kind(at: 10, of: #"x = "say \"hi\"" + 'ok'"#, js)
    #expect(byPosition == .string, "escaped quotes stay inside the string")
    #expect(kind(at: 20, of: #"x = "say \"hi\"" + 'ok'"#, js) == .string)
}

// MARK: - HTML (R8a)

@Test func htmlLexesTagsAttributesEntitiesAndDoctype() {
    let html = HTMLHighlighter()
    let line = #"<!doctype html><a href="x.html" id=go>&amp; text</a>"#
    var state = HighlightState.initial
    let byPosition = kinds(line, html, state: &state)

    #expect(byPosition[1] == .doctype)
    #expect(byPosition[15] == .tag, "<a")
    #expect(byPosition[18] == .attributeName, "href")
    #expect(byPosition[24] == .attributeValue, "\"x.html\"")
    #expect(byPosition[35] == .attributeValue, "the unquoted go")
    #expect(byPosition[38] == .entity, "&amp;")
    #expect(byPosition[45] == .plain, "text is text")
    #expect(byPosition[50] == .tag, "</a")
}

@Test func htmlCommentsCrossLines() {
    let html = HTMLHighlighter()
    var state = HighlightState.initial

    _ = html.highlight(line: "<p>before <!-- a comment", state: &state)
    let second = kinds("still --> <b>after</b>", html, state: &state)

    #expect(second[0] == .comment)
    #expect(second[8] == .comment, "through the -->")
    #expect(second[10] == .tag, "<b resumes markup")
}

@Test func htmlHandsScriptAndStyleBodiesToTheirLanguages() {
    let html = HTMLHighlighter()
    var state = HighlightState.initial

    // The opening tag leads into a JavaScript island…
    _ = html.highlight(line: #"<script type="module">"#, state: &state)
    let js = kinds("  return /re/; // note", html, state: &state)

    #expect(js[2] == .keyword, "return, lexed by the JS lexer")
    #expect(js[9] == .regex, "regex literals work inside the island")
    #expect(js[17] == .comment)

    // …and the closing tag hands back to markup, same line.
    let closing = kinds("var x = 1</script><i>", html, state: &state)
    #expect(closing[0] == .keyword, "var — still JS before the closer")
    #expect(closing[9] == .tag, "</script")
    #expect(closing[18] == .tag, "<i — markup again")

    // Style islands go to the CSS lexer, comments carrying across lines.
    var styleState = HighlightState.initial
    _ = html.highlight(line: "<style>", state: &styleState)
    let css = kinds("h1 { color: #fff; } /* open", html, state: &styleState)
    #expect(css[5] == .attributeName, "color is a property name")
    #expect(css[12] == .number, "#fff")
    #expect(css[22] == .comment)

    let cssContinued = kinds("still */ p { margin: 0 }", html, state: &styleState)
    #expect(cssContinued[0] == .comment, "the CSS comment crossed the line inside the island")
}

@Test func htmlSelfClosedScriptHasNoIsland() {
    let html = HTMLHighlighter()
    var state = HighlightState.initial

    _ = html.highlight(line: "<script src=x.js/>", state: &state)
    let after = kinds("plain text <b>", html, state: &state)
    #expect(after[0] == .plain, "no island after a self-closing script tag")
    #expect(after[11] == .tag)
}

@Test func htmlAttributeValueCanSpanLines() {
    let html = HTMLHighlighter()
    var state = HighlightState.initial

    _ = html.highlight(line: #"<div title="first"#, state: &state)
    let second = kinds(#"second">text"#, html, state: &state)
    #expect(second[0] == .attributeValue, "the open quote carried over")
    #expect(second[8] == .plain, "text after the tag closes")
}

// MARK: - The view integration (R8b)

@Test @MainActor func syntaxTextViewUsesTheBuiltInLexersByLanguage() {
    let view = SyntaxTextView(text: "<b>&amp;</b>", language: "html")
    view.showsLineNumbers = false
    view.frame = Rect(x: 0, y: 0, width: 20, height: 3)

    let buffer = SceneRenderer(root: view).render(size: Size(width: 20, height: 3))

    #expect(buffer[Point(x: 0, y: 0)].style == HighlightKind.tag.cellStyle, "the <b is tag-styled")
    #expect(buffer[Point(x: 3, y: 0)].style == HighlightKind.entity.cellStyle, "&amp; is entity-styled")
    #expect(String(buffer.textLines()[0].prefix(12)) == "<b>&amp;</b>", "the cells still spell the source")
}

@Test @MainActor func syntaxTextViewCarriesStateAcrossLinesAndInvalidatesForward() {
    let view = SyntaxTextView(text: "let a = 1;\n/* opens\nstill comment\nlet b = 2;", language: "js")
    view.showsLineNumbers = false
    view.frame = Rect(x: 0, y: 0, width: 20, height: 6)

    let renderer = SceneRenderer(root: view)
    var buffer = renderer.render(size: Size(width: 20, height: 6))

    let comment = HighlightKind.comment.cellStyle
    #expect(buffer[Point(x: 2, y: 2)].style == comment, "line 3 knows line 2 opened a comment")
    #expect(buffer[Point(x: 0, y: 3)].style == comment, "and line 4 is still inside it")

    // Close the comment at its opening line: everything downstream must
    // re-lex without an explicit invalidation from the caller.
    view.setText("let a = 1;\n/* opens */\nstill comment\nlet b = 2;")
    buffer = renderer.render(size: Size(width: 20, height: 6))

    #expect(buffer[Point(x: 0, y: 2)].style != comment, "line 3 is code again")
    #expect(buffer[Point(x: 0, y: 3)].style == HighlightKind.keyword.cellStyle, "let is a keyword again")
}

@Test @MainActor func syntaxTextViewPrefersACustomHighlighter() {
    struct EverythingIsAString: SyntaxHighlighting {
        func highlight(line: String, state: inout HighlightState) -> [HighlightSpan] {
            [HighlightSpan(start: 0, length: line.count, kind: .string)]
        }
    }

    let view = SyntaxTextView(text: "return 42", language: "js")
    view.showsLineNumbers = false
    view.highlighter = EverythingIsAString()
    view.frame = Rect(x: 0, y: 0, width: 12, height: 2)

    let buffer = SceneRenderer(root: view).render(size: Size(width: 12, height: 2))
    #expect(buffer[Point(x: 0, y: 0)].style == HighlightKind.string.cellStyle, "the custom provider wins over the language")
}
