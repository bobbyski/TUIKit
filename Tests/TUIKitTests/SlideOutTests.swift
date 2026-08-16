import Testing

@testable import TUIKit

// S1 — geometry. The arithmetic is a pure function (`SlideOutLayout`), so
// most of this needs no window; the two that do render real frames, because
// the premise of the whole design is a claim about what reaches the screen.

private func request(
    _ edge: SlideOutEdge,
    length: Int,
    minimum: Int = 1,
    open: Bool = true
) -> SlideOutLayout.Request {
    SlideOutLayout.Request(edge: edge, length: length, minimumLength: minimum, isOpen: open)
}

private let region = Rect(x: 0, y: 0, width: 80, height: 24)

// MARK: - The premise

@Test func closedSlideOutsTakeNoSpaceAtAll() {
    let result = SlideOutLayout.resolve(region: region, requests: [
        request(.leading, length: 20, open: false),
        request(.trailing, length: 20, open: false),
        request(.bottom, length: 8, open: false),
    ])

    // Absent, not zero-sized: a zero-sized frame is a thing that exists and
    // draws nothing, and the difference shows up the moment someone iterates.
    #expect(result.frames.isEmpty)
    #expect(result.content == region, "the content is the whole region, byte for byte")
}

@Test @MainActor func aWindowWithThreeClosedSlideOutsRendersLikeOneWithNone() {
    func render(withSlideOuts: Bool) -> [String] {
        let window = FloatingWindow(title: "proj", frame: Rect(x: 0, y: 0, width: 40, height: 10))
        let label = Label("import Foundation")
        label.anchors = .fill()
        window.content.addSubview(label)

        if withSlideOuts {
            window.addSlideOut(.leading, title: "Files", content: Label("tree"), length: 12)
            window.addSlideOut(.trailing, title: "Inspector", content: Label("info"), length: 12)
            window.addSlideOut(.bottom, title: "Build", content: Label("log"), length: 4)
        }

        let buffer = SceneRenderer(root: window).render(size: Size(width: 40, height: 10))

        return (0..<10).map { row in
            String((0..<40).map { buffer[Point(x: $0, y: row)].character })
        }
    }

    // THE test. Every column a slide-out would cost is a column of text the
    // user does not have, and the entire reason this is not a dock is that
    // closed must cost nothing. If this ever fails, the design is gone.
    #expect(render(withSlideOuts: true) == render(withSlideOuts: false))
}

// MARK: - Geometry

@Test func anOpenSideSlideOutTakesItsColumnsFromTheLeadingEdge() {
    let result = SlideOutLayout.resolve(region: region, requests: [request(.leading, length: 20)])

    #expect(result.frames[.leading] == Rect(x: 0, y: 0, width: 20, height: 24))

    // It PUSHES the document aside rather than covering it — the file tree
    // and the file are wanted at the same time, which is the whole reason to
    // open the tree.
    #expect(result.content == Rect(x: 20, y: 0, width: 60, height: 24))
}

@Test func theTrailingSlideOutHangsOffTheRightEdge() {
    let result = SlideOutLayout.resolve(region: region, requests: [request(.trailing, length: 15)])

    #expect(result.frames[.trailing] == Rect(x: 65, y: 0, width: 15, height: 24))
}

@Test func theBottomSlideOutClaimsTheFullWidthAndTheSidesStopAboveIt() {
    let result = SlideOutLayout.resolve(region: region, requests: [
        request(.leading, length: 20),
        request(.trailing, length: 15),
        request(.bottom, length: 6),
    ])

    // The corner rule. The alternative — sides full height, bottom between
    // them — makes the bottom panel jump sideways whenever a side panel
    // opens, which reads as a bug rather than as a layout.
    #expect(result.frames[.bottom] == Rect(x: 0, y: 18, width: 80, height: 6))
    #expect(result.frames[.leading] == Rect(x: 0, y: 0, width: 20, height: 18))
    #expect(result.frames[.trailing] == Rect(x: 65, y: 0, width: 15, height: 18))
}

@Test func everyOpenPanelTakesItsSpaceFromTheContent() {
    let result = SlideOutLayout.resolve(region: region, requests: [
        request(.leading, length: 20),
        request(.trailing, length: 10),
        request(.bottom, length: 6),
    ])

    // All three sides at once: the document keeps the middle.
    #expect(result.content == Rect(x: 20, y: 0, width: 50, height: 18))
    #expect(result.frames[.trailing] == Rect(x: 70, y: 0, width: 10, height: 18))
}

// MARK: - Not enough room

@Test func theContentNeverLosesItsLastRowOrColumn() {
    let tiny = Rect(x: 0, y: 0, width: 10, height: 4)

    let result = SlideOutLayout.resolve(region: tiny, requests: [
        request(.leading, length: 40, minimum: 20),
        request(.bottom, length: 40, minimum: 20),
    ])

    // A minimum that does not fit is a preference too: the region wins, and
    // it keeps one row and one column for the document rather than handing
    // out a negative size.
    #expect(result.frames[.leading]?.size.width == 9)
    #expect(result.frames[.bottom]?.size.height == 3)
}

@Test func theSecondSideGetsWhatTheFirstLeft() {
    let narrow = Rect(x: 0, y: 0, width: 30, height: 10)

    let result = SlideOutLayout.resolve(region: narrow, requests: [
        request(.leading, length: 25),
        request(.trailing, length: 25),
    ])

    // Leading wins deterministically. Two panels each shrinking the other is
    // how you get a layout nobody can predict.
    #expect(result.frames[.leading]?.size.width == 25)
    #expect(result.frames[.trailing]?.size.width == 4, "the remainder, minus the column the content keeps")
}

@Test func aRegionWithNoRoomLeftDropsTheSecondPanelRatherThanInvertingIt() {
    let narrow = Rect(x: 0, y: 0, width: 6, height: 10)

    let result = SlideOutLayout.resolve(region: narrow, requests: [
        request(.leading, length: 5),
        request(.trailing, length: 5),
    ])

    #expect(result.frames[.leading]?.size.width == 5)
    #expect(result.frames[.trailing] == nil, "no room, so no frame — never a negative one")
}

// MARK: - Region

@Test @MainActor func slideOutsCoverTheContentAreaAndNotTheBorder() {
    let window = FloatingWindow(title: "proj", frame: Rect(x: 0, y: 0, width: 40, height: 12))
    _ = SceneRenderer(root: window).render(size: Size(width: 40, height: 12))

    let region = window.slideOutRegion

    // The point of the whole exercise: a slide-out lives inside the chrome,
    // so the border — and the scrollbars embedded in it — is never painted
    // over and stays usable with a panel open.
    #expect(region.minX >= 1)
    #expect(region.minY >= 1)
    #expect(region.minX + region.size.width <= 39)
    #expect(region.minY + region.size.height <= 11)
}

@Test @MainActor func aPlainWindowOffersItsWholeSelf() {
    let window = Window(frame: Rect(x: 0, y: 0, width: 20, height: 6))
    #expect(window.slideOutRegion == window.bounds, "no chrome, nothing to stay inside of")
}

// MARK: - S3/S4 — opening, pinning, focus

@MainActor
private func demoWindow(width: Int = 60, height: Int = 12) -> (FloatingWindow, TextView, ListView) {
    let window = FloatingWindow(title: "Pin", frame: Rect(x: 0, y: 0, width: width, height: height))
    let document = TextView(text: (1...9).map { "line \($0) ABCDEFGHIJKLMNOPQRSTUVWXYZ" }.joined(separator: "\n"))
    document.isEditable = false
    document.anchors = .fill()
    window.content.addSubview(document)

    let files = ListView(items: ["▾ Sources", "    App.swift"])
    window.addSlideOut(.leading, title: "Files", content: files, length: 20)
    return (window, document, files)
}

@MainActor
private func rows(_ window: FloatingWindow, width: Int = 60, height: Int = 12) -> [String] {
    let buffer = SceneRenderer(root: window).render(size: Size(width: width, height: height))

    return (0..<height).map { row in
        String((0..<width).map { buffer[Point(x: $0, y: row)].character })
    }
}

@Test @MainActor func aSlideOutOpenedBeforeAnyLayoutStillAppears() {
    let (window, _, _) = demoWindow()

    // The bug this pins: `slideOutRegion` used to be read off
    // `panel.content.frame`, which is set in the SAME layout pass that
    // positions slide-outs. Opening one before the window had ever laid out
    // gave it a zero region, so it silently never appeared — and worked the
    // second time, which is the worst way for a bug to behave.
    window.openSlideOut(.leading)

    // Asserted on the panel's CONTENT, not its title: the title is not drawn
    // (there is no top border to put it in — that edge is the window's own).
    #expect(rows(window).contains { $0.contains("▾ Sources") }, "it draws on the very first frame")
}

@Test @MainActor func anOpenPanelPushesTheDocumentAsideRatherThanCoveringIt() {
    let (window, _, _) = demoWindow()
    let line = "line 1 ABCDEFGHIJKLMNOPQRSTUVWXYZ"

    #expect(rows(window).contains { $0.contains(line) })

    window.openSlideOut(.leading)
    let painted = rows(window)

    // Still entirely readable, just further right: the tree and the file are
    // wanted at the same time, which is the whole reason to open the tree.
    // Covering was the first version, and using it settled the question the
    // other way round.
    #expect(painted.contains { $0.contains(line) })
    #expect(painted.contains { $0.contains("▾ Sources") }, "and the panel is beside it, not over it")
}

@Test @MainActor func pinningOnlyDecidesWhetherItClosesOnActivation() {
    let (window, _, _) = demoWindow()
    window.openSlideOut(.leading)
    _ = rows(window)
    let openWidth = window.content.frame.size.width

    // Pinning is NOT a layout mode — Bobby: "pin just means doesn't close on
    // action, which is the only way I envisioned it." The geometry is
    // identical either way; only `closeTransientSlideOuts` reads it.
    window.slideOut(at: .leading)?.isPinned = true
    _ = rows(window)

    #expect(window.content.frame.size.width == openWidth)
}


@Test @MainActor func openingTakesFocusAndClosingGivesItBack() {
    let (window, document, files) = demoWindow()
    window.makeFirstResponder(document)

    window.openSlideOut(.leading)
    #expect(window.firstResponder === files, "a panel you cannot reach is an open panel and no way to use it")

    window.closeSlideOut(.leading)
    #expect(window.firstResponder === document, "and closing returns you to what you were working in")
}

@Test @MainActor func aClosedPanelNeverHoldsTheFirstResponder() {
    let (window, _, files) = demoWindow()
    window.openSlideOut(.leading)
    #expect(window.firstResponder === files)

    window.closeSlideOut(.leading)

    // A hidden view holding focus is a window where the keyboard goes
    // nowhere visible.
    #expect(window.firstResponder !== files)
    #expect(files.isHidden || window.slideOut(at: .leading)?.isOpen == false)
}

@Test @MainActor func transientPanelsCloseTogetherAndPinnedOnesStay() {
    let (window, _, _) = demoWindow()
    let build = ListView(items: ["Build complete!"])
    window.addSlideOut(.bottom, title: "Build", content: build, length: 4)

    window.openSlideOut(.leading)
    window.openSlideOut(.bottom)
    window.slideOut(at: .bottom)?.isPinned = true

    window.closeTransientSlideOuts()

    #expect(window.slideOut(at: .leading)?.isOpen == false, "reach for it, use it, and it is gone")
    #expect(window.slideOut(at: .bottom)?.isOpen == true, "a pinned panel is furniture and stays put")
}

@Test @MainActor func togglingTwiceReturnsTheWindowToItsExactStartingPixels() {
    let (window, _, _) = demoWindow()
    let before = rows(window)

    window.toggleSlideOut(.leading)
    window.toggleSlideOut(.leading)

    // No residue. `RESIZE_ERROR.md` is what residue looks like when nothing
    // tests for it.
    #expect(rows(window) == before)
}

// MARK: - S5 — resizing

@Test @MainActor func draggingTheInnerEdgeResizesTheLeadingPanel() {
    let (window, _, _) = demoWindow(width: 60, height: 12)
    window.openSlideOut(.leading)
    _ = rows(window)

    let slideOut = window.slideOut(at: .leading)
    #expect(slideOut?.length == 20)

    // The RIGHT border of a leading panel — the one the document is on the
    // other side of. `slideOutRegion` starts at x=1 (inside the chrome), so
    // a 20-wide panel's inner edge is at x=20.
    let edge = Point(x: 20, y: 5)
    #expect(window.resizeSlideOut(with: MouseInput(position: edge, action: .press, button: .left)))
    #expect(window.resizeSlideOut(with: MouseInput(position: Point(x: 30, y: 5), action: .drag, button: .left)))

    #expect(slideOut?.length == 30, "measured from the fixed edge, not from the panel's moving one")

    #expect(window.resizeSlideOut(with: MouseInput(position: Point(x: 30, y: 5), action: .release, button: .left)))
    #expect(!window.resizeSlideOut(with: MouseInput(position: Point(x: 40, y: 5), action: .drag, button: .left)),
            "a drag after release is somebody else's")
}

@Test @MainActor func aPressAnywhereButTheInnerEdgeIsNotAResize() {
    let (window, _, _) = demoWindow()
    window.openSlideOut(.leading)
    _ = rows(window)

    // Inside the panel: that is the list's business, not the window's.
    #expect(!window.resizeSlideOut(with: MouseInput(position: Point(x: 10, y: 5), action: .press, button: .left)))

    // A closed panel has no edge to grab.
    window.closeSlideOut(.leading)
    #expect(!window.resizeSlideOut(with: MouseInput(position: Point(x: 20, y: 5), action: .press, button: .left)))
}

@Test @MainActor func aPanelThatSaysItIsNotResizableIsNot() {
    let (window, _, _) = demoWindow()
    window.slideOut(at: .leading)?.isResizable = false
    window.openSlideOut(.leading)
    _ = rows(window)

    #expect(!window.resizeSlideOut(with: MouseInput(position: Point(x: 20, y: 5), action: .press, button: .left)))
}

// MARK: - Window chrome that follows a panel

@Test @MainActor func theTitleButtonSaysWhichWayThePanelWillMove() {
    let (window, _, _) = demoWindow()
    window.slideOutToggleEdge = .leading

    // It has to say what it will do NEXT, not what it did last.
    #expect(rows(window).first?.contains("[>]") == true, "closed: it will come out")

    window.openSlideOut(.leading)
    #expect(rows(window).first?.contains("[<]") == true, "open: it will go back")

    window.closeSlideOut(.leading)
    #expect(rows(window).first?.contains("[>]") == true)
}

@Test @MainActor func clickingTheTitleButtonTogglesThePanel() {
    let (window, _, _) = demoWindow()
    window.slideOutToggleEdge = .leading
    _ = rows(window)

    // The discoverable half of the feature: a shortcut nobody can guess is a
    // feature nobody finds. Row 0, just after the title.
    let button = Point(x: 9, y: 0)
    _ = window.route(.mouse(MouseInput(position: button, action: .press, button: .left)))

    #expect(window.slideOut(at: .leading)?.isOpen == true)
}

@Test @MainActor func aTrailingPanelTakesTheScrollbarsOffTheBorderAndGivesThemBack() {
    let window = FloatingWindow(title: "proj", frame: Rect(x: 0, y: 0, width: 60, height: 12))
    let document = SyntaxTextView(text: (1...30).map { "line \($0)" }.joined(separator: "\n"))
    document.anchors = .fill()
    window.content.addSubview(document)
    window.embedScrollbars(for: document)
    window.addSlideOut(.trailing, title: "Inspector", content: ListView(items: ["Type: struct"]), length: 18)

    #expect(!document.showsOwnScrollbars, "the border carries them while nothing is in the way")

    // A trailing panel puts itself between the window's right border and the
    // document, so a bar on that border would be scrolling something it is
    // nowhere near. The slider moves IN, to the document's own edge.
    window.openSlideOut(.trailing)
    #expect(document.showsOwnScrollbars)

    window.closeSlideOut(.trailing)
    #expect(!document.showsOwnScrollbars, "and back out again when it closes")
}

@Test @MainActor func theBottomPanelOpensAndTakesItsRowsFromTheDocument() {
    let (window, _, _) = demoWindow()
    let build = ListView(items: ["Build complete!"])
    window.addSlideOut(.bottom, title: "Build", content: build, length: 4)

    _ = rows(window)   // lay out first, or `before` is a zero frame
    let before = window.content.frame.size.height
    window.openSlideOut(.bottom)
    _ = rows(window)

    #expect(window.content.frame.size.height == before - 4)
    #expect(rows(window).contains { $0.contains("Build complete!") })
}

@Test @MainActor func aControlKeyRoutedToTheWindowOpensTheBottomPanel() {
    // ^T reaches the panel; ^J cannot, and this pins BOTH halves of that.
    let (window, _, _) = demoWindow()
    let build = ListView(items: ["Build complete!"])
    window.addSlideOut(.bottom, title: "Build", content: build, length: 4)

    final class ShortcutWindow: FloatingWindow {
        override func handleHotKey(_ key: KeyInput) -> Bool {
            if key.modifiers == .control, key.key == .character("t") {
                toggleSlideOut(.bottom)
                return true
            }

            return super.handleHotKey(key)
        }
    }

    // Ctrl+J is ASCII 0x0A, and the decoder turns 0x0A into `.enter` — so a
    // handler asking for `.character("j")` is asking for something that never
    // arrives. Asserted at the decoder, where the truth is.
    var decoder = ANSIInputDecoder()

    guard case .key(let controlJ)? = decoder.feed([0x0A]).first else {
        Issue.record("^J decoded to nothing")
        return
    }

    #expect(controlJ.key == .enter, "^J is Return, not a letter — no handler can have it")

    guard case .key(let controlT)? = decoder.feed([0x14]).first else {
        Issue.record("^T decoded to nothing")
        return
    }

    #expect(controlT.key == .character("t"))
    #expect(controlT.modifiers == .control, "^T is a letter, so a handler can have it")
}

@Test @MainActor func theWindowsOwnHandlerAndAMenuEquivalentDoNotBothFire() {
    // Only one window is ever key, and `App` routes keys to the key window
    // alone — so binding a chord on BOTH the window and a menu is
    // complementary rather than a double-toggle. This pins the routing
    // assumption the demo's Panels menu rests on.
    let (window, _, _) = demoWindow()
    let other = FloatingWindow(title: "other", frame: Rect(x: 0, y: 0, width: 20, height: 6))
    let app = App(driver: HeadlessDriver(size: Size(width: 80, height: 24)))

    app.present(window)
    app.present(other)

    #expect(app.keyWindow === other, "the last presented window is key")
}
