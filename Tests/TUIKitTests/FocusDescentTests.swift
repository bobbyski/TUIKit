import Testing

@testable import TUIKit

// makeFirstResponder's composite-forwarding contract: focusing a wrapper
// lands on its first focusable descendant; hopeless views still refuse.

@MainActor
struct FocusDescentTests {
    @Test func focusingACompositeDescendsToItsFocusableChild() {
        let window = Window(frame: Rect(x: 0, y: 0, width: 40, height: 10))
        let tree = DirectoryTree(root: "/", fileSystem: EmptyFileSystem())
        window.addSubview(tree)

        #expect(window.makeFirstResponder(tree))
        #expect(window.firstResponder is TreeView, "focus lands on the wrapped tree")
        #expect(window.firstResponder?.isDescendant(of: tree) == true)
    }

    @Test func viewsWithNoFocusableSubtreeStillRefuse() {
        let window = Window(frame: Rect(x: 0, y: 0, width: 40, height: 10))
        let plain = TUIView(frame: Rect(x: 0, y: 0, width: 5, height: 1))
        window.addSubview(plain)

        #expect(!window.makeFirstResponder(plain))
        #expect(window.firstResponder == nil)
    }

    @Test func hiddenDescendantsAreSkippedInTheDescent() {
        let window = Window(frame: Rect(x: 0, y: 0, width: 40, height: 10))
        let wrapper = TUIView(frame: .zero)
        let hidden = TextField()
        hidden.isHidden = true
        let visible = TextField()
        wrapper.addSubview(hidden)
        wrapper.addSubview(visible)
        window.addSubview(wrapper)

        #expect(window.makeFirstResponder(wrapper))
        #expect(window.firstResponder === visible)
    }
}

/// A file system with nothing in it.
private struct EmptyFileSystem: FileSystemProvider {
    func entries(at path: String) -> [FileSystemEntry] {
        []
    }
}
