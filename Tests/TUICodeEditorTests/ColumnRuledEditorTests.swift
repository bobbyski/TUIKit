import CodeEditorCore
import Testing
import TUIKit
@testable import TUICodeEditor

// Columns that mean something, shown as bands.

@MainActor
private func editor(_ text: String, width: Int = 90) -> ColumnRuledEditorView {
    let view = ColumnRuledEditorView(text: text, language: "cobol", bands: ColumnRuledEditorView.cobolFixedFormat)
    view.frame = Rect(x: 0, y: 0, width: width, height: 6)
    view.layoutIfNeeded()
    return view
}

@Test @MainActor func theCobolAreasAreWhereTheStandardSaysTheyAre() {
    let view = editor("       IDENTIFICATION DIVISION.")

    // 1–6 sequence, 7 indicator, 8–11 Area A, 12–72 Area B, 73+ discarded —
    // zero-based here, because that is what a character index is.
    #expect(view.band(atColumn: 0)?.name == "sequence")
    #expect(view.band(atColumn: 6)?.name == "indicator")
    #expect(view.band(atColumn: 7)?.name == "Area A")
    #expect(view.band(atColumn: 11)?.name == "Area B")
    #expect(view.band(atColumn: 71)?.name == "Area B", "72 is the last column a compiler reads")
    #expect(view.band(atColumn: 72)?.name == "ignored")
    #expect(view.band(atColumn: 200)?.name == "ignored")
}

@Test @MainActor func theIgnoredTailIsTheBandWorthNoticing() {
    let view = editor("      *" + String(repeating: "X", count: 100))

    let ignored = try! #require(view.bands.first { $0.name == "ignored" })
    #expect(ignored.emphasis == .warning)

    // An over-long statement looks correct and behaves differently, which is
    // the single most useful thing a COBOL editor can point out.
    let buffer = SceneRenderer(root: view).render(size: Size(width: 90, height: 6))
    let gutter = (0..<90).first { buffer[Point(x: $0, y: 0)].character == "│" } ?? 0
    let code = buffer[Point(x: gutter + 20, y: 0)].style.background
    let discarded = buffer[Point(x: gutter + 75, y: 0)].style.background

    #expect(code != discarded, "the two sides of column 72 do not look the same")
}

@Test @MainActor func anOrdinaryEditorPaysNothingForThis() {
    // No bands, no tints, no behaviour change — the subclass has to be free
    // when it is not being used.
    let plain = ColumnRuledEditorView(text: "let a = 1", language: "swift")
    plain.frame = Rect(x: 0, y: 0, width: 40, height: 4)
    plain.layoutIfNeeded()
    _ = SceneRenderer(root: plain).render(size: Size(width: 40, height: 4))

    #expect(plain.columnTints.isEmpty)
    #expect(plain.band(atColumn: 0) == nil)
}

@Test @MainActor func aTruecolourThemeGetsShadesAndAPaletteThemeGetsColours() {
    // Shades of the ground where there is a ground to shade: the bands read
    // as one surface with slightly different footing.
    var dark = CellStyle()
    dark.background = .rgb(red: 0, green: 0, blue: 170)
    let shaded = ColumnRuledEditorView.palette(over: dark)

    if case .rgb = shaded[.subtle] {
        // Expected.
    } else {
        Issue.record("a truecolor theme should be shaded, not painted")
    }

    #expect(shaded[.subtle] != dark.background, "a shade nobody can see is not a band")

    // And where there is nothing to shade, something that cannot be mistaken
    // for the ground. Gaudy beats invisible.
    var plain = CellStyle()
    plain.background = .standard
    #expect(ColumnRuledEditorView.palette(over: plain)[.subtle] == .named(.blue))
    #expect(ColumnRuledEditorView.palette(over: plain)[.warning] == .named(.red))
}

@Test @MainActor func shadingGoesTheDirectionWithRoomInIt() {
    // Lightening a near-white background produces the same near-white.
    var light = CellStyle()
    light.background = .rgb(red: 250, green: 250, blue: 250)

    guard case .rgb(let red, _, _)? = ColumnRuledEditorView.palette(over: light)[.subtle] else {
        Issue.record("no shade")
        return
    }

    #expect(red < 250, "a light ground darkens instead")
}

// MARK: - COBOL colouring

@Test func aStarInColumnSevenCommentsTheLine() {
    let highlighter = COBOLHighlighter()

    // The same asterisk in column 12 is multiplication — which is why COBOL
    // gets a scanner rather than a grammar.
    let comment = highlighter.tokens(for: "      * THIS IS A NOTE")
    #expect(comment.count == 1)
    #expect(comment.first?.scope == "comment.line")
    #expect(comment.first?.range == 0..<22)

    let code = highlighter.tokens(for: "           COMPUTE X = Y * Z.")
    #expect(code.contains { $0.scope == "keyword" })
    #expect(!code.contains { $0.scope == "comment.line" && $0.range.lowerBound == 0 })
}

@Test func anythingPastColumn72IsMarkedAsWhatItIs() {
    let line = "           DISPLAY " + String(repeating: "A", count: 80)
    let tokens = COBOLHighlighter().tokens(for: line)

    let ignored = tokens.first { $0.range.lowerBound == 72 }
    #expect(ignored?.scope == "comment.line", "a compiler will never see it")
}

@Test func cobolIsShoutedButNotAlways() {
    // Case-insensitive, and traditionally shouted: `Move` is the same verb.
    let upper = COBOLHighlighter().tokens(for: "           MOVE ZERO TO COUNTER.")
    let mixed = COBOLHighlighter().tokens(for: "           Move Zero To Counter.")

    #expect(upper.filter { $0.scope == "keyword" }.count == mixed.filter { $0.scope == "keyword" }.count)
}

@Test func pascalCommentsWithBracesRatherThanSlashesAndStars() {
    let highlighter = GrammarCatalog.highlighter(for: "pascal")
    let (tokens, _) = highlighter.tokenize(line: "  x := 1; { set the counter }", entering: .code)

    #expect(tokens.contains { $0.scope == "comment.block" })
    #expect(tokens.contains { $0.scope == "constant.numeric" })

    let (keywords, _) = highlighter.tokenize(line: "procedure Main; begin end;", entering: .code)
    #expect(keywords.filter { $0.scope == "keyword" }.count >= 3)
}
