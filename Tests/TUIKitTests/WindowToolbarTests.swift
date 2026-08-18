import Testing
@testable import TUIKit

/// A toolbar belongs to its window, and hidden items take no room.
@MainActor
struct WindowToolbarTests {
    private func window() -> FloatingWindow {
        let window = FloatingWindow(title: "Project", frame: Rect(x: 0, y: 0, width: 40, height: 12))
        window.layoutIfNeeded()
        return window
    }

    @Test("A toolbar handed to a window lands across the top of it")
    func toolbarSitsOnTop() {
        let window = window()
        let toolbar = Toolbar()
        toolbar.addItem("Build", glyph: "⚒")

        window.setToolbar(toolbar)
        window.layoutIfNeeded()

        let interior = window.slideOutRegion
        #expect(toolbar.frame.minY == interior.minY)
        #expect(toolbar.frame.minX == interior.minX)
        #expect(toolbar.frame.size.width == interior.size.width)
        #expect(toolbar.frame.size.height == 1)
        #expect(window.isToolbarVisible)
    }

    @Test("The toolbar's rows come off the top of what everything else gets")
    func toolbarShrinksTheInterior() {
        let window = window()
        let toolbar = Toolbar()
        toolbar.displayMode = .both                 // two rows
        toolbar.addItem("Build", glyph: "⚒")
        window.setToolbar(toolbar)
        window.layoutIfNeeded()

        let full = window.slideOutRegion
        let left = window.slideOutContentRegion
        #expect(left.minY == full.minY + 2)
        #expect(left.size.height == full.size.height - 2)
    }

    @Test("Slide-outs start below the toolbar, not beside it")
    func slideOutsClearTheToolbar() {
        let window = window()
        let toolbar = Toolbar()
        toolbar.addItem("Build", glyph: "⚒")
        window.setToolbar(toolbar)

        let files = window.addSlideOut(.leading, title: "Files", content: TUIView(), length: 10)
        window.openSlideOut(.leading)
        window.layoutIfNeeded()

        #expect(files.chrome.frame.minY == window.slideOutRegion.minY + 1)
        #expect(files.chrome.frame.maxY == window.slideOutRegion.maxY)
    }

    @Test("Hiding the toolbar gives the rows straight back")
    func hidingReturnsTheRows() {
        let window = window()
        let toolbar = Toolbar()
        toolbar.addItem("Build", glyph: "⚒")
        window.setToolbar(toolbar)
        window.layoutIfNeeded()

        let withBar = window.slideOutContentRegion.size.height
        window.setToolbarVisible(false)
        window.layoutIfNeeded()

        #expect(!window.isToolbarVisible)
        #expect(window.slideOutContentRegion.size.height == withBar + 1)
        #expect(window.slideOutContentRegion == window.slideOutRegion)
    }

    @Test("A hidden item takes no width and cannot be activated")
    func hiddenItemsTakeNoRoom() {
        let toolbar = Toolbar()
        toolbar.frame = Rect(x: 0, y: 0, width: 40, height: 1)
        toolbar.addItem("Build", glyph: "⚒")
        let commit = toolbar.addItem("Commit", glyph: "⌥")
        toolbar.addItem("Run", glyph: "▶")

        let wide = toolbar.intrinsicContentSize?.width
        commit.isVisible = false

        #expect(toolbar.intrinsicContentSize!.width < wide!)
        #expect(!commit.isInteractive)
        #expect(toolbar.span(ofItems: 1..<2)?.width == 0)
    }

    @Test("A hidden item does not draw, and the ones after it close up")
    func hiddenItemsDoNotDraw() {
        let toolbar = Toolbar()
        toolbar.frame = Rect(x: 0, y: 0, width: 30, height: 1)
        toolbar.addItem("Build")
        let commit = toolbar.addItem("Commit")
        toolbar.addItem("Run")
        commit.isVisible = false

        let line = rows(toolbar, width: 30, height: 1).first ?? ""
        #expect(!line.contains("Commit"))
        #expect(line.contains("Build"))
        #expect(line.contains("Run"))
    }

    @Test("A press fires the item's action, and a disabled one does not")
    func actionsFireOnPress() {
        let toolbar = Toolbar()
        toolbar.frame = Rect(x: 0, y: 0, width: 30, height: 1)

        var built = 0
        var stopped = 0
        toolbar.addItem("Build") { built += 1 }
        let stop = toolbar.addItem("Stop") { stopped += 1 }
        stop.isEnabled = false

        press(toolbar, item: 0)
        press(toolbar, item: 1)

        #expect(built == 1)
        #expect(stopped == 0)
    }

    @Test("A hidden item cannot be clicked, and the click lands nowhere")
    func hiddenItemsIgnoreClicks() {
        let toolbar = Toolbar()
        toolbar.frame = Rect(x: 0, y: 0, width: 30, height: 1)

        var fired = 0
        let build = toolbar.addItem("Build") { fired += 1 }
        build.isVisible = false
        toolbar.layoutIfNeeded()

        #expect(!toolbar.mouseEvent(MouseInput(position: Point(x: 0, y: 0), action: .press, button: .left)))
        #expect(fired == 0)
    }

    // Clicks the middle of an item's span.
    private func press(_ toolbar: Toolbar, item index: Int) {
        guard let span = toolbar.span(ofItems: index..<(index + 1)), span.width > 0 else {
            return
        }

        _ = toolbar.mouseEvent(
            MouseInput(position: Point(x: span.x + span.width / 2, y: 0), action: .press, button: .left)
        )
    }

    // Draws the view standalone and returns its rows as strings.
    private func rows(_ view: TUIView, width: Int, height: Int) -> [String] {
        view.frame = Rect(x: 0, y: 0, width: width, height: height)
        let buffer = SceneRenderer(root: view).render(size: Size(width: width, height: height))

        return (0..<height).map { row in
            String((0..<width).map { buffer[Point(x: $0, y: row)].character })
        }
    }
}
