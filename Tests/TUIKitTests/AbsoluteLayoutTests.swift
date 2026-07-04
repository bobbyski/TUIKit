import Testing
@testable import TUIKit

// MARK: - No automated layout

@Test @MainActor func absoluteLayoutLeavesChildrenWherePlaced() {
    let canvas = AbsoluteLayout(frame: Rect(x: 0, y: 0, width: 20, height: 20))
    let a = TUIView(frame: Rect(x: 2, y: 1, width: 4, height: 2))
    let b = canvas.place(TUIView(), at: Rect(x: 8, y: 5, width: 3, height: 3))

    canvas.addSubview(a)
    a.anchors = .fill()          // would fill any normal parent — ignored here

    canvas.setNeedsLayout()
    canvas.layoutIfNeeded()

    #expect(a.frame == Rect(x: 2, y: 1, width: 4, height: 2), "anchors are ignored; child not moved")
    #expect(b.frame == Rect(x: 8, y: 5, width: 3, height: 3), "placed child keeps its frame")

    // Intrinsic size is the bounding box of the children (8+3, 5+3).
    #expect(canvas.intrinsicContentSize == Size(width: 11, height: 8))
}

@Test @MainActor func emptyAbsoluteLayoutIsFlexible() {
    #expect(AbsoluteLayout().intrinsicContentSize == nil)
}

// MARK: - Auto-adjusts its parent

@Test @MainActor func absoluteLayoutSizesToItsParent() {
    let stack = VStack(frame: Rect(x: 0, y: 0, width: 10, height: 10))
    let canvas = AbsoluteLayout()
    canvas.place(TUIView(), at: Rect(x: 3, y: 2, width: 4, height: 3))   // bounding box 7×5
    stack.addSubview(canvas)

    stack.layoutIfNeeded()

    // Fill cross-axis (width 10), intrinsic main-axis (height 5).
    #expect(canvas.frame.size == Size(width: 10, height: 5))
}

// MARK: - relayout() forces the parent to re-measure

@Test @MainActor func relayoutRemeasuresThroughTheParent() {
    let stack = VStack(frame: Rect(x: 0, y: 0, width: 10, height: 12))
    let canvas = AbsoluteLayout()
    let child = canvas.place(TUIView(), at: Rect(x: 3, y: 2, width: 4, height: 3))
    stack.addSubview(canvas)
    stack.layoutIfNeeded()
    #expect(canvas.frame.size.height == 5)

    // Move the child taller by direct frame assignment.
    child.frame = Rect(x: 3, y: 2, width: 4, height: 8)   // bounding height now 10

    // A plain relayout of the stack sees nothing new — the stack was never
    // marked, because the child's frame change doesn't propagate size upward.
    stack.layoutIfNeeded()
    #expect(canvas.frame.size.height == 5, "stale until relayout()")

    // relayout() marks the ancestor chain, so the stack re-measures.
    canvas.relayout()
    stack.layoutIfNeeded()
    #expect(canvas.frame.size.height == 10, "parent adopted the new bounding size")
}

// MARK: - refresh() forces a redraw

@Test @MainActor func refreshForcesARedraw() {
    let window = Window(frame: Rect(x: 0, y: 0, width: 12, height: 4))
    let canvas = AbsoluteLayout()
    canvas.anchors = .fill()
    canvas.place(Label("hi"), at: Rect(x: 1, y: 1, width: 5, height: 1))
    window.addSubview(canvas)

    let renderer = SceneRenderer(root: window)
    _ = renderer.renderIfNeeded(size: window.frame.size)                 // first paint
    #expect(renderer.renderIfNeeded(size: window.frame.size) == nil, "clean tree presents nothing")

    canvas.refresh()
    #expect(renderer.renderIfNeeded(size: window.frame.size) != nil, "refresh() re-dirties the subtree")
}
