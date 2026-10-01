// Copyright (c) 2026 Bobby Skinner
// SPDX-License-Identifier: MIT
// See the LICENSE file at the repository root for the full text.

import Testing
@testable import TUIKit

// `wraps` (ActiveUI's AUIStepper.wraps): past one bound lands on the other,
// as NSStepper's valueWraps does. Off, the value pins.

@Test @MainActor func aWrappingStepperGoesRoundTheEnds() {
    let stepper = Stepper(value: 9, in: 0...10, step: 2)
    stepper.wraps = true
    var events: [Int] = []
    stepper.onValueChanged = { events.append($0) }

    _ = stepper.keyDown(KeyInput(key: .up))
    #expect(stepper.value == 0, "past the top should land on the bottom, got \(stepper.value)")
    _ = stepper.keyDown(KeyInput(key: .down))
    #expect(stepper.value == 10, "past the bottom should land on the top, got \(stepper.value)")
    #expect(events == [0, 10])

    // Home and End are jumps to the bounds, not steps; wrapping leaves them alone.
    _ = stepper.keyDown(KeyInput(key: .home))
    #expect(stepper.value == 0)
}

@Test @MainActor func aStepperThatDoesNotWrapStillPins() {
    let stepper = Stepper(value: 10, in: 0...10)
    var events: [Int] = []
    stepper.onValueChanged = { events.append($0) }
    _ = stepper.keyDown(KeyInput(key: .up))
    #expect(stepper.value == 10 && events.isEmpty, "a pinned stepper moved or reported")
}

@Test @MainActor func aStepperWithoutItsValueIsTheTwoButtons() {
    let stepper = Stepper(value: 0, in: -1_000_000...1_000_000)
    stepper.showsValue = false
    #expect(stepper.intrinsicContentSize == Size(width: 7, height: 1))
    stepper.frame = Rect(x: 0, y: 0, width: 7, height: 1)
    let window = Window(frame: Rect(x: 0, y: 0, width: 7, height: 1))
    window.addSubview(stepper)
    let line = SceneRenderer(root: window).render(size: Size(width: 7, height: 1)).textLines()[0]
    #expect(line == "[-] [+]", "drew \(line)")

    var steps: [Int] = []
    stepper.onValueChanged = { steps.append($0) }
    _ = stepper.mouseEvent(MouseInput(position: Point(x: 5, y: 0), action: .press, button: .left))
    _ = stepper.mouseEvent(MouseInput(position: Point(x: 1, y: 0), action: .press, button: .left))
    #expect(steps == [1, 0], "the buttons stepped \(steps)")
}
