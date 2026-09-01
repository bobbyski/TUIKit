import Testing
@testable import TUIKit

// Coordinate conversion between views (TUIKIT_CHANGE_REQUESTS.md R3).
//
// The arithmetic Window has always done privately for drag handling, made
// public because hosts need it too. These pin the three answers that are easy
// to get subtly wrong: nesting, sideways conversion through a shared parent,
// and the unrelated case that must refuse rather than guess.

@MainActor
private func view(_ x: Int, _ y: Int, _ w: Int = 10, _ h: Int = 4) -> TUIView {
    TUIView(frame: Rect(origin: Point(x: x, y: y), size: Size(width: w, height: h)))
}

@Test @MainActor
func originSumsTheChain() {
    let root = view(0, 0, 80, 24)
    let middle = view(10, 5)
    let leaf = view(3, 2)
    root.addSubview(middle)
    middle.addSubview(leaf)

    #expect(leaf.origin(in: root) == Point(x: 13, y: 7))
    #expect(middle.origin(in: root) == Point(x: 10, y: 5))
}

@Test @MainActor
func originInSelfIsZero() {
    let root = view(4, 4)

    #expect(root.origin(in: root) == Point.zero)
}

@Test @MainActor
func originRefusesWhenNotAnAncestor() {
    let root = view(0, 0, 80, 24)
    let child = view(2, 2)
    let stranger = view(0, 0)
    root.addSubview(child)

    // Refusing beats answering a plausible number: a detached view would
    // otherwise report an origin measured against nothing.
    #expect(child.origin(in: stranger) == nil)
}

@Test @MainActor
func convertGoesSideways() {
    let root = view(0, 0, 80, 24)
    let left = view(0, 0, 20, 10)
    let right = view(40, 3, 20, 10)
    root.addSubview(left)
    root.addSubview(right)

    // A point 1 cell into `left` is 39 cells left of, and 3 above, the same
    // spot in `right`.
    #expect(left.convert(Point(x: 1, y: 1), to: right) == Point(x: -39, y: -2))
    #expect(right.convert(Point(x: -39, y: -2), to: left) == Point(x: 1, y: 1))
}

@Test @MainActor
func convertRoundTripsThroughNesting() {
    let root = view(0, 0, 80, 24)
    let middle = view(10, 5)
    let leaf = view(3, 2)
    root.addSubview(middle)
    middle.addSubview(leaf)

    let inLeaf = Point(x: 1, y: 1)
    let inRoot = leaf.convert(inLeaf, to: root)

    #expect(inRoot == Point(x: 14, y: 8))
    #expect(root.convert(inRoot!, to: leaf) == inLeaf)
    #expect(leaf.convert(inRoot!, from: root) == inLeaf)
}

@Test @MainActor
func unrelatedViewsShareNoAncestor() {
    let one = view(0, 0)
    let two = view(0, 0)

    #expect(one.nearestCommonAncestor(with: two) == nil)
    #expect(one.convert(Point.zero, to: two) == nil)
}

@Test @MainActor
func aViewIsItsOwnAncestor() {
    let root = view(0, 0, 80, 24)
    let child = view(2, 2)
    root.addSubview(child)

    #expect(root.nearestCommonAncestor(with: child) === root)
    #expect(child.nearestCommonAncestor(with: root) === root)
}
