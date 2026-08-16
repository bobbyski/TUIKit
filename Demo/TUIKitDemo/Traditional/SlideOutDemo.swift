import TUIKit

// A window with all three slide-outs, for eyeball-testing them.
//
// The point of the demo is the thing you CANNOT see: with every panel closed
// this window is document from border to border — no separator, no stub, no
// reserved column. That is the whole reason slide-outs are not docks (see
// `Docs/SlideOutPlan.md`), and it is only convincing if you can toggle them
// and watch the text stay exactly where it was.

/// A window that claims its own shortcuts. `Window.handleHotKey` runs before
/// focus routing, which is what makes ^L work while focus is inside a panel.
@MainActor
final class SlideOutDemoWindow: FloatingWindow {
    override func handleHotKey(_ key: KeyInput) -> Bool {
        guard key.modifiers == .control else {
            return super.handleHotKey(key)
        }

        switch key.key {
        case .character("l"):
            toggleSlideOut(.leading)
            return true

        case .character("r"):
            toggleSlideOut(.trailing)
            return true

        // NOT ^J, which never arrives: Ctrl+J *is* ASCII 0x0A, and the
        // decoder turns 0x0A into `.enter` — the same reason ^I is Tab and
        // ^M is Return. ^H, ^I, ^J and ^M are all unavailable as shortcuts,
        // whatever a handler says it wants. NOT ^B either: the demo's File
        // menu already claims it.
        case .character("t"):
            toggleSlideOut(.bottom)
            return true

        case .character("p"):
            slideOut(at: .leading)?.isPinned.toggle()
            return true

        default:
            return super.handleHotKey(key)
        }
    }
}

@MainActor
func makeSlideOutDemo(index: Int) -> SlideOutDemoWindow {
    let window = SlideOutDemoWindow(
        title: "Slide-Outs \(index)",
        frame: Rect(x: 6 + index * 2, y: 3 + index, width: 74, height: 22)
    )

    let document = SyntaxTextView(text: """
        // Toggle the panels and watch this text MOVE ASIDE, not get covered.
        //
        //   ^L  Files      (leading)
        //   ^R  Inspector  (trailing)
        //   ^T  Build      (bottom)
        //   ^P  pin/unpin the leading panel
        //
        // All four are also in the Panels menu. Both are needed: keys reach
        // only the KEY window, so the window's own handler works when this
        // window is key and the menu's equivalents work when the menu bar is
        // — which is the state you are in right after opening this from the
        // File menu.
        //
        // Drag a panel's INNER border to resize it.
        //
        // Closed, a slide-out costs zero cells: no divider, no stub, no
        // reserved column. That is the whole reason these are not docks.
        //
        // Open, it pushes the document aside — the tree and the file are
        // wanted at the same time, which is the point of opening the tree.
        //
        // Only ONE line is drawn per panel: the divider on the inner edge.
        // The other three sides are the window's own frame, so a box there
        // would paint a second line beside the window's and cost two columns
        // to say nothing.
        //
        // Pin (^P) means one thing: the panel does not close when you
        // activate a row inside it. Unpinned is a drawer — open it, pick a
        // file, it closes behind you.
        //
        // The [>] button after the title toggles the Files panel too, and
        // flips to [<] while it is open.
        //
        // Open the Inspector (^R) and watch the vertical scrollbar move OFF
        // the window border and onto this view's own right edge — the border
        // is on the far side of the panel, so a bar there would be scrolling
        // something it is nowhere near. Close it and the slider moves back
        // out.

        struct Editor {
            var text: String
            var caret: Int

            func render() -> String {
                text
            }
        }
        """)
    document.language = "swift"
    document.anchors = .fill()
    window.content.addSubview(document)

    let files = ListView(items: [
        "▾ Sources", "    App.swift", "    Editor.swift", "▾ Tests", "    AppTests.swift",
    ])
    files.select(0)
    window.addSlideOut(.leading, title: "Files", content: files, length: 22)

    let inspector = ListView(items: ["Type: struct", "Lines: 12", "Language: swift"])
    window.addSlideOut(.trailing, title: "Inspector", content: inspector, length: 24)

    let build = ListView(items: [
        "Compiling TUIKit SlideOut.swift", "Compiling TUIKit Window.swift", "Build complete! (3.22s)",
    ])
    window.addSlideOut(.bottom, title: "Build", content: build, length: 6)

    // The discoverable half of the feature: a shortcut nobody can guess is a
    // feature nobody finds.
    window.slideOutToggleEdge = .leading

    // Border-embedded scrollbars, so the trailing panel has something to hand
    // back and forth.
    window.embedScrollbars(for: document)

    return window
}
