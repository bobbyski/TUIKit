import Testing
@testable import TUIKit

// A Demo Source-shaped window: a sidebar stand-in on the left, a scrolling
// syntax viewer on the right, bars embedded in the window border.
@MainActor
private func makeEmbeddedWindow() -> (window: FloatingWindow, editor: SyntaxTextView) {
    let window = FloatingWindow(title: "Src", frame: Rect(x: 0, y: 0, width: 30, height: 12))
    window.theme = .dark

    let sidebar = TUIView(frame: Rect(x: 0, y: 0, width: 8, height: 10))
    window.content.addSubview(sidebar)

    // 40 lines of 60 columns — overflows both axes of its 19×10 frame.
    let text = Array(repeating: String(repeating: "x", count: 60), count: 40).joined(separator: "\n")
    let editor = SyntaxTextView(text: text, language: "text")
    editor.showsLineNumbers = false
    editor.isEditable = false
    editor.frame = Rect(x: 9, y: 0, width: 19, height: 10)
    window.content.addSubview(editor)

    window.embedScrollbars(for: editor)   // vertical .fullEdge, horizontal .underClient
    return (window, editor)
}

@Test @MainActor func borderScrollbarsRideTheChromeUnderTheClientOnly() {
    let (window, editor) = makeEmbeddedWindow()
    #expect(!editor.showsOwnScrollbars, "embedding hands the bars to the border")

    let buffer = SceneRenderer(root: window).render(size: Size(width: 30, height: 12))

    // The right border carries the vertical bar: arrows at the run's ends,
    // solid track/thumb cells between — not the border glyph.
    #expect(buffer[Point(x: 29, y: 1)].character == "▴")
    #expect(buffer[Point(x: 29, y: 10)].character == "▾")
    #expect(buffer[Point(x: 29, y: 5)].character == " ", "track/thumb cells are solid color")

    // The bottom border carries the horizontal bar only under the editor
    // (panel x 10..28); under the sidebar it stays a plain border line.
    #expect(buffer[Point(x: 2, y: 11)].character == "─", "no bar under the sidebar")
    #expect(buffer[Point(x: 10, y: 11)].character == "◂")
    #expect(buffer[Point(x: 28, y: 11)].character == "▸")
    #expect(buffer[Point(x: 20, y: 11)].character == " ")

    // The resize corner survives.
    #expect(buffer[Point(x: 29, y: 11)].character == "◢")
}

@Test @MainActor func borderScrollbarsScrollTheClient() {
    let (window, editor) = makeEmbeddedWindow()
    _ = SceneRenderer(root: window).render(size: Size(width: 30, height: 12))

    // Track press below the thumb pages down (viewport 10 → a 9-line page).
    _ = window.route(.mouse(MouseInput(position: Point(x: 29, y: 8), action: .press, button: .left)))
    #expect(editor.verticalScrollSpan?.offset == 9)
    _ = window.route(.mouse(MouseInput(position: Point(x: 29, y: 8), action: .release, button: .left)))

    // The ▾ arrow steps one line.
    _ = window.route(.mouse(MouseInput(position: Point(x: 29, y: 10), action: .press, button: .left)))
    #expect(editor.verticalScrollSpan?.offset == 10)
    _ = window.route(.mouse(MouseInput(position: Point(x: 29, y: 10), action: .release, button: .left)))

    // Grabbing the thumb and dragging maps back to a proportional offset.
    // At offset 10: track rows 2..9, thumb length 2, start 2 + 10*6/30 = 4.
    _ = window.route(.mouse(MouseInput(position: Point(x: 29, y: 4), action: .press, button: .left)))
    _ = window.route(.mouse(MouseInput(position: Point(x: 29, y: 7), action: .drag, button: .left)))
    #expect(editor.verticalScrollSpan?.offset == 25, "thumb row 7 → clamped start 5 of 6 → 25 of 30")
    _ = window.route(.mouse(MouseInput(position: Point(x: 29, y: 7), action: .release, button: .left)))

    // The horizontal bar pages too: a press right of its thumb.
    _ = window.route(.mouse(MouseInput(position: Point(x: 20, y: 11), action: .press, button: .left)))
    #expect(editor.horizontalScrollSpan?.offset == 18, "viewport 19 → an 18-column page")
}

@Test @MainActor func partialVerticalBarFollowsTheClientSpan() {
    let (window, editor) = makeEmbeddedWindow()

    // Re-embed asking the vertical bar to hug the client too — proving the
    // right bar can run partial when we decide to use it.
    editor.frame = Rect(x: 9, y: 3, width: 19, height: 7)
    window.embedScrollbars(for: editor, vertical: .underClient)

    let buffer = SceneRenderer(root: window).render(size: Size(width: 30, height: 12))

    // Above the editor's span the border stays chrome; within it, the bar.
    #expect(buffer[Point(x: 29, y: 2)].character == "│", "no bar above the client")
    #expect(buffer[Point(x: 29, y: 4)].character == "▴")
    #expect(buffer[Point(x: 29, y: 10)].character == "▾")
}

@Test @MainActor func embeddedBarsArePermanentChromeEvenWhenContentFits() {
    let (window, editor) = makeEmbeddedWindow()
    let renderer = SceneRenderer(root: window)

    // Grow the window (and the editor with it) until everything fits…
    window.frame = Rect(x: 0, y: 0, width: 80, height: 50)
    editor.frame = Rect(x: 9, y: 0, width: 69, height: 48)
    var buffer = renderer.render(size: Size(width: 80, height: 50))

    // …the bars stay, Borland-style, with the thumb filling the track.
    #expect(buffer[Point(x: 79, y: 1)].character == "▴", "vertical bar stays when lines fit")
    #expect(buffer[Point(x: 79, y: 48)].character == "▾")
    #expect(buffer[Point(x: 40, y: 49)].character == " ", "horizontal bar stays when lines fit")

    // Shrinking back re-engages both axes — no bar goes missing.
    window.frame = Rect(x: 0, y: 0, width: 30, height: 12)
    editor.frame = Rect(x: 9, y: 0, width: 19, height: 10)
    buffer = renderer.render(size: Size(width: 30, height: 12))
    #expect(buffer[Point(x: 29, y: 1)].character == "▴")
    #expect(buffer[Point(x: 29, y: 10)].character == "▾")
    #expect(buffer[Point(x: 10, y: 11)].character == "◂")
}
