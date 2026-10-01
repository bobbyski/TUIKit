// Copyright (c) 2026 Bobby Skinner
// SPDX-License-Identifier: MIT
// See the LICENSE file at the repository root for the full text.

import Testing
@testable import TUIKit

// ActiveUI change request R8: a field that hides a password, and one that sits
// its text centred or at the trailing edge.

@MainActor
private func hosted(_ field: TextField, width: Int = 12, focused: Bool = false) -> (App, Window, TextField) {
    let size = Size(width: width, height: 1)
    let app = App(driver: HeadlessDriver(size: size))
    let window = Window(frame: Rect(x: 0, y: 0, width: width, height: 1))
    field.frame = window.bounds
    window.addSubview(field)
    app.present(window)
    if focused {
        window.makeFirstResponder(field)
    }
    return (app, window, field)
}

@MainActor
private func row(_ window: Window, width: Int) -> String {
    let buffer = SceneRenderer(root: window).render(size: Size(width: width, height: 1))
    return String((0..<width).map { buffer[Point(x: $0, y: 0)].character })
}

@Test @MainActor func aSecureFieldDrawsBulletsNotTheText() {
    let field = TextField(text: "hunter2")
    field.isSecure = true
    let (_, window, _) = hosted(field)
    let drawn = row(window, width: 12)
    #expect(drawn.hasPrefix("•••••••"))
    #expect(!drawn.contains("h") && !drawn.contains("2"), "the password showed: \(drawn)")
}

@Test @MainActor func aSecureFieldStillTypesTheRealText() {
    let field = TextField(text: "ab")
    field.isSecure = true
    let (_, window, _) = hosted(field, focused: true)
    _ = field.keyDown(KeyInput(key: .character("c"), modifiers: []))
    #expect(field.text == "abc")
    #expect(row(window, width: 12).hasPrefix("•••"))
}

@Test @MainActor func aSecureFieldGivesNothingToTheClipboard() {
    let field = TextField(text: "secret")
    field.isSecure = true
    let (app, _, _) = hosted(field, focused: true)
    app.pasteboard.copy("before")
    _ = field.keyDown(KeyInput(key: .character("c"), modifiers: .control))
    #expect(app.pasteboard.string == "before", "copy took the password")
    _ = field.keyDown(KeyInput(key: .character("x"), modifiers: .control))
    #expect(app.pasteboard.string == "before", "cut took the password")
    #expect(field.text == "secret", "cut removed what it did not copy")
}

@Test @MainActor func alignmentPlacesShortText() {
    // 12 columns, one kept for the caret: "abc" leaves 8 to share.
    let trailing = TextField(text: "abc")
    trailing.alignment = .trailing
    #expect(row(hosted(trailing).1, width: 12) == "        abc ")

    let centred = TextField(text: "abc")
    centred.alignment = .center
    #expect(row(hosted(centred).1, width: 12) == "    abc     ")

    let leading = TextField(text: "abc")
    #expect(row(hosted(leading).1, width: 12) == "abc         ")
}

@Test @MainActor func aClickInAnAlignedFieldLandsOnItsCharacter() {
    let field = TextField(text: "abc")
    field.alignment = .trailing
    _ = hosted(field, focused: true)
    // "abc" sits at columns 8–10: a click on column 9 is the "b".
    _ = field.mouseEvent(MouseInput(position: Point(x: 9, y: 0), action: .press, button: .left))
    #expect(field.cursorPosition == 1)
}

// One report per edit (ActiveUI's AUITextField.onChange): typing over a
// selection and pasting were two and many.

@Test @MainActor func typingOverASelectionReportsOnce() {
    let field = TextField(text: "hello")
    let window = Window(frame: Rect(x: 0, y: 0, width: 20, height: 1))
    field.frame = Rect(x: 0, y: 0, width: 20, height: 1)
    window.addSubview(field)
    window.makeFirstResponder(field)
    var reports: [String] = []
    field.onChanged = { reports.append($0) }

    field.selectAll()
    window.route(.key(KeyInput(key: .character("x"))))
    #expect(field.text == "x")
    #expect(reports == ["x"], "typing over a selection reported \(reports)")
}

@Test @MainActor func aPasteReportsOnce() {
    let field = TextField(text: "")
    let board = Pasteboard()
    field.pasteboard = board
    board.copy("abc")
    var reports: [String] = []
    field.onChanged = { reports.append($0) }

    field.paste()
    #expect(field.text == "abc")
    #expect(reports == ["abc"], "a paste reported \(reports)")
}
