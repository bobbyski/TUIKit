import Foundation
import Testing
@testable import TUIKit

// SUPPORT_TERMINAL_PLAN.md U1, the compositing half.
//
// The driver has diffed rows against the previous frame for a while, so an
// idle app writes no bytes. What it did not do was stop *composing*: every
// view in the tree was drawn every frame, including the ones clipped entirely
// away. A list is a stack of rows in a shorter window, so most of the work in
// a frame went into rows nobody could see.

/// A view that records how often it was asked to draw.
@MainActor
private final class CountingView: TUIView {
    var drawCount = 0

    override func draw(_ painter: Painter) {
        drawCount += 1
        super.draw(painter)
    }
}

@Test @MainActor func aViewClippedEntirelyAwayIsNotDrawn() {
    let window = Window(frame: Rect(x: 0, y: 0, width: 20, height: 5))
    let onScreen = CountingView()
    onScreen.frame = Rect(x: 0, y: 0, width: 20, height: 2)
    let offScreen = CountingView()
    offScreen.frame = Rect(x: 0, y: 40, width: 20, height: 2)   // far below the window
    window.addSubview(onScreen)
    window.addSubview(offScreen)

    _ = SceneRenderer(root: window).render(size: Size(width: 20, height: 5))

    #expect(onScreen.drawCount == 1, "a visible view still draws")
    #expect(offScreen.drawCount == 0,
            "a view whose clip has no area cannot reach the buffer, so it is not asked")
}

@Test @MainActor func aCulledSubtreeComesOutOfTheFrameClean() {
    // Otherwise `needsDisplayInTree` stays true and the run loop composes a
    // new frame on every tick, forever, over something invisible.
    let window = Window(frame: Rect(x: 0, y: 0, width: 20, height: 5))
    let offScreen = CountingView()
    offScreen.frame = Rect(x: 0, y: 40, width: 20, height: 2)
    let child = CountingView()
    child.frame = Rect(x: 0, y: 0, width: 20, height: 1)
    offScreen.addSubview(child)
    window.addSubview(offScreen)

    let renderer = SceneRenderer(root: window)
    _ = renderer.render(size: Size(width: 20, height: 5))

    #expect(offScreen.needsDisplay == false)
    #expect(child.needsDisplay == false)
    #expect(renderer.needsRender(for: Size(width: 20, height: 5)) == false,
            "a culled subtree must not keep the tree dirty")
}

@Test @MainActor func cullingIsByClipNotByFrame() {
    // A view partly on screen keeps drawing — the guard is "no area left to
    // write into", not "the frame pokes out of the window".
    let window = Window(frame: Rect(x: 0, y: 0, width: 20, height: 5))
    let straddling = CountingView()
    straddling.frame = Rect(x: 0, y: 3, width: 20, height: 10)
    window.addSubview(straddling)

    _ = SceneRenderer(root: window).render(size: Size(width: 20, height: 5))
    #expect(straddling.drawCount == 1)
}
