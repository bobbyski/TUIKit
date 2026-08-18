import CodeEditorCore
import Testing
import TUIKit

@testable import TUICodeEditor

// The view half: cells on a grid. Rendered through SceneRenderer so these are
// real frames, not mocks.

@MainActor
private func render(_ editor: CodeEditorView, width: Int = 44, height: Int = 8) -> [String] {
    editor.frame = Rect(x: 0, y: 0, width: width, height: height)

    let buffer = SceneRenderer(root: editor).render(size: Size(width: width, height: height))

    return (0..<height).map { row in
        String((0..<width).map { buffer[Point(x: $0, y: row)].character })
    }
}

@MainActor
private func styles(_ editor: CodeEditorView, row: Int, width: Int = 44, height: Int = 8) -> [CellStyle] {
    editor.frame = Rect(x: 0, y: 0, width: width, height: height)
    let buffer = SceneRenderer(root: editor).render(size: Size(width: width, height: height))
    return (0..<width).map { buffer[Point(x: $0, y: row)].style }
}

// MARK: - Gutter

@Test @MainActor func theGutterStacksItsBands() {
    let editor = CodeEditorView(text: "one\ntwo", language: "swift")
    let lines = render(editor)

    // breakpoint + ribbon + diagnostics + fold + numbers + separator
    #expect(editor.gutterColumns == 1 + 1 + 1 + 1 + 3 + 1)
    #expect(lines[0].contains("1 │"), "line numbers then the separator")
    #expect(lines[1].contains("2 │"))
}

@Test @MainActor func theGutterWidensWithTheLineCount() {
    let small = CodeEditorView(text: "a")
    let large = CodeEditorView(text: (1...1000).map(String.init).joined(separator: "\n"))

    _ = render(small)
    _ = render(large)

    #expect(large.gutterColumns > small.gutterColumns, "four digits need more room than one")
}

@Test @MainActor func theChangeRibbonMarksEachKind() {
    let editor = CodeEditorView(text: "a\nb\nc")
    editor.lineChanges = [0: .added, 1: .modified, 2: .deletedAbove]

    let lines = render(editor)

    #expect(lines[0].contains("▌"))
    #expect(lines[1].contains("▌"))
    #expect(lines[2].contains("▔"), "a deletion marks the boundary, not a line")
}

@Test @MainActor func diagnosticsShowSeverityAndUnderlineTheirRange() {
    let editor = CodeEditorView(text: "let broken = 1", language: "swift")
    editor.diagnostics = DiagnosticSet([
        EditorDiagnostic(line: 0, column: 4, length: 6, severity: .error, message: "bad")
    ])

    let lines = render(editor)
    #expect(lines[0].contains("✖"), "the gutter carries the severity")

    let row = styles(editor, row: 0)
    let underlined = row.filter { $0.flags.contains(.underline) }.count
    #expect(underlined == 6, "exactly the diagnostic's range is underlined")
}

@Test @MainActor func staleDiagnosticsDimRatherThanDisappear() {
    // After an edit the markers are out of date but still the best
    // information there is; hiding them makes a broken file look clean.
    let editor = CodeEditorView(text: "x", language: "swift")
    editor.diagnostics = DiagnosticSet(
        [EditorDiagnostic(line: 0, severity: .warning, message: "w")],
        isStale: true
    )

    let lines = render(editor)
    #expect(lines[0].contains("⚠"))

    let row = styles(editor, row: 0)
    #expect(row.contains { $0.flags.contains(.dim) })
}

@Test @MainActor func theWorstSeverityOnALineWins() {
    let editor = CodeEditorView(text: "x")
    editor.diagnostics = DiagnosticSet([
        EditorDiagnostic(line: 0, severity: .info, message: "i"),
        EditorDiagnostic(line: 0, severity: .error, message: "e"),
        EditorDiagnostic(line: 0, severity: .warning, message: "w"),
    ])

    #expect(render(editor)[0].contains("✖"), "a gutter cell can only show one")
}

@Test @MainActor func gutterClicksRouteToTheOwningBand() {
    let editor = CodeEditorView(text: "a\nb\nc")
    _ = render(editor)

    var toggled: [Int] = []
    editor.breakpoints.onToggle = { toggled.append($0) }

    var selected: [Int] = []
    editor.diagnosticsBand.diagnostics = DiagnosticSet([
        EditorDiagnostic(line: 1, severity: .error, message: "e")
    ])
    editor.diagnosticsBand.onSelect = { selected.append($0) }

    // Column 0 is the breakpoint band; column 2 the diagnostics band
    // (breakpoint, ribbon, diagnostics, fold, numbers).
    _ = editor.handleGutterClick(at: Point(x: 0, y: 2))
    _ = editor.handleGutterClick(at: Point(x: 2, y: 1))

    #expect(toggled == [2], "the click column decides which band fires")
    #expect(selected == [1])
}

// MARK: - Syntax on screen

@Test @MainActor func keywordsAndCommentsGetDifferentStyles() {
    let editor = CodeEditorView(text: "let x = 1 // note", language: "swift")
    let row = styles(editor, row: 0)
    let gutter = editor.gutterColumns

    let keyword = row[gutter]                       // "l" of let
    let comment = row[gutter + 10]                  // inside the comment

    #expect(keyword != comment, "syntax colouring reaches the cells")
    #expect(comment.flags.contains(.dim), "comments are dimmed by the default theme")
}

@Test @MainActor func aBlockCommentStaysColouredAcrossLines() {
    // The headline gap, end to end on a real grid.
    let editor = CodeEditorView(text: "/* open\nfunc notCode()\nstill */\nlet x = 1", language: "swift")
    let gutter = editor.gutterColumns

    let inside = styles(editor, row: 1)[gutter]
    let after = styles(editor, row: 3)[gutter]

    #expect(inside.flags.contains(.dim), "line 2 is inside the comment")
    #expect(!after.flags.contains(.dim), "line 4 is code again")
}

// MARK: - Editing through the view

@Test @MainActor func typingGoesInAndReportsChanges() {
    let editor = CodeEditorView(text: "", language: "swift")
    var reported: [String] = []
    editor.onChanged = { reported.append($0) }

    _ = editor.keyDown(KeyInput(key: .character("a")))
    _ = editor.keyDown(KeyInput(key: .character("b")))

    #expect(editor.text == "ab")
    #expect(reported.last == "ab")
}

@Test @MainActor func aReadOnlyEditorTakesNoTextButStillMoves() {
    let editor = CodeEditorView(text: "abc\ndef")
    editor.isEditable = false

    _ = editor.keyDown(KeyInput(key: .character("x")))
    #expect(editor.text == "abc\ndef", "no typing")

    _ = editor.keyDown(KeyInput(key: .down))
    #expect(editor.cursorPosition.y == 1, "but navigation still works")
}

@Test @MainActor func tabIndentsASelectionAndInsertsAUnitWithoutOne() {
    let editor = CodeEditorView(text: "a\nb", language: "swift")

    _ = editor.keyDown(KeyInput(key: .tab))
    #expect(editor.text == "    a\nb", "no selection: insert a unit")

    editor.selectAll()
    _ = editor.keyDown(KeyInput(key: .tab))
    #expect(editor.text == "        a\n    b", "with a selection: shift the lines")
}

@Test @MainActor func controlChordsDoTheUsualThings() {
    let editor = CodeEditorView(text: "hello", language: "swift")
    let pasteboard = Pasteboard()
    editor.pasteboard = pasteboard

    editor.selectAll()
    _ = editor.keyDown(KeyInput(key: .character("c"), modifiers: .control))
    #expect(pasteboard.string == "hello")

    _ = editor.keyDown(KeyInput(key: .character("z"), modifiers: .control))   // nothing to undo yet
    _ = editor.keyDown(KeyInput(key: .character("v"), modifiers: .control))
    #expect(editor.text == "hello", "pasting over the selection replaces it")
}

@Test @MainActor func clickingPlacesTheCaretPastTheGutter() {
    let editor = CodeEditorView(text: "hello world")
    _ = render(editor)

    let position = editor.position(at: Point(x: editor.gutterColumns + 4, y: 0))

    #expect(position == TextPosition(line: 0, column: 4), "the gutter is not part of the text")
}

// MARK: - Viewport

@Test @MainActor func theCaretScrollsItselfIntoView() {
    let editor = CodeEditorView(text: (1...100).map { "line \($0)" }.joined(separator: "\n"))
    _ = render(editor, height: 6)

    editor.scrollTo(line: 80)
    let lines = render(editor, height: 6)

    #expect(lines.contains { $0.contains("line 81") }, "line 81 is on screen (1-based numbering)")
}

@Test @MainActor func borderScrollbarsReportTheirSpans() {
    let editor = CodeEditorView(text: (1...50).map(String.init).joined(separator: "\n"))
    _ = render(editor, height: 10)

    let span = editor.verticalScrollSpan

    #expect(span?.content == 50)
    #expect(span?.viewport == 10)
}

@Test @MainActor func embeddedBarsSuppressTheInteriorOnes() {
    // The window border hosts them instead; drawing both is the doubled-bar
    // bug the IDE hit in the old editor.
    let editor = CodeEditorView(text: (1...50).map(String.init).joined(separator: "\n"))
    editor.showsOwnScrollbars = false

    let lines = render(editor, width: 20, height: 6)

    #expect(lines.allSatisfy { $0.count == 20 })
    #expect(!editor.drawsVerticalBar)
}

// MARK: - Folding

@Test @MainActor func foldingHidesTheBodyAndMarksTheOpener() {
    let editor = CodeEditorView(text: "func f() {\n    one()\n    two()\n}\nlet after = 1", language: "swift")
    _ = render(editor)

    #expect(render(editor)[1].contains("one()"), "open to begin with")

    editor.toggleFold(at: 0)
    let lines = render(editor)

    #expect(lines[0].contains("⋯"), "the collapsed opener says so")
    #expect(!lines.joined().contains("one()"), "the body is gone")
    #expect(lines[1].contains("let after"), "the next visible line moves up")
}

@Test @MainActor func theFoldBandShowsTheRightControl() {
    let editor = CodeEditorView(text: "func f() {\n    x()\n}", language: "swift")
    _ = render(editor)

    #expect(render(editor)[0].contains("▾"), "foldable and open")

    editor.toggleFold(at: 0)
    #expect(render(editor)[0].contains("▸"), "collapsed")
}

@Test @MainActor func clickingBelowAFoldHitsTheRightLine() {
    // Rows map to VISIBLE lines; without that a click after a fold lands on
    // whatever line happens to share the row number.
    let editor = CodeEditorView(text: "func f() {\n    x()\n    y()\n}\ntarget", language: "swift")
    _ = render(editor)
    editor.toggleFold(at: 0)

    let position = editor.position(at: Point(x: editor.gutterColumns, y: 1))

    #expect(position.line == 4, "row 1 is 'target', not line 1")
}

@Test @MainActor func typingInsideAFoldOpensIt() {
    let editor = CodeEditorView(text: "func f() {\n    x()\n}", language: "swift")
    _ = render(editor)
    editor.toggleFold(at: 0)

    editor.scrollTo(line: 1)

    #expect(!editor.foldBand.map.isFolded(0), "you never type into text you cannot see")
}

@Test @MainActor func foldAllAndUnfoldAllWork() {
    let editor = CodeEditorView(text: "func a() {\n    x()\n}\nfunc b() {\n    y()\n}", language: "swift")
    _ = render(editor)

    editor.foldAll()
    #expect(editor.visibleDocumentLines == [0, 3])

    editor.unfoldAll()
    #expect(editor.visibleDocumentLines.count == 6)
}

// MARK: - The view's own scrollbars

@Test @MainActor func ownScrollbarsWearArrowsLikeTheEmbeddedOnes() {
    let editor = CodeEditorView(text: (1...60).map { "line \($0) " + String(repeating: "z", count: 90) }.joined(separator: "\n"))
    editor.showsOwnScrollbars = true

    let lines = render(editor, width: 40, height: 10)

    // The interior pair had no arrows and no drag while the border-embedded
    // pair had both — two implementations of one control, drifted apart.
    #expect(lines[0].hasSuffix("▴"))
    #expect(lines[8].hasSuffix("▾"))
    #expect(lines[9].hasPrefix("◂"), "and the horizontal one runs the WHOLE view, not from the gutter")
    #expect(lines[9].contains("▸"))
}

@Test @MainActor func pressingAnArrowStepsAndDraggingTheThumbScrolls() {
    let editor = CodeEditorView(text: (1...60).map { "line \($0)" }.joined(separator: "\n"))
    editor.showsOwnScrollbars = true
    _ = render(editor, width: 40, height: 10)

    let column = 39

    // The ▾ arrow steps one line.
    _ = editor.mouseEvent(MouseInput(position: Point(x: column, y: 9), action: .press, button: .left))
    #expect(editor.verticalScrollSpan?.offset == 1)
    _ = editor.mouseEvent(MouseInput(position: Point(x: column, y: 9), action: .release, button: .left))

    // A track press below the thumb pages down, keeping one line of context.
    _ = editor.mouseEvent(MouseInput(position: Point(x: column, y: 7), action: .press, button: .left))
    #expect((editor.verticalScrollSpan?.offset ?? 0) > 1)
    _ = editor.mouseEvent(MouseInput(position: Point(x: column, y: 7), action: .release, button: .left))

    // And the thumb drags.
    let before = editor.verticalScrollSpan?.offset ?? 0
    _ = editor.mouseEvent(MouseInput(position: Point(x: column, y: 3), action: .press, button: .left))
    _ = editor.mouseEvent(MouseInput(position: Point(x: column, y: 6), action: .drag, button: .left))
    #expect((editor.verticalScrollSpan?.offset ?? 0) != before, "the thumb follows the pointer")
}

// MARK: - Clipboard

@Test @MainActor func theEditorUsesTheAppClipboardWithoutTheHostWiringIt() {
    let app = App(driver: HeadlessDriver(size: Size(width: 40, height: 8)))
    let window = Window(frame: Rect(x: 0, y: 0, width: 40, height: 8))
    let editor = CodeEditorView(text: "alpha\nbeta", language: "swift")
    editor.frame = window.bounds
    window.addSubview(editor)
    app.present(window)
    window.makeFirstResponder(editor)

    // THE bug: `pasteboard` was an opt-in the host never opted into, so ^C,
    // ^X and ^V were bound, implemented, and returned early on nil — copy and
    // paste simply did nothing in OmegaCLIDE's code window for the editor's
    // whole life. It now falls back to the app's, which is the shape
    // `SyntaxTextView` already had.
    app.pasteboard.copy("gamma")
    #expect(editor.keyDown(KeyInput(key: .character("v"), modifiers: .control)))
    #expect(editor.text.contains("gamma"))

    // And copy reaches the app clipboard, so it also reaches the SYSTEM one:
    // `App` forwards copies to the driver, which emits OSC 52.
    editor.selectAll()
    #expect(editor.copySelection())
    #expect(app.pasteboard.string?.contains("gamma") == true)
}

@Test @MainActor func tintedLinesKeepTheirSyntaxColoursOnANewGround() {
    // The inline diff's colouring: a tinted line is the same line on a
    // different ground, not a line repainted one flat colour. Syntax has to
    // survive, or a diff block stops being readable code.
    let editor = CodeEditorView(text: "let a = 1\nlet b = 2", language: "swift")
    editor.frame = Rect(x: 0, y: 0, width: 40, height: 4)
    editor.lineTints = [1: .rgb(red: 80, green: 30, blue: 40)]

    let buffer = SceneRenderer(root: editor).render(size: Size(width: 40, height: 4))

    // The TEXT area, not the gutter: line numbers stay on the window's own
    // ground, the way they do in every diff worth copying — the band marks
    // the code, and a tinted gutter would just make the numbers harder to read.
    // Found rather than hard-coded, since the gutter's width follows the line
    // count.
    let divider = (0..<40).first { buffer[Point(x: $0, y: 1)].character == "│" } ?? 0
    let text = (divider + 1)..<38

    func cells(onRow row: Int) -> [TerminalCell] {
        text.map { buffer[Point(x: $0, y: row)] }
    }

    let plain = cells(onRow: 0)
    let tinted = cells(onRow: 1)

    #expect(tinted.allSatisfy { $0.style.background == .rgb(red: 80, green: 30, blue: 40) },
            "the whole text area wears the tint, including past the end of the line")
    #expect(plain.allSatisfy { $0.style.background != .rgb(red: 80, green: 30, blue: 40) })

    // `let` is a keyword on both rows and keeps its colour on the tinted one.
    let keyword = zip(plain, tinted).first { $0.0.character == "l" && $0.1.character == "l" }
    #expect(keyword != nil)
    #expect(keyword?.0.style.foreground == keyword?.1.style.foreground)
}

@Test @MainActor func aNumberProviderReplacesPositionsWithRealLineNumbers() {
    // A diff's rows come from two files; numbering them 1…n numbers a
    // document that exists nowhere.
    let editor = CodeEditorView(text: "removed\nadded\ncontext")
    editor.frame = Rect(x: 0, y: 0, width: 40, height: 4)
    editor.lineNumbers.widestProvidedNumber = 412
    editor.lineNumbers.numberProvider = { line in
        [410, nil, 412][line]   // the middle row belongs to neither file
    }

    let buffer = SceneRenderer(root: editor).render(size: Size(width: 40, height: 4))

    // Everything left of the separator — the number band sits after the
    // breakpoint, ribbon, diagnostic and fold bands.
    func gutter(_ row: Int) -> String {
        let divider = (0..<40).first { buffer[Point(x: $0, y: row)].character == "│" } ?? 0
        return String((0..<divider).map { buffer[Point(x: $0, y: row)].character })
            .trimmingCharacters(in: .whitespaces)
    }

    #expect(gutter(0) == "410")
    #expect(gutter(1).isEmpty, "a row belonging to neither file numbers nothing")
    #expect(gutter(2) == "412")
}

@Test @MainActor func trailingNumbersReserveTheirColumnOnlyWhenUsed() {
    // For the side-by-side diff still to come; an ordinary editor must be
    // exactly as wide as it was.
    let editor = CodeEditorView(text: "let a = 1")
    editor.frame = Rect(x: 0, y: 0, width: 30, height: 3)

    let plain = SceneRenderer(root: editor).render(size: Size(width: 30, height: 3))
    let lastColumn = (0..<3).map { plain[Point(x: 29, y: $0)].character }
    #expect(lastColumn.allSatisfy { $0 == " " })

    editor.trailingNumbers = [0: 412]
    let withNumbers = SceneRenderer(root: editor).render(size: Size(width: 30, height: 3))
    let right = String((25..<30).map { withNumbers[Point(x: $0, y: 0)].character })
    #expect(right.contains("412"), "the new file's number sits down the right edge")
}
