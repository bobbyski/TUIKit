import Testing
@testable import TUIKit

// Columns, not characters — the difference TUIKit did not previously have a
// way to express.

@Test func widthIsColumnsNotCharacters() {
    #expect(DisplayWidth.of("a") == 1)
    #expect(DisplayWidth.of("日") == 2, "one Character, two columns")
    #expect(DisplayWidth.of("한") == 2)
    #expect(DisplayWidth.of("🚀") == 2)
    #expect(DisplayWidth.of("│") == 1, "box drawing stays narrow, or every frame in the app moves")
    #expect(DisplayWidth.of("▶") == 1)
    #expect(DisplayWidth.of("─") == 1)
}

@Test func aPresentationSelectorMakesAGlyphWide() {
    // The difference is invisible in a source file and two columns wide on a
    // terminal, which is how a toolbar ends up one cell out of true.
    #expect(DisplayWidth.of("⚒") == 1)
    #expect(DisplayWidth.of("⚒\u{FE0F}") == 2)
}

@Test func combiningMarksTakeNoColumnOfTheirOwn() {
    // An accent is part of the letter before it, not a column after it.
    #expect(DisplayWidth.of("e\u{0301}") == 1)
    #expect(DisplayWidth.of("\u{200B}") == 0)
}

@Test func stringWidthAddsUp() {
    #expect(DisplayWidth.of("hello") == 5)
    #expect(DisplayWidth.of("日本語") == 6)
    #expect(DisplayWidth.of("a日b") == 4)
}

@Test func aPrefixNeverSplitsAWideGlyph() {
    // Half of a 日 is not a character; it is a corrupted row.
    let (text, width) = DisplayWidth.prefix(of: "日本語", fitting: 5)

    #expect(text == "日本")
    #expect(width == 4, "the odd column is left empty rather than half-filled")

    #expect(DisplayWidth.prefix(of: "日本", fitting: 1).text.isEmpty)
    #expect(DisplayWidth.prefix(of: "abc", fitting: 2).text == "ab")
}

@Test @MainActor func aWideGlyphOwnsTwoCellsAndDisplacesNothing() {
    // THE BUG: writing 日 at x and anything at x+1 made the terminal advance
    // three columns for two cells, so every cell after it on the row moved.
    let surface = RenderTarget(size: Size(width: 10, height: 1))
    let painter = Painter(target: surface, origin: .zero, clip: Rect(x: 0, y: 0, width: 10, height: 1))

    painter.write("日本x", at: .zero)

    #expect(surface.buffer[Point(x: 0, y: 0)].character == "日")
    #expect(surface.buffer[Point(x: 1, y: 0)].isContinuation, "the right half of the glyph before it")
    #expect(surface.buffer[Point(x: 2, y: 0)].character == "本")
    #expect(surface.buffer[Point(x: 3, y: 0)].isContinuation)
    #expect(surface.buffer[Point(x: 4, y: 0)].character == "x", "and the next character lands where it belongs")

    // The encoder emits the glyph once: the terminal's cursor is already past
    // the continuation column.
    let encoded = ANSIEncoder.encode(surface.buffer)[0]
    #expect(encoded.contains("日本x"))
    #expect(!encoded.contains("日 本"), "nothing is emitted in a continuation cell")

    // And the text projection reads the way a test author expects.
    #expect(surface.buffer.text(row: 0).hasPrefix("日本x"))
}

@Test func theGlyphsOmegaCLIDEActuallyUsesAreNarrow() {
    // A wide glyph in a toolbar shifts every label after it, so these are
    // worth pinning: they are the ones the IDE ships.
    for glyph in ["▤", "⤓", "⇊", "⚒", "▶", "■", "⌕", "⚙", "☰", "▸", "▾", "│", "─", "█", "•"] {
        #expect(DisplayWidth.of(Character(glyph)) == 1, "\(glyph) must stay one column")
    }
}
