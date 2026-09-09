import Foundation
import Testing
@testable import TUIKit

// PLAN Phase 11.5 — hover help.
//
// ActiveUI carries a `tooltip` property on every view and, until this landed,
// its terminal arm was an empty `#if` — set, accepted, and silently dropped.
// Ground rule 5 says nothing ships silently, so the property needed either a
// real implementation or a visible band. This is the implementation.

@MainActor
private func window(width: Int = 30, height: Int = 10) -> Window {
    Window(frame: Rect(x: 0, y: 0, width: width, height: height))
}

@Test @MainActor func helpTextIsFoundOnTheViewUnderThePointer() {
    let root = window()
    let button = Button("Save") {}
    button.frame = Rect(x: 2, y: 2, width: 8, height: 1)
    button.toolTip = "Write the file to disk"
    root.addSubview(button)

    #expect(root.viewWithToolTip(at: Point(x: 4, y: 2)) === button)
    #expect(root.viewWithToolTip(at: Point(x: 20, y: 8)) == nil,
            "empty space has nothing to say")
}

@Test @MainActor func helpTextIsInheritedFromAnAncestor() {
    // The case it exists for: a row of unlabelled glyph buttons, described
    // once on the row rather than once per button.
    let root = window()
    let row = StackView(axis: .horizontal, spacing: 1)
    row.frame = Rect(x: 0, y: 0, width: 20, height: 1)
    row.toolTip = "Formatting"
    let bold = Button("B") {}
    bold.frame = Rect(x: 0, y: 0, width: 3, height: 1)
    row.addSubview(bold)
    root.addSubview(row)

    #expect(root.viewWithToolTip(at: Point(x: 1, y: 0)) === row,
            "the button has none of its own, so the row answers")
}

@Test @MainActor func aTooltipNeverTakesTheKeyboard() {
    let root = window()
    let field = TextField()
    field.frame = Rect(x: 0, y: 0, width: 10, height: 1)
    root.addSubview(field)
    root.makeFirstResponder(field)

    root.showTooltip("Help", at: Point(x: 2, y: 2))

    #expect(root.isShowingTooltip)
    #expect(root.firstResponder === field,
            "help text appears because the pointer rested, which is the weakest signal there is")
}

@Test @MainActor func aTooltipFlipsAboveThePointerWhenThereIsNoRoomBelow() {
    let root = window(width: 30, height: 10)
    root.showTooltip("Help", at: Point(x: 2, y: 9))

    let panel = root.subviews.compactMap { $0 as? TooltipPanel }.first
    #expect(panel != nil)
    #expect((panel?.frame.minY ?? 0) < 9, "no room below, so it goes above")
}

@Test @MainActor func aTooltipIsPushedInsideTheWindowsEdges() {
    let root = window(width: 20, height: 10)
    root.showTooltip("A long piece of help", at: Point(x: 19, y: 1))

    let panel = root.subviews.compactMap { $0 as? TooltipPanel }.first
    #expect(panel != nil)
    #expect((panel?.frame.minX ?? -1) >= 0)
    #expect((panel?.frame.maxX ?? 999) <= 20, "a panel half off the screen is worse than none")
}

@Test @MainActor func restingOverAViewShowsItsHelpAndMovingAwayTakesItBack() async throws {
    let driver = HeadlessDriver(size: Size(width: 30, height: 10))
    let clock = ManualTimerSource()
    let app = App(driver: driver, timerSource: clock)

    let root = window()
    let button = Button("Save") {}
    button.frame = Rect(x: 2, y: 2, width: 8, height: 1)
    button.toolTip = "Write the file"
    root.addSubview(button)

    let session = Task { try await app.run(root) }
    while await driver.presentCount == 0 {
        await Task.yield()
    }

    // Resting over the button arms the dwell clock.
    await driver.send(.mouse(MouseInput(position: Point(x: 4, y: 2), action: .move, button: .none)))
    while await clock.streamCount < 1 {
        await Task.yield()
    }
    #expect(root.isShowingTooltip == false, "nothing before the delay elapses")

    clock.fire()
    while !root.isShowingTooltip {
        await Task.yield()
    }
    #expect(root.isShowingTooltip)

    // Moving off it takes the help away again — no second delay.
    await driver.send(.mouse(MouseInput(position: Point(x: 20, y: 8), action: .move, button: .none)))
    while root.isShowingTooltip {
        await Task.yield()
    }
    #expect(root.isShowingTooltip == false)

    await driver.send(.key(KeyInput(key: .character("c"), modifiers: .control)))
    try await session.value
}

@Test @MainActor func aPressTakesHelpTextAwayRatherThanLeavingItOverTheAction() async throws {
    let driver = HeadlessDriver(size: Size(width: 30, height: 10))
    let clock = ManualTimerSource()
    let app = App(driver: driver, timerSource: clock)

    let root = window()
    let button = Button("Save") {}
    button.frame = Rect(x: 2, y: 2, width: 8, height: 1)
    button.toolTip = "Write the file"
    root.addSubview(button)

    let session = Task { try await app.run(root) }
    while await driver.presentCount == 0 {
        await Task.yield()
    }

    await driver.send(.mouse(MouseInput(position: Point(x: 4, y: 2), action: .move, button: .none)))
    while await clock.streamCount < 1 {
        await Task.yield()
    }
    clock.fire()
    while !root.isShowingTooltip {
        await Task.yield()
    }

    await driver.send(.mouse(MouseInput(position: Point(x: 4, y: 2), action: .press, button: .left)))
    while root.isShowingTooltip {
        await Task.yield()
    }
    #expect(root.isShowingTooltip == false,
            "a press means doing, not asking — help text over it is in the way")

    await driver.send(.key(KeyInput(key: .character("c"), modifiers: .control)))
    try await session.value
}
