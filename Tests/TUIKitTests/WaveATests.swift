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
