import CodeEditorCore
import Testing
import TUIKit
@testable import TUICodeEditor

// The over/under view: what it draws, and the alignment claim.

@MainActor
private func rendered(_ view: TUIView, width: Int, height: Int) -> [String] {
    view.frame = Rect(x: 0, y: 0, width: width, height: height)
    let buffer = SceneRenderer(root: view).render(size: Size(width: width, height: height))

    return (0..<height).map { row in
        String((0..<width).map { buffer[Point(x: $0, y: row)].character })
    }
}

@MainActor
private func diffView(old: String, new: String) -> DiffView {
    let view = DiffView()
    view.model = DiffModel.build(old: old, new: new)
    view.oldTitle = "5361d7e"
    view.newTitle = "Working"
    return view
}

@Test @MainActor func bothRevisionsAreNamedAndTheChangeIsMarked() {
    let view = diffView(old: "one\ntwo\nthree", new: "one\nTWO\nthree")
    let lines = rendered(view, width: 40, height: 9)

    #expect(lines[0].contains("5361d7e"))
    #expect(lines[0].contains("-1 +1"), "the caption tallies the edit")
    #expect(lines.contains { $0.contains("- ") && $0.contains("two") })

    let bottom = lines.drop(while: { !$0.contains("Working") })
    #expect(bottom.contains { $0.contains("+ ") && $0.contains("TWO") })
}

@Test @MainActor func aChangeOnTopSitsDirectlyAboveItsCounterpart() {
    // The claim the whole design rests on. Both halves get the same rows, so
    // the offset of a row within its half is the same number on both sides.
    let view = diffView(old: "a\nb\nc\nd\ne", new: "a\nb\nC\nd\ne")
    let lines = rendered(view, width: 30, height: 13)

    let rows = view.rowsPerHalf
    let topRow = lines[1...rows].firstIndex { $0.contains("- ") }
    let bottomRow = lines[(rows + 2)...].firstIndex { $0.contains("+ ") }

    #expect(topRow != nil)
    #expect(bottomRow != nil)
    #expect(topRow.map { $0 - 1 } == bottomRow.map { $0 - (rows + 2) },
            "the removed line and the line replacing it are at the same depth in their halves")
}

@Test @MainActor func fillerRowsKeepTheContextLevel() {
    // Three out, one in: the bottom half shows two blank rows so "tail" lands
    // level on both sides.
    let view = diffView(old: "head\na\nb\nc\ntail", new: "head\nA\ntail")
    let lines = rendered(view, width: 30, height: 13)

    let rows = view.rowsPerHalf
    let top = Array(lines[1...rows])
    let bottom = Array(lines[(rows + 2)...])

    let topTail = top.firstIndex { $0.contains("tail") }
    let bottomTail = bottom.firstIndex { $0.contains("tail") }
    #expect(topTail != nil)
    #expect(topTail == bottomTail)
}

@Test @MainActor func scrollingMovesBothHalvesAtOnce() {
    let old = (1...40).map { "line \($0)" }.joined(separator: "\n")
    let new = (1...40).map { $0 == 30 ? "CHANGED" : "line \($0)" }.joined(separator: "\n")
    let view = diffView(old: old, new: new)
    _ = rendered(view, width: 40, height: 13)

    view.setScrollOffset(vertical: 25)
    let lines = rendered(view, width: 40, height: 13)
    let rows = view.rowsPerHalf

    // The same model row heads both halves — one offset, no drift.
    #expect(lines[1].contains("line 26"))
    #expect(lines[rows + 2].contains("line 26"))
}

@Test @MainActor func nextChangeJumpsToTheEditAndWraps() {
    let old = (1...60).map { "line \($0)" }.joined(separator: "\n")
    let new = (1...60).map { $0 == 50 ? "CHANGED" : "line \($0)" }.joined(separator: "\n")
    let view = diffView(old: old, new: new)
    _ = rendered(view, width: 40, height: 13)

    view.goToNextChange()
    #expect(view.verticalOffset > 0, "a diff of a long file is mostly context; n skips it")

    let atChange = view.verticalOffset
    view.goToNextChange()
    #expect(view.verticalOffset <= atChange, "one change means the next one wraps back to it")
}

@Test @MainActor func scrollSpansDriveTheBorderScrollbars() {
    let old = (1...100).map { "line \($0)" }.joined(separator: "\n")
    let view = diffView(old: old, new: old)
    _ = rendered(view, width: 40, height: 13)

    let span = try! #require(view.verticalScrollSpan)
    #expect(span.content == 100)
    #expect(span.viewport == view.rowsPerHalf)

    // Clamped, like every other scrollable surface.
    view.setScrollOffset(vertical: 10_000)
    #expect(view.verticalOffset == 100 - view.rowsPerHalf)
}

@Test @MainActor func anIdenticalPairSaysSoRatherThanDrawingNothing() {
    let view = DiffView()
    view.model = DiffModel.build(old: "same", new: "same")
    let lines = rendered(view, width: 30, height: 6)

    #expect(lines.contains { $0.contains("same") }, "context still draws")
    #expect(view.model.isEmpty)
}
