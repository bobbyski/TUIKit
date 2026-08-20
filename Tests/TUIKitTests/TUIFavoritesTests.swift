import Testing
@testable import TUIKit

/// The favorites bar: what fits is on the row, what does not is behind `>>`.
@MainActor
struct TUIFavoritesTests {

    /// A bar of `width` columns holding `titles`.
    private func bar(width: Int, _ titles: [String]) -> TUIFavorites {
        let bar = TUIFavorites()
        bar.items = titles.map { TUIFavorites.Item(title: $0) }
        bar.frame = Rect(x: 0, y: 0, width: width, height: 1)
        bar.layoutIfNeeded()
        return bar
    }

    private func render(_ bar: TUIFavorites) -> String {
        SceneRenderer(root: bar).render(size: bar.frame.size).textLines()[0]
    }

    @Test("items that fit are all drawn, with no overflow button")
    func everythingFitsSoNoOverflow() {
        let line = render(bar(width: 40, ["Docs", "Mail"]))

        #expect(line.contains("★ Docs"))
        #expect(line.contains("★ Mail"))
        #expect(!line.contains(">>"), "nothing overflowed")
    }

    @Test("what does not fit is replaced by an overflow button")
    func tooManyItemsOverflow() {
        let line = render(bar(width: 20, ["Alpha", "Bravo", "Charlie", "Delta"]))

        #expect(line.contains("★ Alpha"))
        #expect(line.hasSuffix(" >> "), "the overflow button ends the row")
        #expect(!line.contains("Delta"), "the tail moved into the menu")
    }

    @Test("clicking a visible item reports its index")
    func clickingAnItemReportsIt() {
        let favorites = bar(width: 40, ["Docs", "Mail"])
        var chosen: [Int] = []
        favorites.onActivate = { chosen.append($0) }

        // " ★ Docs " is 8 columns, so the second item starts at 8.
        _ = favorites.mouseEvent(MouseInput(position: Point(x: 2, y: 0), action: .press, button: .left))
        _ = favorites.mouseEvent(MouseInput(position: Point(x: 9, y: 0), action: .press, button: .left))

        #expect(chosen == [0, 1])
    }

    @Test("a click past the last item activates nothing")
    func clickingEmptySpaceDoesNothing() {
        let favorites = bar(width: 40, ["Docs"])
        var chosen: [Int] = []
        favorites.onActivate = { chosen.append($0) }

        _ = favorites.mouseEvent(MouseInput(position: Point(x: 30, y: 0), action: .press, button: .left))
        #expect(chosen.isEmpty)
    }

    @Test("the overflow menu carries the items the row could not show")
    func overflowMenuHoldsTheRest() throws {
        let window = Window()
        window.frame = Rect(x: 0, y: 0, width: 20, height: 6)

        let favorites = TUIFavorites()
        favorites.items = ["Alpha", "Bravo", "Charlie", "Delta"].map { TUIFavorites.Item(title: $0) }
        favorites.frame = Rect(x: 0, y: 0, width: 20, height: 1)
        window.addSubview(favorites)
        window.layoutIfNeeded()

        var chosen: [Int] = []
        favorites.onActivate = { chosen.append($0) }

        // Clicking `>>` opens a context menu on the window.
        let line = SceneRenderer(root: window).render(size: window.frame.size).textLines()[0]
        let overflowX = line.count - 2
        _ = favorites.mouseEvent(MouseInput(position: Point(x: overflowX, y: 0), action: .press, button: .left))

        window.layoutIfNeeded()
        let rows = SceneRenderer(root: window).render(size: window.frame.size).textLines()
        let dropdown = rows.dropFirst().joined(separator: "\n")

        #expect(dropdown.contains("Charlie"), "the overflow menu lists what did not fit")
        #expect(dropdown.contains("Delta"))

        // Choosing the last entry reports its index in `items`, not its place
        // in the menu — the bar's width must not change what a click means.
        guard let deltaRow = rows.firstIndex(where: { $0.contains("Delta") }) else {
            Issue.record("expected Delta in the dropdown")
            return
        }

        let deltaColumn = try #require(rows[deltaRow].firstIndex(of: "D")).utf16Offset(in: rows[deltaRow])
        window.route(.mouse(MouseInput(position: Point(x: deltaColumn, y: deltaRow),
                                       action: .press, button: .left)))
        window.route(.mouse(MouseInput(position: Point(x: deltaColumn, y: deltaRow),
                                       action: .release, button: .left)))
        #expect(chosen == [3])
    }

    @Test("an empty bar can say so")
    func anEmptyBarShowsItsPlaceholder() {
        let favorites = TUIFavorites()
        favorites.emptyText = "No favorites yet"
        favorites.frame = Rect(x: 0, y: 0, width: 30, height: 1)
        favorites.layoutIfNeeded()

        #expect(render(favorites).contains("No favorites yet"))
    }
}
