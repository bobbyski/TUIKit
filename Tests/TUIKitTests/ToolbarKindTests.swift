import Testing

@testable import TUIKit

// The five item kinds, the three display modes, and the ribbon built on top.

@MainActor
private func rendered(_ view: TUIView, width: Int, height: Int) -> [String] {
    view.frame = Rect(x: 0, y: 0, width: width, height: height)
    let buffer = SceneRenderer(root: view).render(size: Size(width: width, height: height))

    return (0..<height).map { row in
        String((0..<width).map { buffer[Point(x: $0, y: row)].character })
    }
}

// MARK: - Kinds

@Test @MainActor func flexibleSpaceSharesOutTheLeftoverWidth() {
    let bar = Toolbar()
    bar.addItem("A")
    bar.add(.flexibleSpace())
    bar.addItem("B")

    let lines = rendered(bar, width: 30, height: 1)
    let row = try! #require(lines.first)

    // The point of a flexible space: something pinned to the right-hand end.
    #expect(row.hasPrefix(" A"))
    #expect(row.trimmingCharacters(in: .whitespaces).hasSuffix("B"))

    // The gap absorbed the leftover rather than the item growing: A and B are
    // as far apart as the bar allows.
    let a = row.firstIndex(of: "A")!
    let b = row.firstIndex(of: "B")!
    #expect(row.distance(from: a, to: b) > 20)
}

@Test @MainActor func twoFlexibleSpacesSplitTheLeftoverEvenly() {
    let bar = Toolbar()
    bar.addItem("A")
    bar.add(.flexibleSpace())
    bar.addItem("B")
    bar.add(.flexibleSpace())
    bar.addItem("C")

    let row = rendered(bar, width: 31, height: 1)[0]
    let a = row.firstIndex(of: "A")!
    let b = row.firstIndex(of: "B")!
    let c = row.firstIndex(of: "C")!

    // Even split, remainder to the earliest — the same rule `StackView` uses,
    // so a stray cell lands in the same place in both.
    let left = row.distance(from: a, to: b)
    let right = row.distance(from: b, to: c)
    #expect(abs(left - right) <= 1)
}

@Test @MainActor func dividersAndSpacesArePunctuationNotFocusStops() {
    let bar = Toolbar()
    let first = bar.addItem("A")
    bar.add(.divider())
    bar.add(.space(3))
    let last = bar.addItem("B")

    #expect(first.isInteractive)
    #expect(last.isInteractive)

    // Stepping focus onto a separator is how a toolbar feels broken.
    #expect(bar.items.allSatisfy { item in
        switch item.kind {
        case .divider, .space, .flexibleSpace: return !item.isInteractive
        case .button, .view: return item.isInteractive
        }
    })

    let row = rendered(bar, width: 24, height: 1)[0]
    #expect(row.contains("│"))
}

@Test @MainActor func ahostedViewIsARealSubviewGivenItsOwnSegment() {
    let bar = Toolbar()
    bar.addItem("Run")
    let field = TextField(text: "query")
    bar.add(.view(field, title: "Search"))

    _ = rendered(bar, width: 40, height: 1)

    #expect(field.superview === bar, "the control is a subview, not a drawing")
    #expect(field.frame.size.width > 0)
    #expect(field.frame.minX > 0, "placed after the button")
}

// MARK: - Display modes

@Test @MainActor func iconOnlyAndTextOnlyAreOneRowAndBothIsTwo() {
    let bar = Toolbar()
    bar.addItem("Run", glyph: "▶")

    bar.displayMode = .textOnly
    #expect(bar.rowCount == 1)
    #expect(rendered(bar, width: 20, height: 1)[0].contains("Run"))

    bar.displayMode = .iconOnly
    #expect(bar.rowCount == 1)
    let icons = rendered(bar, width: 20, height: 1)[0]
    #expect(icons.contains("▶"))
    #expect(!icons.contains("Run"), "icon only means no label")

    // The extra row is what makes `.both` cost double, which is why it is
    // asked for rather than assumed.
    bar.displayMode = .both
    #expect(bar.rowCount == 2)
    let stacked = rendered(bar, width: 20, height: 2)
    #expect(stacked[0].contains("▶"))
    #expect(stacked[1].contains("Run"), "the label sits on its own row under the glyph")
}

@Test @MainActor func aTallHostedControlRaisesTheWholeBar() {
    let bar = Toolbar()
    bar.displayMode = .textOnly
    #expect(bar.rowCount == 1)

    let tall = TUIView()
    tall.minimumSize = Size(width: 6, height: 3)
    bar.add(.view(TallStub()))

    // The bar never hands a control less height than it asked for.
    #expect(bar.rowCount == 3)
    _ = tall
}

private final class TallStub: TUIView {
    override var intrinsicContentSize: Size? {
        Size(width: 6, height: 3)
    }
}

// MARK: - Ribbon

@Test @MainActor func aRibbonIsAToolbarPlusGroupCaptions() {
    let ribbon = Ribbon()
    ribbon.toolbar.displayMode = .textOnly
    ribbon.addGroup("Build", items: [ToolbarItem("Run"), ToolbarItem("Stop")])
    ribbon.addGroup("Project", items: [ToolbarItem("Config")])

    #expect(ribbon.groupTitles == ["Build", "Project"])

    // A divider between groups, inserted by the ribbon so a caller cannot
    // end up with two.
    #expect(ribbon.toolbar.items.contains { if case .divider = $0.kind { return true } else { return false } })

    // Captions cost one row on top of the bar's own.
    #expect(ribbon.rowCount == ribbon.toolbar.rowCount + 1)

    let lines = rendered(ribbon, width: 44, height: ribbon.rowCount)
    #expect(lines[0].contains("Run"))
    #expect(lines[1].contains("Build"), "the caption sits under its group")
    #expect(lines[1].contains("Project"))

    // And turning captions off gives the row back.
    ribbon.showsGroupTitles = false
    #expect(ribbon.rowCount == ribbon.toolbar.rowCount)
}

// MARK: - Mutation (what customising a toolbar actually is)

@Test @MainActor func itemsCanBeInsertedRemovedAndReordered() {
    let bar = Toolbar()
    bar.addItem("Run")
    bar.addItem("Stop")

    bar.insert(ToolbarItem("Build"), at: 0)
    #expect(bar.items.map(\.title) == ["Build", "Run", "Stop"])

    // Out of range clamps rather than crashing: a customisation palette works
    // from a list that may be one edit behind.
    bar.insert(ToolbarItem("Last"), at: 99)
    bar.insert(ToolbarItem("First"), at: -5)
    #expect(bar.items.map(\.title) == ["First", "Build", "Run", "Stop", "Last"])

    #expect(bar.remove(at: 0)?.title == "First")
    #expect(bar.remove(at: 99) == nil, "and removing what is not there is a no-op")

    bar.move(from: 0, to: 2)
    #expect(bar.items.map(\.title) == ["Run", "Stop", "Build", "Last"])

    bar.removeAllItems()
    #expect(bar.items.isEmpty)
}

@Test @MainActor func removingAHostedControlTakesItOffTheBar() {
    // Left as a subview it would keep drawing where nothing places it.
    let bar = Toolbar()
    let field = TextField(text: "search")
    bar.add(.view(field, title: "Search"))
    #expect(field.superview === bar)

    _ = bar.remove(at: 0)
    #expect(field.superview == nil)
}

@Test @MainActor func changingAnItemRepaintsTheBarThatHoldsIt() {
    // THE BUG: isEnabled, isVisible and title were plain vars, so anyone
    // holding only the item saw a stale bar until something else forced a
    // repaint.
    let bar = Toolbar()
    bar.frame = Rect(x: 0, y: 0, width: 30, height: 1)
    let stop = bar.addItem("Stop")

    _ = SceneRenderer(root: bar).render(size: Size(width: 30, height: 1))
    #expect(!bar.needsDisplay)

    stop.isEnabled = false
    #expect(bar.needsDisplay)

    _ = SceneRenderer(root: bar).render(size: Size(width: 30, height: 1))
    stop.title = "Halt"
    #expect(bar.needsDisplay)

    _ = SceneRenderer(root: bar).render(size: Size(width: 30, height: 1))
    stop.isVisible = false
    #expect(bar.needsDisplay)

    // Setting a value to what it already was is not a change.
    _ = SceneRenderer(root: bar).render(size: Size(width: 30, height: 1))
    stop.isVisible = false
    #expect(!bar.needsDisplay)
}

@Test @MainActor func anItemRemovedFromABarNoLongerRepaintsIt() {
    let bar = Toolbar()
    bar.frame = Rect(x: 0, y: 0, width: 30, height: 1)
    let item = bar.addItem("Run")
    _ = bar.remove(at: 0)

    _ = SceneRenderer(root: bar).render(size: Size(width: 30, height: 1))
    item.isEnabled = false
    #expect(!bar.needsDisplay)
}
