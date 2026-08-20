import Testing
@testable import TUIKit

// Long-press: a left press held still past `App.longPressInterval` becomes a
// `.longPress` — the pressed view gets first refusal, a context menu is the
// fallback, and a consumed long-press swallows the rest of the gesture (no
// activation on release, no debounced `.click`). Driven entirely through the
// app loop with a ManualTimerSource, like the multi-click tests.

// Records the semantic events a view under test receives.
@MainActor
private final class GestureRecorder: TUIView {
    var presses = 0
    var clicks: [Int] = []
    var longPresses = 0

    // Whether the recorder itself claims long-presses (false → the window
    // falls back to the nearest context menu).
    var consumesLongPress = false

    override func mouseEvent(_ mouse: MouseInput) -> Bool {
        switch mouse.action {
        case .press:
            presses += 1
            return true

        case .click:
            clicks.append(mouse.clickCount)
            return true

        case .longPress:
            guard consumesLongPress else {
                return false
            }

            longPresses += 1
            return true

        default:
            return true
        }
    }
}

@MainActor
private func booted(
    size: Size = Size(width: 30, height: 8)
) async throws -> (HeadlessDriver, ManualTimerSource, App, Window, Task<Void, Error>) {
    let driver = HeadlessDriver(size: size)
    let clock = ManualTimerSource()
    let app = App(driver: driver, timerSource: clock)
    let window = Window(frame: Rect(origin: .zero, size: size))

    let session = Task { try await app.run(window) }
    while await driver.presentCount == 0 {
        await Task.yield()
    }

    return (driver, clock, app, window, session)
}

@Test @MainActor func aHeldButtonFiresOnLongPressAndItsReleaseDoesNotActivate() async throws {
    let (driver, clock, _, window, session) = try await booted()

    var activations = 0
    var longPresses = 0
    let button = Button("Back") { activations += 1 }
    button.onLongPress = { longPresses += 1 }
    button.frame = Rect(x: 2, y: 2, width: 8, height: 1)
    window.addSubview(button)

    let spot = Point(x: 4, y: 2)

    // Hold: press, let the long-press clock fire while the button is down.
    await driver.send(.mouse(MouseInput(position: spot, action: .press, button: .left)))
    while await clock.streamCount < 1 {
        await Task.yield()
    }
    #expect(button.isPressed, "the face is down while held")

    clock.fire()
    while longPresses == 0 {
        await Task.yield()
    }
    #expect(longPresses == 1)
    #expect(!button.isPressed, "the gesture was taken: the face pops back up")

    // The release that ends the hold is inert — no activation, and no
    // debounced click either.
    await driver.send(.mouse(MouseInput(position: spot, action: .release, button: .left)))
    clock.fire()
    await Task.yield()
    #expect(activations == 0, "a long-press swallows the click half of the gesture")

    // A normal quick click on the same button still works.
    await driver.send(.mouse(MouseInput(position: spot, action: .press, button: .left)))
    await driver.send(.mouse(MouseInput(position: spot, action: .release, button: .left)))
    while activations == 0 {
        await Task.yield()
    }
    #expect(activations == 1)
    #expect(longPresses == 1, "the quick click did not long-press")

    await driver.send(.key(KeyInput(key: .character("c"), modifiers: .control)))
    try await session.value
}

@Test @MainActor func anUnhandledLongPressOpensTheNearestContextMenuAndSuppressesTheClick() async throws {
    let (driver, clock, _, window, session) = try await booted()

    let recorder = GestureRecorder(frame: Rect(x: 0, y: 0, width: 30, height: 8))
    recorder.consumesLongPress = false
    let menu = Menu("")
    menu.addItem("History") {}
    recorder.contextMenu = menu
    window.addSubview(recorder)

    let spot = Point(x: 5, y: 3)
    await driver.send(.mouse(MouseInput(position: spot, action: .press, button: .left)))
    while await clock.streamCount < 1 {
        await Task.yield()
    }

    let presented = await driver.presentCount
    clock.fire()
    while await driver.presentCount == presented {
        await Task.yield()
    }

    // The fallback: the view declined, so its context menu opened at the
    // pointer — the same menu a right-click would show.
    #expect(await driver.snapshotText().contains { $0.contains("History") })

    // And the click half of the gesture is gone: release + settled guard
    // deliver no `.click`.
    await driver.send(.mouse(MouseInput(position: spot, action: .release, button: .left)))
    clock.fire()
    await Task.yield()
    #expect(recorder.clicks.isEmpty, "the long-press consumed the gesture")

    await driver.send(.key(KeyInput(key: .character("c"), modifiers: .control)))
    try await session.value
}

@Test @MainActor func aDragPastTheSlopIsNotAHold() async throws {
    let (driver, clock, _, window, session) = try await booted()

    let recorder = GestureRecorder(frame: Rect(x: 0, y: 0, width: 30, height: 8))
    recorder.consumesLongPress = true
    window.addSubview(recorder)

    await driver.send(.mouse(MouseInput(position: Point(x: 5, y: 3), action: .press, button: .left)))
    while await clock.streamCount < 1 {
        await Task.yield()
    }

    // Moving four cells is a drag; the long-press clock is abandoned, so its
    // tick delivers nothing.
    await driver.send(.mouse(MouseInput(position: Point(x: 9, y: 3), action: .drag, button: .left)))
    while recorder.presses == 0 {
        await Task.yield()
    }
    clock.fire()
    await Task.yield()
    #expect(recorder.longPresses == 0, "a drag is not a hold")

    await driver.send(.key(KeyInput(key: .character("c"), modifiers: .control)))
    try await session.value
}

@Test @MainActor func anUnconsumedHoldRemainsASlowClick() async throws {
    let (driver, clock, _, window, session) = try await booted()

    // No long-press handler, no context menu: holding must change nothing —
    // the release still clicks, exactly as before long-press existed.
    let recorder = GestureRecorder(frame: Rect(x: 0, y: 0, width: 30, height: 8))
    recorder.consumesLongPress = false
    window.addSubview(recorder)

    let spot = Point(x: 5, y: 3)
    await driver.send(.mouse(MouseInput(position: spot, action: .press, button: .left)))
    while await clock.streamCount < 1 {
        await Task.yield()
    }
    clock.fire()   // long-press fires, nobody wants it
    await Task.yield()

    await driver.send(.mouse(MouseInput(position: spot, action: .release, button: .left)))
    while await clock.streamCount < 2 {
        await Task.yield()
    }
    clock.fire()   // the multi-click guard settles
    while recorder.clicks.isEmpty {
        await Task.yield()
    }
    #expect(recorder.clicks == [1], "a hold nothing reacted to is just a slow click")

    await driver.send(.key(KeyInput(key: .character("c"), modifiers: .control)))
    try await session.value
}

@Test @MainActor func aHoldMidClickSequenceIsNotALongPress() async throws {
    // The multi-click guard's promise — a click still under the finger is
    // not a gesture yet — outranks the hold: only a FRESH press can become
    // a long-press, so a slow double-click stays a double-click even over a
    // view that would consume long-presses.
    let (driver, clock, _, window, session) = try await booted()

    let recorder = GestureRecorder(frame: Rect(x: 0, y: 0, width: 30, height: 8))
    recorder.consumesLongPress = true
    window.addSubview(recorder)

    let spot = Point(x: 5, y: 3)

    // Click one completes; click two goes down and HOLDS past the interval.
    await driver.send(.mouse(MouseInput(position: spot, action: .press, button: .left)))
    await driver.send(.mouse(MouseInput(position: spot, action: .release, button: .left)))
    await driver.send(.mouse(MouseInput(position: spot, action: .press, button: .left)))
    while recorder.presses < 2 {
        await Task.yield()
    }

    clock.fire()
    await Task.yield()
    #expect(recorder.longPresses == 0, "a hold mid-sequence is a slow click, not a long-press")

    // The sequence completes as the double it always was.
    await driver.send(.mouse(MouseInput(position: spot, action: .release, button: .left)))
    while await clock.streamCount < 3 {
        await Task.yield()
    }
    clock.fire()
    while recorder.clicks.isEmpty {
        await Task.yield()
    }
    #expect(recorder.clicks == [2])

    await driver.send(.key(KeyInput(key: .character("c"), modifiers: .control)))
    try await session.value
}

@Test @MainActor func aToolbarItemWithALongPressActionClicksOnReleaseAndHoldsForTheAlternate() async throws {
    let (driver, clock, _, window, session) = try await booted()

    var back = 0
    var history = 0
    var forward = 0

    let bar = Toolbar()
    bar.frame = Rect(x: 0, y: 0, width: 30, height: 1)
    let backItem = bar.addItem("Back") { back += 1 }
    backItem.longPressAction = { history += 1 }
    bar.addItem("Fwd") { forward += 1 }
    window.addSubview(bar)

    // The Back segment starts the row; press lands inside it.
    let backSpot = Point(x: 2, y: 0)

    // A quick click: the item has a long-press action, so it activates on
    // RELEASE (it cannot know which gesture it is at press time).
    await driver.send(.mouse(MouseInput(position: backSpot, action: .press, button: .left)))
    while await clock.streamCount < 1 {
        await Task.yield()
    }
    #expect(back == 0, "not yet — the press might become a hold")

    await driver.send(.mouse(MouseInput(position: backSpot, action: .release, button: .left)))
    while back == 0 {
        await Task.yield()
    }
    #expect(back == 1)
    #expect(history == 0)

    // Let the click's guard settle: a hold reads as a long-press only on a
    // FRESH press, never mid-click-sequence. (Wait for the guard's stream —
    // press armed the long-press stream first, so it is the second.)
    while await clock.streamCount < 2 {
        await Task.yield()
    }
    clock.fire()
    await Task.yield()

    // A hold: the long-press fires the alternate, and the release is inert.
    await driver.send(.mouse(MouseInput(position: backSpot, action: .press, button: .left)))
    while await clock.streamCount < 3 {
        await Task.yield()
    }
    clock.fire()
    while history == 0 {
        await Task.yield()
    }
    await driver.send(.mouse(MouseInput(position: backSpot, action: .release, button: .left)))
    clock.fire()
    await Task.yield()
    #expect(back == 1, "the hold's release does not also click Back")
    #expect(history == 1)

    // An item WITHOUT a long-press action keeps the old contract: it
    // activates the moment it is pressed.
    let row = await driver.snapshotText()[0]
    let fwdColumn = row.distance(from: row.startIndex, to: row.range(of: "Fwd")!.lowerBound)
    await driver.send(.mouse(MouseInput(position: Point(x: fwdColumn, y: 0), action: .press, button: .left)))
    while forward == 0 {
        await Task.yield()
    }
    #expect(forward == 1, "no long-press action → press activates immediately")
    await driver.send(.mouse(MouseInput(position: Point(x: fwdColumn, y: 0), action: .release, button: .left)))

    await driver.send(.key(KeyInput(key: .character("c"), modifiers: .control)))
    try await session.value
}
