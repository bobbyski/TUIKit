import Testing
@testable import TUIKit

@Test func frameworkReportsAVersion() {
    #expect(!TUIKitInfo.version.isEmpty)
}

// MARK: - Geometry

@Test func rectContainsItsInteriorNotItsMaxEdge() {
    let rect = Rect(x: 2, y: 3, width: 4, height: 2)

    #expect(rect.contains(Point(x: 2, y: 3)))
    #expect(rect.contains(Point(x: 5, y: 4)))
    #expect(!rect.contains(Point(x: 6, y: 4)))
    #expect(!rect.contains(Point(x: 2, y: 5)))
    #expect(!rect.contains(Point(x: 1, y: 3)))
}

@Test func rectIntersectionOverlapsAndDisjoints() {
    let a = Rect(x: 0, y: 0, width: 10, height: 10)
    let b = Rect(x: 5, y: 5, width: 10, height: 10)
    let c = Rect(x: 20, y: 20, width: 3, height: 3)

    #expect(a.intersection(b) == Rect(x: 5, y: 5, width: 5, height: 5))
    #expect(b.intersection(a) == a.intersection(b))
    #expect(a.intersection(c) == .zero)
    #expect(a.intersection(a) == a)
}

@Test func sizeClampsNegativeComponentsToZero() {
    let size = Size(width: -4, height: 3)

    #expect(size.width == 0)
    #expect(size.isEmpty)
    #expect(size.cellCount == 0)
}

@Test func pointArithmetic() {
    let base = Point(x: 3, y: 4)
    let offset = Point(x: 1, y: -2)

    #expect(base + offset == Point(x: 4, y: 2))
    #expect(base - offset == Point(x: 2, y: 6))
}
