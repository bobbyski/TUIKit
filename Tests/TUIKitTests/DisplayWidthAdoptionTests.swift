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
