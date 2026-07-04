import Testing
@testable import TUIKit

// MARK: - Test Views

/// Focusable view that records everything routed to it.
@MainActor
private final class RecordingView: TUIView {
    var accepts = true
    var handlesKeys = false
    var handlesHotKeys = false
    var handlesColdKeys = false
    var handlesMouse = false

    private(set) var keys: [KeyInput] = []
    private(set) var hotKeys: [KeyInput] = []
    private(set) var coldKeys: [KeyInput] = []
    private(set) var mice: [MouseInput] = []
    private(set) var becameFocused = 0
    private(set) var resignedFocus = 0

    override var acceptsFirstResponder: Bool { accepts }

    override func didBecomeFirstResponder() { becameFocused += 1 }
    override func didResignFirstResponder() { resignedFocus += 1 }

    override func keyDown(_ key: KeyInput) -> Bool {
        keys.append(key)
        return handlesKeys
    }

    override func handleHotKey(_ key: KeyInput) -> Bool {
        hotKeys.append(key)
        return handlesHotKeys
    }

    override func handleColdKey(_ key: KeyInput) -> Bool {
        coldKeys.append(key)
        return handlesColdKeys
    }

    override func mouseEvent(_ mouse: MouseInput) -> Bool {
        mice.append(mouse)
        return handlesMouse
    }
}

private func key(_ character: Character, modifiers: KeyModifiers = []) -> KeyInput {
    KeyInput(key: .character(character), modifiers: modifiers)
}

@MainActor
private func makeWindowWithTwoFields() -> (Window, RecordingView, RecordingView) {
    let window = Window(frame: Rect(x: 0, y: 0, width: 20, height: 6))
    let first = RecordingView(frame: Rect(x: 1, y: 1, width: 5, height: 1))
    let second = RecordingView(frame: Rect(x: 1, y: 3, width: 5, height: 1))

    window.addSubview(first)
    window.addSubview(second)

    return (window, first, second)
}

// MARK: - Focus

@Test @MainActor func makeFirstResponderMovesFocusAndFiresHooks() {
    let (window, first, second) = makeWindowWithTwoFields()

    #expect(window.makeFirstResponder(first))
    #expect(first.isFirstResponder)
    #expect(first.becameFocused == 1)

    #expect(window.makeFirstResponder(second))
    #expect(!first.isFirstResponder)
    #expect(first.resignedFocus == 1)
    #expect(second.isFirstResponder)
}

@Test @MainActor func refusingViewsCannotBecomeFirstResponder() {
    let (window, first, _) = makeWindowWithTwoFields()
    first.accepts = false

    #expect(!window.makeFirstResponder(first))
    #expect(window.firstResponder == nil)
}

@Test @MainActor func outsideViewsCannotBecomeFirstResponder() {
    let (window, _, _) = makeWindowWithTwoFields()
    let stranger = RecordingView()

    #expect(!window.makeFirstResponder(stranger))
}

@Test @MainActor func tabCyclesFocusInDepthFirstOrderWithWraparound() {
    let (window, first, second) = makeWindowWithTwoFields()
    let tab = TerminalInput.key(KeyInput(key: .tab))

    window.route(tab)
    #expect(window.firstResponder === first)

    window.route(tab)
    #expect(window.firstResponder === second)

    window.route(tab)
    #expect(window.firstResponder === first)
}

@Test @MainActor func shiftTabCyclesBackward() {
    let (window, first, second) = makeWindowWithTwoFields()

    window.route(.key(KeyInput(key: .tab, modifiers: .shift)))
    #expect(window.firstResponder === second)

    window.route(.key(KeyInput(key: .tab, modifiers: .shift)))
    #expect(window.firstResponder === first)
}

@Test @MainActor func hiddenViewsAreSkippedInTabOrder() {
    let (window, first, second) = makeWindowWithTwoFields()
    first.isHidden = true

    window.route(.key(KeyInput(key: .tab)))

    #expect(window.firstResponder === second)
}

// MARK: - Key Routing

@Test @MainActor func focusedViewReceivesKeys() {
    let (window, first, second) = makeWindowWithTwoFields()
    first.handlesKeys = true
    window.makeFirstResponder(first)

    #expect(window.route(.key(key("a"))))
    #expect(first.keys == [key("a")])
    #expect(second.keys.isEmpty)
}

@Test @MainActor func unhandledKeysBubbleToSuperview() {
    let window = Window(frame: Rect(x: 0, y: 0, width: 10, height: 4))
    let panel = RecordingView(frame: Rect(x: 0, y: 0, width: 10, height: 4))
    let field = RecordingView(frame: Rect(x: 1, y: 1, width: 4, height: 1))

    panel.accepts = false
    panel.handlesKeys = true
    window.addSubview(panel)
    panel.addSubview(field)
    window.makeFirstResponder(field)

    #expect(window.route(.key(key("x"))))
    #expect(field.keys == [key("x")])
    #expect(panel.keys == [key("x")])
}

@Test @MainActor func hotKeysInterceptBeforeTheFocusedView() {
    let (window, first, second) = makeWindowWithTwoFields()
    second.handlesHotKeys = true
    first.handlesKeys = true
    window.makeFirstResponder(first)

    #expect(window.route(.key(key("q"))))
    #expect(second.hotKeys == [key("q")])
    #expect(first.keys.isEmpty, "hot key must never reach the focused view")
}

@Test @MainActor func coldKeysCatchWhatNothingElseWanted() {
    let (window, first, second) = makeWindowWithTwoFields()
    second.handlesColdKeys = true
    window.makeFirstResponder(first)

    #expect(window.route(.key(key("z"))))
    #expect(first.keys == [key("z")], "focused view saw and declined it")
    #expect(second.coldKeys == [key("z")])
}

@Test @MainActor func focusedViewCanConsumeTabItself() {
    let (window, first, second) = makeWindowWithTwoFields()
    first.handlesKeys = true
    window.makeFirstResponder(first)

    window.route(.key(KeyInput(key: .tab)))

    #expect(window.firstResponder === first, "handled tab must not move focus")
    #expect(second.keys.isEmpty)
}

// MARK: - Mouse Routing

@Test @MainActor func mouseHitsDeepestViewInLocalCoordinates() {
    let window = Window(frame: Rect(x: 0, y: 0, width: 20, height: 8))
    let panel = RecordingView(frame: Rect(x: 2, y: 1, width: 10, height: 5))
    let field = RecordingView(frame: Rect(x: 3, y: 2, width: 4, height: 1))

    panel.accepts = false
    field.handlesMouse = true
    window.addSubview(panel)
    panel.addSubview(field)

    // Screen (6, 3) inside window = window-local (6, 3); panel-local (4, 2);
    // field-local (1, 0).
    let click = MouseInput(position: Point(x: 6, y: 3), action: .press, button: .left)

    #expect(window.route(.mouse(click)))
    #expect(field.mice.first?.position == Point(x: 1, y: 0))
    #expect(panel.mice.isEmpty)
}

@Test @MainActor func unhandledMouseBubblesWithTranslatedCoordinates() {
    let window = Window(frame: Rect(x: 0, y: 0, width: 20, height: 8))
    let panel = RecordingView(frame: Rect(x: 2, y: 1, width: 10, height: 5))
    let field = RecordingView(frame: Rect(x: 3, y: 2, width: 4, height: 1))

    panel.accepts = false
    panel.handlesMouse = true
    window.addSubview(panel)
    panel.addSubview(field)

    let click = MouseInput(position: Point(x: 6, y: 3), action: .press, button: .left)
    window.route(.mouse(click))

    #expect(field.mice.first?.position == Point(x: 1, y: 0))
    #expect(panel.mice.first?.position == Point(x: 4, y: 2))
}

@Test @MainActor func clickFocusesTheHitView() {
    let (window, first, _) = makeWindowWithTwoFields()

    let click = MouseInput(position: Point(x: 2, y: 1), action: .press, button: .left)
    window.route(.mouse(click))

    #expect(window.firstResponder === first)
}

@Test @MainActor func clickOutsideTheWindowIsRejected() {
    let (window, _, _) = makeWindowWithTwoFields()

    let outside = MouseInput(position: Point(x: 50, y: 50), action: .press, button: .left)

    #expect(!window.route(.mouse(outside)))
}
