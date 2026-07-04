import Testing
@testable import TUIKit

// MARK: - Test Views

/// Fills its bounds with one character.
@MainActor
private final class FillView: TUIView {
    var character: Character

    init(frame: Rect, character: Character) {
        self.character = character
        super.init(frame: frame)
    }

    override func draw(_ painter: Painter) {
        painter.fill(bounds, with: TerminalCell(character: character))
    }
}

/// Writes text at a local position — including deliberately out-of-bounds
/// positions, to prove the painter clips them.
@MainActor
private final class TextView: TUIView {
    var text: String
    var position: Point

    init(frame: Rect, text: String, position: Point = .zero) {
        self.text = text
        self.position = position
        super.init(frame: frame)
    }

    override func draw(_ painter: Painter) {
        painter.write(text, at: position)
    }
}

// MARK: - Hierarchy

@Test @MainActor func addSubviewLinksParentAndChild() {
    let parent = TUIView(frame: Rect(x: 0, y: 0, width: 10, height: 10))
    let child = TUIView(frame: Rect(x: 1, y: 1, width: 2, height: 2))

    parent.addSubview(child)

    #expect(child.superview === parent)
    #expect(parent.subviews.count == 1)
    #expect(parent.subviews.first === child)
}

@Test @MainActor func addSubviewReparentsFromPreviousParent() {
    let first = TUIView(frame: Rect(x: 0, y: 0, width: 5, height: 5))
    let second = TUIView(frame: Rect(x: 0, y: 0, width: 5, height: 5))
    let child = TUIView()

    first.addSubview(child)
    second.addSubview(child)

    #expect(first.subviews.isEmpty)
    #expect(child.superview === second)
}

@Test @MainActor func removeFromSuperviewDetaches() {
    let parent = TUIView(frame: Rect(x: 0, y: 0, width: 5, height: 5))
    let child = TUIView()

    parent.addSubview(child)
    child.removeFromSuperview()

    #expect(parent.subviews.isEmpty)
    #expect(child.superview == nil)
}

// MARK: - Local Coordinates

@Test @MainActor func childrenDrawInLocalCoordinates() {
    let root = TUIView(frame: Rect(x: 0, y: 0, width: 10, height: 4))
    let panel = TUIView(frame: Rect(x: 2, y: 1, width: 6, height: 2))
    let label = TextView(frame: Rect(x: 1, y: 0, width: 4, height: 1), text: "hi")

    root.addSubview(panel)
    panel.addSubview(label)

    let buffer = SceneRenderer(root: root).render(size: Size(width: 10, height: 4))

    // Label's local (0,0) is panel(2,1) + label(1,0) = buffer (3,1).
    #expect(buffer.text(row: 1) == "   hi     ")
}

@Test @MainActor func rootFrameOffsetsTheWholeTree() {
    let root = TextView(frame: Rect(x: 4, y: 2, width: 5, height: 1), text: "top")

    let buffer = SceneRenderer(root: root).render(size: Size(width: 10, height: 4))

    #expect(buffer.text(row: 2) == "    top   ")
}

// MARK: - Clipping Contract

@Test @MainActor func childCannotDrawOutsideItsOwnFrame() {
    let root = TUIView(frame: Rect(x: 0, y: 0, width: 10, height: 3))
    // The view is 3 wide but writes 8 characters.
    let child = TextView(frame: Rect(x: 1, y: 1, width: 3, height: 1), text: "TOOLONG!")

    root.addSubview(child)

    let buffer = SceneRenderer(root: root).render(size: Size(width: 10, height: 3))

    #expect(buffer.text(row: 1) == " TOO      ")
}

@Test @MainActor func childCannotDrawOutsideItsParentViewport() {
    let root = TUIView(frame: Rect(x: 0, y: 0, width: 10, height: 4))
    let panel = TUIView(frame: Rect(x: 2, y: 1, width: 4, height: 2))
    // Child frame extends past the panel's right edge; the panel clips it.
    let child = FillView(frame: Rect(x: 2, y: 0, width: 6, height: 1), character: "#")

    root.addSubview(panel)
    panel.addSubview(child)

    let buffer = SceneRenderer(root: root).render(size: Size(width: 10, height: 4))

    // Panel covers columns 2..<6; the child may fill only columns 4..<6.
    #expect(buffer.text(row: 1) == "    ##    ")
}

@Test @MainActor func negativeChildPositionsClipAtParentOrigin() {
    let root = TUIView(frame: Rect(x: 0, y: 0, width: 8, height: 3))
    let panel = TUIView(frame: Rect(x: 3, y: 1, width: 4, height: 1))
    let child = TextView(frame: Rect(x: -2, y: 0, width: 6, height: 1), text: "abcdef")

    root.addSubview(panel)
    panel.addSubview(child)

    // Child local x 0..5 maps to panel x -2..3; only panel x 0..3 (buffer
    // 3..6) is writable, showing characters c..f.
    let buffer = SceneRenderer(root: root).render(size: Size(width: 8, height: 3))

    #expect(buffer.text(row: 1) == "   cdef ")
}

// MARK: - Compose Order and Visibility

@Test @MainActor func laterSiblingsOverdrawEarlierOnes() {
    let root = TUIView(frame: Rect(x: 0, y: 0, width: 6, height: 1))
    let back = FillView(frame: Rect(x: 0, y: 0, width: 4, height: 1), character: "a")
    let front = FillView(frame: Rect(x: 2, y: 0, width: 4, height: 1), character: "b")

    root.addSubview(back)
    root.addSubview(front)

    let buffer = SceneRenderer(root: root).render(size: Size(width: 6, height: 1))

    #expect(buffer.text(row: 0) == "aabbbb")
}

@Test @MainActor func hiddenViewsAndTheirSubtreesAreSkipped() {
    let root = TUIView(frame: Rect(x: 0, y: 0, width: 4, height: 1))
    let panel = FillView(frame: Rect(x: 0, y: 0, width: 4, height: 1), character: "x")
    let child = FillView(frame: Rect(x: 0, y: 0, width: 4, height: 1), character: "y")

    root.addSubview(panel)
    panel.addSubview(child)
    panel.isHidden = true

    let buffer = SceneRenderer(root: root).render(size: Size(width: 4, height: 1))

    #expect(buffer.text(row: 0) == "    ")
}

@Test @MainActor func renderingIsDeterministic() {
    let root = TUIView(frame: Rect(x: 0, y: 0, width: 8, height: 2))
    root.addSubview(FillView(frame: Rect(x: 1, y: 0, width: 3, height: 2), character: "z"))

    let renderer = SceneRenderer(root: root)
    let first = renderer.render(size: Size(width: 8, height: 2))
    root.setNeedsDisplay()
    let second = renderer.render(size: Size(width: 8, height: 2))

    #expect(first == second)
}

// MARK: - Dirty Tracking

@Test @MainActor func renderClearsDirtinessUntilNextChange() {
    let root = TUIView(frame: Rect(x: 0, y: 0, width: 4, height: 2))
    let child = FillView(frame: Rect(x: 0, y: 0, width: 2, height: 1), character: "c")
    root.addSubview(child)

    let renderer = SceneRenderer(root: root)
    let size = Size(width: 4, height: 2)

    #expect(renderer.renderIfNeeded(size: size) != nil)
    #expect(renderer.renderIfNeeded(size: size) == nil)

    // A deep change re-dirties the tree through ancestor propagation.
    child.character = "d"
    child.setNeedsDisplay()

    #expect(root.needsDisplayInTree)
    #expect(renderer.renderIfNeeded(size: size)?.text(row: 0) == "dd  ")
    #expect(renderer.renderIfNeeded(size: size) == nil)
}

@Test @MainActor func frameChangeMarksDirty() {
    let view = TUIView(frame: Rect(x: 0, y: 0, width: 2, height: 2))
    let renderer = SceneRenderer(root: view)
    _ = renderer.render(size: Size(width: 4, height: 4))

    view.frame = Rect(x: 1, y: 1, width: 2, height: 2)

    #expect(view.needsDisplay)
    #expect(renderer.needsRender(for: Size(width: 4, height: 4)))
}

@Test @MainActor func sizeChangeForcesRenderEvenWhenClean() {
    let root = TUIView(frame: Rect(x: 0, y: 0, width: 4, height: 2))
    let renderer = SceneRenderer(root: root)

    _ = renderer.render(size: Size(width: 4, height: 2))

    #expect(renderer.renderIfNeeded(size: Size(width: 4, height: 2)) == nil)
    #expect(renderer.renderIfNeeded(size: Size(width: 6, height: 3)) != nil)
}

// MARK: - Painter Primitives

@Test @MainActor func drawBoxRendersBorders() {
    let root = TUIView(frame: Rect(x: 0, y: 0, width: 5, height: 3))

    final class BoxView: TUIView {
        override func draw(_ painter: Painter) {
            painter.drawBox(bounds)
        }
    }

    let box = BoxView(frame: Rect(x: 0, y: 0, width: 5, height: 3))
    root.addSubview(box)

    let buffer = SceneRenderer(root: root).render(size: Size(width: 5, height: 3))

    #expect(buffer.textLines() == [
        "┌───┐",
        "│   │",
        "└───┘",
    ])
}
