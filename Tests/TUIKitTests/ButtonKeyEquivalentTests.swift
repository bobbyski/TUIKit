// Copyright (c) 2026 Bobby Skinner
// SPDX-License-Identifier: MIT
// See the LICENSE file at the repository root for the full text.

import Testing
@testable import TUIKit

// ActiveUI change request R9: a button's key equivalent.

@Test @MainActor func aKeyEquivalentActivatesTheButton() {
    var activations = 0
    let button = Button("Save") { activations += 1 }
    button.keyEquivalent = KeyInput(key: .character("s"), modifiers: .control)

    #expect(button.handleHotKey(KeyInput(key: .character("s"), modifiers: .control)))
    #expect(button.handleHotKey(KeyInput(key: .character("S"), modifiers: .control)), "a letter matches either case")
    #expect(!button.handleHotKey(KeyInput(key: .character("s"), modifiers: [])), "the modifiers must match")
    #expect(!button.handleHotKey(KeyInput(key: .character("d"), modifiers: .control)))
    #expect(activations == 2)
}

@Test @MainActor func returnIsADefaultButtonOnlyWhenNothingFocusedTakesIt() {
    var activations = 0
    let button = Button("OK") { activations += 1 }
    button.keyEquivalent = KeyInput(key: .enter, modifiers: [])
    let editor = TextView(text: "")
    let app = App(driver: HeadlessDriver(size: Size(width: 20, height: 4)))
    let window = Window(frame: Rect(x: 0, y: 0, width: 20, height: 4))
    editor.frame = Rect(x: 0, y: 0, width: 20, height: 2)
    button.frame = Rect(x: 0, y: 3, width: 6, height: 1)
    window.addSubview(editor)
    window.addSubview(button)
    app.present(window)

    // Unmodified: not a hot key, so a focused text view keeps its Return.
    #expect(!button.handleHotKey(KeyInput(key: .enter, modifiers: [])))
    window.makeFirstResponder(editor)
    _ = window.route(.key(KeyInput(key: .enter, modifiers: [])))
    #expect(activations == 0 && editor.text == "\n", "Return went to the button, not the text view")

    // With nothing taking Return, it presses the default button.
    #expect(button.handleColdKey(KeyInput(key: .enter, modifiers: [])))
    #expect(activations == 1)
}

@Test @MainActor func withoutAKeyEquivalentNothingNewMatches() {
    let button = Button("Plain") {}
    #expect(!button.handleHotKey(KeyInput(key: .character("s"), modifiers: .control)))
}
