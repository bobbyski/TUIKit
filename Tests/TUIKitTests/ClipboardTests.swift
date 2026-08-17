import Testing

@testable import TUIKit

// Copy/paste across the editable controls. Every one of these went through
// the app's pasteboard WITHOUT the host wiring anything — the bug was that
// the plumbing existed and nobody connected it, so the keys were bound, the
// methods were written, and each returned early on a nil pasteboard.

@MainActor
private func hosted<V: TUIView>(_ view: V, size: Size = Size(width: 20, height: 6)) -> (App, Window, V) {
    let app = App(driver: HeadlessDriver(size: size))
    let window = Window(frame: Rect(x: 0, y: 0, width: size.width, height: size.height))
    view.frame = window.bounds
    window.addSubview(view)
    app.present(window)
    window.makeFirstResponder(view)
    return (app, window, view)
}

// MARK: - Text field (the Find box)

@Test @MainActor func aTextFieldPastesTheAppClipboardAtTheCursor() {
    let (app, _, field) = hosted(TextField(text: "let"))
    app.pasteboard.copy("Value")

    // The field never had a clipboard at all: ^V fell through its
    // "modifiers must be empty" guard and did nothing, so the Find box was
    // something you could only type into.
    #expect(field.keyDown(KeyInput(key: .character("v"), modifiers: .control)))
    #expect(field.text == "letValue", "pasted at the cursor, which starts at the end")
}

@Test @MainActor func aTextFieldPasteFlattensNewlines() {
    let (app, _, field) = hosted(TextField())
    app.pasteboard.copy("first\nsecond\r\nthird")

    _ = field.keyDown(KeyInput(key: .character("v"), modifiers: .control))

    // A field is ONE line. Keeping the newline would drop everything after
    // it, which is the failure mode you would never notice until it bit.
    #expect(field.text == "first second third")
}

@Test @MainActor func aTextFieldCopiesAndCutsItsWholeText() {
    let (app, _, field) = hosted(TextField(text: "query"))

    #expect(field.keyDown(KeyInput(key: .character("c"), modifiers: .control)))
    #expect(app.pasteboard.string == "query", "the whole field: there is a cursor but no selection")

    #expect(field.keyDown(KeyInput(key: .character("x"), modifiers: .control)))
    #expect(field.text.isEmpty)
    #expect(app.pasteboard.string == "query")
}

// MARK: - Code editor (the code window)

@Test @MainActor func theCodeEditorCopiesAndPastesThroughTheAppClipboard() {
    let (app, _, editor) = hosted(SyntaxTextView(text: "alpha\nbeta", language: "swift"))

    app.pasteboard.copy("gamma")
    #expect(editor.keyDown(KeyInput(key: .character("v"), modifiers: .control)))
    #expect(editor.text.contains("gamma"))
}

// MARK: - Text view (the commit message box)

@Test @MainActor func aTextViewPasteKeepsNewlines() {
    let (app, _, view) = hosted(TextView(text: ""))
    app.pasteboard.copy("Subject line\n\nA body paragraph.")

    #expect(view.keyDown(KeyInput(key: .character("v"), modifiers: .control)))

    // Newlines are KEPT here — the opposite of a one-line field, and the
    // whole point of pasting a commit message.
    #expect(view.text == "Subject line\n\nA body paragraph.")
}

@Test @MainActor func aReadOnlyTextViewRefusesPaste() {
    let (app, _, view) = hosted(TextView(text: "fixed"))
    view.isEditable = false
    app.pasteboard.copy("nope")

    _ = view.keyDown(KeyInput(key: .character("v"), modifiers: .control))
    #expect(view.text == "fixed")
}
