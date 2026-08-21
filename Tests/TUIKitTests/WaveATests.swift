import Testing
@testable import TUIKit

// Phase 16 Wave A — the control-parity fill, small controls first. Every
// behaviour here is proven through the headless renderer and the window's
// own routing, never by hand.

@MainActor
private func host(_ view: TUIView, width: Int, height: Int = 1) -> Window {
    let window = Window(frame: Rect(x: 0, y: 0, width: width, height: height))
    view.frame = Rect(x: 0, y: 0, width: width, height: height)
    window.addSubview(view)
    return window
}

@MainActor
private func lines(_ window: Window) -> [String] {
    SceneRenderer(root: window).render(size: window.frame.size).textLines()
}

@MainActor
private func buffer(_ window: Window) -> CellBuffer {
    SceneRenderer(root: window).render(size: window.frame.size)
}

private func key(_ key: Key, _ modifiers: KeyModifiers = []) -> TerminalInput {
    .key(KeyInput(key: key, modifiers: modifiers))
}

@MainActor
private func click(_ window: Window, x: Int, y: Int = 0) {
    window.route(.mouse(MouseInput(position: Point(x: x, y: y), action: .press, button: .left, modifiers: [])))
    window.route(.mouse(MouseInput(position: Point(x: x, y: y), action: .release, button: .left, modifiers: [])))
}

// MARK: - SearchField (16.2)

@Test @MainActor func searchFieldShowsTheMagnifierAndPlaceholder() {
    let search = SearchField()
    let window = host(search, width: 20)

    #expect(lines(window)[0].hasPrefix("⌕ Search"))
}

@Test @MainActor func searchFieldReportsLiveAndEscapeClears() {
    let search = SearchField()
    let window = host(search, width: 20)
    var reports: [String] = []
    search.onSearch = { reports.append($0) }

    window.makeFirstResponder(search)   // lands on the field inside
    #expect(window.firstResponder === search.field)

    window.route(key(.character("a")))
    window.route(key(.character("b")))
    #expect(reports == ["a", "ab"], "live: every change reports")
    #expect(lines(window)[0].hasSuffix("✕"), "a clear glyph once there is text")

    window.route(key(.escape))
    #expect(search.text.isEmpty)
    #expect(reports.last == "", "Esc reports the empty search")
    #expect(!lines(window)[0].contains("✕"))
}

@Test @MainActor func searchFieldClearGlyphClearsByMouseAndReturnCommits() {
    let search = SearchField()
    let window = host(search, width: 20)
    var committed: [String] = []
    search.onCommit = { committed.append($0) }

    window.makeFirstResponder(search)
    window.route(key(.character("q")))
    window.route(key(.enter))
    #expect(committed == ["q"])

    click(window, x: 19)
    #expect(search.text.isEmpty, "clicking ✕ clears")
}

@Test @MainActor func searchFieldDebounceWaitsForQuietThenReportsOnce() {
    let search = SearchField()
    let window = host(search, width: 20)
    var reports: [String] = []
    search.onSearch = { reports.append($0) }

    // A hand-cranked scheduler: we decide when the quiet period "elapses".
    var pending: [@MainActor () -> Void] = []
    var cancelled = 0
    search.scheduleDebounce = { _, body in
        pending.append(body)
        return { cancelled += 1 }
    }
    search.debounce = .milliseconds(100)

    window.makeFirstResponder(search)
    window.route(key(.character("a")))
    window.route(key(.character("b")))

    #expect(reports.isEmpty, "nothing reports while keys keep coming")
    #expect(cancelled == 1, "the second keystroke cancelled the first wait")
    #expect(pending.count == 2)

    pending.last?()
    #expect(reports == ["ab"], "quiet: one report, the latest query")
}

// MARK: - Link (16.7)

@Test @MainActor func linkRendersUnderlinedAndOpensOnEnterOrClick() {
    let link = Link("Docs", url: "https://example.com/docs")
    let window = host(link, width: 10)
    var opened: [String] = []
    link.onOpen = { opened.append($0) }

    #expect(lines(window)[0].hasPrefix("Docs"))
    #expect(buffer(window)[Point(x: 0, y: 0)].style.flags.contains(.underline))

    window.makeFirstResponder(link)
    window.route(key(.enter))
    click(window, x: 1)
    #expect(opened == ["https://example.com/docs", "https://example.com/docs"])
}

@Test @MainActor func helpLinkIsTheRoundButtonOpeningAnAnchor() {
    let help = Link.help(anchor: "themes", baseURL: "https://example.com/help#")
    let window = host(help, width: 5)
    var opened: [String] = []
    help.onOpen = { opened.append($0) }

    #expect(lines(window)[0].hasPrefix("(?)"))
    #expect(help.intrinsicContentSize == Size(width: 3, height: 1))

    window.makeFirstResponder(help)
    window.route(key(.character(" ")))
    #expect(opened == ["https://example.com/help#themes"])
}

// MARK: - PasteButton (16.10)

@Test @MainActor func pasteButtonHandsOverTheAppPasteboardOrReportsEmpty() {
    let app = App(driver: HeadlessDriver(size: Size(width: 20, height: 1)))
    var pasted: [String] = []
    var empties = 0
    let paste = PasteButton { pasted.append($0) }
    paste.onEmpty = { empties += 1 }

    let window = host(paste, width: 12)
    window.app = app
    window.makeFirstResponder(paste)
    #expect(window.firstResponder === paste.button)

    window.route(key(.enter))
    #expect(empties == 1 && pasted.isEmpty, "an empty board reports empty")

    app.pasteboard.copy("hello")
    window.route(key(.enter))
    #expect(pasted == ["hello"])
}

// MARK: - Slider ticks + RangeSlider (16.3)

@Test @MainActor func sliderTicksDrawAndSnapAndArrowsWalkThem() {
    let slider = Slider(value: 0, in: 0...100)
    slider.tickMarks = 5
    let window = host(slider, width: 22)

    // Five ticks at 0/25/50/75/100; the handle covers the one it rests on.
    #expect(lines(window)[0].filter { $0 == "┼" }.count == 4)

    slider.snapsToTicks = true
    slider.setValue(30)
    #expect(slider.value == 25, "programmatic values snap to the nearest tick")

    window.makeFirstResponder(slider)
    window.route(key(.right))
    #expect(slider.value == 50, "arrows walk tick to tick, not by step")
    window.route(key(.left))
    window.route(key(.left))
    #expect(slider.value == 0)
}

@Test @MainActor func rangeSliderMovesTheActiveThumbAndKeepsTheGap() {
    let slider = RangeSlider(lower: 20, upper: 60, in: 0...100, minimumGap: 10)
    let window = host(slider, width: 22)
    var spans: [ClosedRange<Int>] = []
    slider.onValuesChanged = { spans.append($0) }

    #expect(lines(window)[0].filter { $0 == "█" }.count == 2)
    #expect(lines(window)[0].contains("━"), "the span between the thumbs is drawn")

    window.makeFirstResponder(slider)
    window.route(key(.right))
    #expect(slider.values == 21...60)

    window.route(key(.character(" ")))   // switch to the upper thumb
    window.route(key(.left))
    #expect(slider.values == 21...59)
    #expect(spans.count == 2)

    slider.setValues(55...60)
    #expect(slider.values == 55...65, "the upper value yields to keep the gap")

    window.route(key(.home))   // upper thumb: as low as the gap allows — already there
    #expect(slider.values == 55...65)
    #expect(spans.count == 2, "no change, no report")
}

@Test @MainActor func rangeSliderMouseGrabsTheNearestThumb() {
    let slider = RangeSlider(lower: 20, upper: 80, in: 0...100)
    let window = host(slider, width: 22)
    window.makeFirstResponder(slider)

    click(window, x: 19)   // near the right end → the upper thumb moves
    #expect(slider.activeThumb == .upper)
    #expect(slider.upperValue > 90 && slider.lowerValue == 20)

    click(window, x: 2)    // near the left → the lower thumb
    #expect(slider.activeThumb == .lower)
    #expect(slider.lowerValue < 10)
}

// MARK: - StatusBar flash + priority (16.8)

@Test @MainActor func statusBarFlashOwnsTheRowThenRestoresTheSegments() {
    let bar = StatusBar()
    bar.addSegment(Label("Ready"), percentage: 100)
    bar.addSegment(Label("UTF-8"))
    let window = host(bar, width: 30)

    var expire: (@MainActor () -> Void)?
    bar.scheduleFlash = { _, body in
        expire = body
        return {}
    }

    #expect(lines(window)[0].contains("Ready") && lines(window)[0].contains("UTF-8"))

    bar.flash("Saved 3 files")
    let flashed = lines(window)[0]
    #expect(flashed.contains("Saved 3 files"))
    #expect(!flashed.contains("Ready") && !flashed.contains("UTF-8"), "segments step aside")
    #expect(bar.flashText == "Saved 3 files")

    expire?()
    #expect(bar.flashText == nil)
    #expect(lines(window)[0].contains("Ready") && lines(window)[0].contains("UTF-8"), "and come back")
}

@Test @MainActor func statusBarLowestPriorityGivesWayFirstWhenNarrow() {
    let bar = StatusBar()
    bar.showsSeparators = false
    let keep = bar.addSegment(Label("KEEPME"), minimumWidth: 6, priority: 1)
    let drop = bar.addSegment(Label("DROPME"), minimumWidth: 6, priority: 0)
    let window = host(bar, width: 8)
    _ = lines(window)

    #expect(keep.content.frame.size.width == 6, "the higher priority keeps its width")
    #expect(drop.content.frame.size.width == 2, "the lower one takes the whole deficit")
}

// MARK: - ViewThatFits (16.4)

@Test @MainActor func viewThatFitsShowsTheFirstCandidateThatFits() {
    let fits = ViewThatFits(axis: .horizontal, candidates: [
        Label("Save the document to disk"),   // 25
        Label("Save document"),               // 13
        Label("Save"),                        // 4
    ])
    var choices: [Int] = []
    fits.onChoiceChanged = { choices.append($0) }

    let wide = host(fits, width: 30)
    #expect(lines(wide)[0].hasPrefix("Save the document to disk"))

    fits.frame = Rect(x: 0, y: 0, width: 20, height: 1)
    wide.frame = Rect(x: 0, y: 0, width: 20, height: 1)
    #expect(lines(wide)[0].hasPrefix("Save document"))
    #expect(!lines(wide)[0].contains("disk"))

    fits.frame = Rect(x: 0, y: 0, width: 6, height: 1)
    wide.frame = Rect(x: 0, y: 0, width: 6, height: 1)
    #expect(lines(wide)[0].hasPrefix("Save"))
    #expect(choices == [0, 1, 2], "each switch is reported once")
}

// MARK: - PageView (16.5)

@Test @MainActor func pageViewShowsOnePageAndArrowsDotsAndKeysTurnIt() {
    let pages = PageView(pages: [Label("one"), Label("two"), Label("three")])
    let window = host(pages, width: 20, height: 3)
    var turned: [Int] = []
    pages.onPageChanged = { turned.append($0) }

    var text = lines(window)
    #expect(text[0].hasPrefix("one") && !text[0].contains("two"))
    #expect(text[2].hasPrefix("◂") && text[2].hasSuffix("▸"))
    #expect(text[2].contains("● ○ ○"))

    window.makeFirstResponder(pages)
    window.route(key(.right))
    text = lines(window)
    #expect(text[0].hasPrefix("two") && text[2].contains("○ ● ○"))

    click(window, x: 19, y: 2)   // the ▸ arrow
    #expect(pages.currentIndex == 2)
    #expect(!pages.next(), "no page past the last")

    click(window, x: 7, y: 2)    // the first dot
    #expect(pages.currentIndex == 0)
    #expect(turned == [1, 2, 0])
}

// MARK: - Accordion (16.6)

@Test @MainActor func accordionExclusiveOpensOneSectionAndGivesItTheSpace() {
    let accordion = Accordion(mode: .exclusive)
    let a = accordion.addSection("General", content: Label("general body"), isExpanded: true)
    let b = accordion.addSection("Appearance", content: Label("appearance body"))
    accordion.addSection("Advanced", content: Label("advanced body"))
    let window = host(accordion, width: 30, height: 9)
    var changes: [String] = []
    accordion.onSectionChanged = { changes.append("\($0):\($1)") }

    var text = lines(window)
    #expect(text[0].hasPrefix("▾ General") && text[1].contains("general body"))
    #expect(a.frame.size.height == 7, "the open section takes the rows left after three headers")

    window.makeFirstResponder(b)
    window.route(key(.character(" ")))   // open Appearance → General closes
    text = lines(window)
    #expect(text[0].hasPrefix("▸ General") && text[1].hasPrefix("▾ Appearance"))
    #expect(!a.isExpanded && b.isExpanded)
    #expect(changes == ["1:true"])
    #expect(b.frame.size.height == 7 && a.frame.size.height == 1)
}

@Test @MainActor func accordionSharedSplitsTheSpaceBetweenOpenSections() {
    let accordion = Accordion(mode: .shared)
    let a = accordion.addSection("One", content: Label("1"), isExpanded: true)
    let b = accordion.addSection("Two", content: Label("2"), isExpanded: true)
    accordion.addSection("Three", content: Label("3"))
    let window = host(accordion, width: 20, height: 11)
    _ = lines(window)

    // 11 rows - 3 headers = 8 left, 4 each.
    #expect(a.isExpanded && b.isExpanded)
    #expect(a.frame.size.height == 5 && b.frame.size.height == 5)
}

// MARK: - Navigator (16.1)

@Test @MainActor func navigatorPushesPopsAndKeepsTheHeaderHonest() {
    let navigator = Navigator(root: Label("root body"), title: "Settings")
    let window = host(navigator, width: 30, height: 4)
    var depths: [Int] = []
    navigator.onDepthChanged = { depths.append($0) }

    var text = lines(window)
    #expect(text[0].contains("Settings") && !text[0].contains("Back"), "the root has nothing to go back to")
    #expect(text[1].hasPrefix("root body"))
    #expect(!navigator.pop(), "nothing to pop at the root")

    navigator.push(Label("second body"), title: "Second")
    text = lines(window)
    #expect(text[0].contains("◂ Back") && text[0].contains("Second"))
    #expect(text[1].hasPrefix("second body") && !text[1].contains("root"))
    #expect(navigator.depth == 2)

    window.route(key(.escape))   // bubbles up from the header, which is focused
    text = lines(window)
    #expect(navigator.depth == 1 && text[1].hasPrefix("root body"))

    navigator.push(Label("third"), title: "Third")
    click(window, x: 2, y: 0)    // on "◂ Back"
    #expect(navigator.depth == 1)
    #expect(depths == [2, 1, 2, 1])
}

@Test @MainActor func navigatorMovesFocusOntoThePushedView() {
    let navigator = Navigator(root: Label("root"), title: "Root")
    let window = host(navigator, width: 30, height: 4)
    let field = TextField(placeholder: "name")

    navigator.push(field, title: "Name")
    #expect(window.firstResponder === field)

    navigator.popToRoot()
    #expect(navigator.depth == 1)
    #expect(window.firstResponder !== field, "a popped view keeps no focus")
}

// MARK: - Canvas (16.9)

@Test @MainActor func canvasWithOnlyChromeShowsAnHonestPlaceholderOnPlainTerminals() {
    let canvas = Canvas(chrome: { chrome, bounds in
        chrome.rect("backing", ChromeRect(bounds), fill: ChromeColor(red: 10, green: 20, blue: 30))
    })
    let window = host(canvas, width: 30, height: 5)
    let text = lines(window)

    #expect(text.joined().contains("VTG graphics required"))
    #expect(text[0].hasPrefix("┌") || text[0].hasPrefix("╔") || text[0].hasPrefix("╭"), "framed, not a blank")
}

@Test @MainActor func canvasDrawsChromeWhenTheTerminalHasItAndCellsAlways() {
    var cellDraws = 0
    let canvas = Canvas(
        cells: { painter, _ in
            cellDraws += 1
            painter.write("42%", at: Point(x: 1, y: 1))
        },
        chrome: { chrome, bounds in
            chrome.circle("dial", center: ChromePoint(x: 5, y: 2.5), radius: 2, fill: ChromeColor(red: 1, green: 2, blue: 3))
        }
    )
    canvas.frame = Rect(x: 0, y: 0, width: 20, height: 5)

    // Plain terminal: cells only, no placeholder (there IS a cell drawing).
    let plain = SceneRenderer(root: canvas)
    let plainText = plain.render(size: Size(width: 20, height: 5)).textLines()
    #expect(plainText[1].contains("42%") && !plainText.joined().contains("VTG"))

    // VectorTerminal: the chrome closure runs, cells draw over it.
    let vector = SceneRenderer(root: canvas)
    vector.chromeEnabled = true
    let vectorText = vector.render(size: Size(width: 20, height: 5)).textLines()
    #expect(vectorText[1].contains("42%"))
    #expect(vector.chromeCommands.contains { $0.id.hasSuffix("_dial") })
    #expect(cellDraws == 2)
}
