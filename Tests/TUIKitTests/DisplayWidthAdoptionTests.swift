import Foundation
import Testing
@testable import TUIKit

// ActiveUI's TUIKIT_CHANGE_REQUESTS.md R1: the text controls measured in
// characters while the terminal advances in columns, so CJK and emoji
// mis-aligned everywhere text was centred, wrapped, truncated or padded.

@MainActor
private func render(_ view: TUIView, width: Int, height: Int) -> [String] {
    let window = Window(frame: Rect(x: 0, y: 0, width: width, height: height))
    view.frame = Rect(x: 0, y: 0, width: width, height: height)
    window.addSubview(view)
    return SceneRenderer(root: window).render(size: Size(width: width, height: height)).textLines()
}

@Test @MainActor func aLabelMeasuresCJKInColumns() {
    let label = Label("日本語")
    #expect(label.intrinsicContentSize?.width == 6, "three characters, six columns")

    label.alignment = .center
    let centered = render(label, width: 10, height: 1)[0]
    #expect(centered.hasPrefix("  日本語"), "centred by columns: (10 - 6) / 2 leads")

    label.alignment = .trailing
    let trailing = render(label, width: 10, height: 1)[0]
    #expect(trailing.hasPrefix("    日本語"), "trailing by columns")
}

@Test @MainActor func truncationCountsColumnsAndNeverSplitsAWideCharacter() {
    #expect(Label.truncated("日本語", width: 6) == "日本語", "exactly fits")
    #expect(Label.truncated("日本語", width: 4) == "日…", "日本… would be five columns; half a 本 is not a character")
    #expect(Label.truncated("abcdef", width: 4) == "abc…", "ASCII behaves exactly as before")
    #expect(Label.truncated("日本語", width: 1) == "…")
}

@Test @MainActor func aTextViewWrapsByColumnsNotCharacters() {
    let view = TextView(text: "日本語の犬です")
    let lines = render(view, width: 6, height: 4)

    // Seven characters are fourteen columns: three per six-column row.
    #expect(lines[0].hasPrefix("日本語"))
    #expect(lines[1].hasPrefix("の犬で"))
    #expect(lines[2].hasPrefix("す"))
}

@Test @MainActor func aTextViewCursorLandsOnDisplayColumns() {
    let view = TextView(text: "日本語")
    view.frame = Rect(x: 0, y: 0, width: 10, height: 2)
    _ = render(view, width: 10, height: 2)

    // A click on either cell of a wide character puts the caret before it.
    _ = view.mouseEvent(MouseInput(position: Point(x: 1, y: 0), action: .press, button: .left))
    #expect(view.cursorPosition == Point(x: 0, y: 0), "right half of 日 is still 日")

    _ = view.mouseEvent(MouseInput(position: Point(x: 2, y: 0), action: .press, button: .left))
    #expect(view.cursorPosition == Point(x: 1, y: 0), "column two is where 本 begins")

    // Typing after a click lands where the caret shows, not two cells left.
    _ = view.keyDown(KeyInput(key: .character("x")))
    #expect(view.text == "日x本語")

    _ = view.mouseEvent(MouseInput(position: Point(x: 9, y: 0), action: .press, button: .left))
    #expect(view.cursorPosition == Point(x: 4, y: 0), "past the end clamps to the end")
}

@Test @MainActor func aTableViewKeepsItsColumnGridUnderCJKCells() {
    let table = TableView(
        columns: [TableColumn("Name", width: .fixed(8)), TableColumn("Kind")],
        rows: [["日本語", "wide"], ["ascii", "plain"]]
    )
    let lines = render(table, width: 20, height: 4)

    let wide = lines[1].range(of: "wide")
    let plain = lines[2].range(of: "plain")
    #expect(wide != nil && plain != nil)

    // The second column starts at the same display column in both rows. The
    // rendered strings differ in CHARACTER count (continuation cells draw
    // nothing), so compare the columns before each cell instead.
    if let wide, let plain {
        let wideLead = DisplayWidth.of(String(lines[1][lines[1].startIndex..<wide.lowerBound]))
        let plainLead = DisplayWidth.of(String(lines[2][lines[2].startIndex..<plain.lowerBound]))
        #expect(wideLead == plainLead, "a CJK cell must not push its neighbour")
    }
}

@Test @MainActor func aListViewTruncatesAndPadsCJKRowsByColumns() {
    let list = ListView(items: ["日本語のとても長い名前", "short"])
    let lines = render(list, width: 10, height: 3)

    #expect(lines[0].contains("…"), "a row wider than the view truncates")
    #expect(lines[1].hasPrefix("short"))
}

// ── Second wave (SUPPORT_TERMINAL_PLAN.md U3) ────────────────────────────
//
// The first wave fixed the text controls. These are the twenty-eight other
// places that measured a title, a caption or a chart label in characters:
// menu bars, panels, pop-ups, completion lists, toolbars, forms, gauges,
// progress bars, navigators and all five chart axes.

@Test @MainActor func aMenuBarPlacesCJKTitlesByColumns() {
    let bar = MenuBar()
    bar.addMenu(Menu("日本"))            // four columns, not two
    bar.addMenu(Menu("File"))
    bar.frame = Rect(x: 0, y: 0, width: 40, height: 1)
    let line = render(bar, width: 40, height: 1)[0]

    // The second title has to clear the first: two spaces of gap after four
    // columns of CJK. Counting characters put it at index 4 — on top of the 本.
    // Against an ASCII title of the SAME column width, so the assertion is
    // about columns rather than about the bar's own leading chrome.
    let ascii = MenuBar()
    ascii.addMenu(Menu("ab12"))          // four columns, four characters
    ascii.addMenu(Menu("File"))
    ascii.frame = Rect(x: 0, y: 0, width: 40, height: 1)
    let asciiLine = render(ascii, width: 40, height: 1)[0]

    let cjkFile = line.range(of: "File").map { line.distance(from: line.startIndex, to: $0.lowerBound) }
    let asciiFile = asciiLine.range(of: "File").map { asciiLine.distance(from: asciiLine.startIndex, to: $0.lowerBound) }
    #expect(cjkFile != nil && asciiFile != nil)
    // Two characters of CJK and four of ASCII are both four columns, so the
    // next title starts in the same place. Counting characters put the CJK
    // one two columns early — on top of its own 本.
    #expect(DisplayWidth.of(line.prefix(cjkFile ?? 0)) == DisplayWidth.of(asciiLine.prefix(asciiFile ?? 0)),
            "a four-column title advances the bar by four columns, whatever its character count")
}

@Test @MainActor func aTabStripAdvancesByColumns() {
    // Each tab's x is the running sum of the ones before it, so a title
    // measured in characters puts every later tab — and every later hit
    // test — two columns left of where it is drawn.
    let tabs = TabView()
    tabs.addTab("日本", content: Label("one"))
    tabs.addTab("Two", content: Label("two"))
    let line = render(tabs, width: 30, height: 3)[0]

    let plain = TabView()
    plain.addTab("ab12", content: Label("one"))     // four columns, as 日本 is
    plain.addTab("Two", content: Label("two"))
    let plainLine = render(plain, width: 30, height: 3)[0]

    func column(of needle: String, in text: String) -> Int? {
        text.range(of: needle).map { DisplayWidth.of(text[text.startIndex..<$0.lowerBound]) }
    }
    #expect(column(of: "Two", in: line) != nil)
    #expect(column(of: "Two", in: line) == column(of: "Two", in: plainLine),
            "a four-column tab title advances the strip by four columns")
}

@Test @MainActor func aPopUpButtonPadsCJKItemsToTheSameWidth() {
    let popup = PopUpButton(items: ["日本語", "abc"])
    popup.frame = Rect(x: 0, y: 0, width: 12, height: 1)
    let closed = render(popup, width: 12, height: 1)[0]

    // The closed button shows the selection; what matters is that the row it
    // draws is the width it claimed, so the next control does not overlap it.
    #expect(DisplayWidth.of(closed) <= 12,
            "a CJK selection must not overrun the button it is drawn in")
}

@Test @MainActor func intrinsicWidthsCountColumnsAcrossTheControls() {
    // The sizing side of the same bug: a control that asks for as many cells
    // as its title has *characters* is drawn half as wide as its own text.
    #expect(Checkbox("日本語").intrinsicContentSize?.width == 6 + 4)
    #expect(Link("日本語", url: "https://example.com").intrinsicContentSize?.width == 6)
    #expect(ToggleButton("日本語").intrinsicContentSize?.width == 6 + 2)
}

// ── TextField's scroll model (U3's named remainder) ──────────────────────

@Test @MainActor func aTextFieldScrollsByColumnsNotCharacters() {
    let field = TextField()
    field.setText("日本語の犬です")          // seven characters, fourteen columns
    field.frame = Rect(x: 0, y: 0, width: 8, height: 1)

    let window = Window(frame: Rect(x: 0, y: 0, width: 8, height: 1))
    window.addSubview(field)
    window.makeFirstResponder(field)
    // `setText` leaves the caret at the end, which is the case that scrolls.

    let line = SceneRenderer(root: window)
        .render(size: Size(width: 8, height: 1)).textLines()[0]

    // Whatever it shows, it must not overrun the field: the old form
    // subtracted a character count from a column budget and scrolled about
    // half as far as it had to, leaving the caret off the right-hand end.
    #expect(DisplayWidth.of(line) <= 8)
    #expect(line.contains("す"), "the caret's own character has to be on screen")
}

@Test @MainActor func aTextFieldNeverDrawsHalfAWideCharacter() {
    let field = TextField()
    field.setText("日本語")                  // six columns
    field.frame = Rect(x: 0, y: 0, width: 5, height: 1)   // room for two and a half

    let window = Window(frame: Rect(x: 0, y: 0, width: 5, height: 1))
    window.addSubview(field)

    let line = SceneRenderer(root: window)
        .render(size: Size(width: 5, height: 1)).textLines()[0]

    #expect(DisplayWidth.of(line.trimmingCharacters(in: .whitespaces)) <= 5,
            "half of a 日 is not a character, it is a corrupted cell")
}

@Test @MainActor func clickingAWideCharacterLandsOnIt() {
    let field = TextField()
    field.setText("日本語")
    field.frame = Rect(x: 0, y: 0, width: 10, height: 1)

    let window = Window(frame: Rect(x: 0, y: 0, width: 10, height: 1))
    window.addSubview(field)
    window.makeFirstResponder(field)

    // Column 2 is the start of 本 — the second character, not the third.
    _ = field.mouseEvent(MouseInput(position: Point(x: 2, y: 0), action: .press, button: .left))
    _ = field.keyDown(KeyInput(key: .character("X")))
    #expect(field.text == "日X本語",
            "a click at column 2 is the caret before the second character")
}

