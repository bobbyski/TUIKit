import Testing
@testable import TUIKit

/// View with a declared natural size, for fit-content layout tests.
@MainActor
private final class SizedView: View {
    var natural: Size?

    init(natural: Size? = nil) {
        self.natural = natural
        super.init(frame: .zero)
    }

    override var intrinsicContentSize: Size? {
        natural
    }
}

// MARK: - Anchors

@Test @MainActor func anchorsFillStretchesWithInsets() {
    let parent = View(frame: Rect(x: 0, y: 0, width: 20, height: 10))
    let child = View()

    child.anchors = .fill(inset: 2)
    parent.addSubview(child)
    parent.layoutIfNeeded()

    #expect(child.frame == Rect(x: 2, y: 2, width: 16, height: 6))
}

@Test @MainActor func anchorsPinToOneEdgeWithFixedLength() {
    let parent = View(frame: Rect(x: 0, y: 0, width: 20, height: 10))
    let sidebar = View()

    sidebar.anchors = AnchorSet(trailing: 1, top: 0, bottom: 0, width: 6)
    parent.addSubview(sidebar)
    parent.layoutIfNeeded()

    #expect(sidebar.frame == Rect(x: 13, y: 0, width: 6, height: 10))
}

@Test @MainActor func anchorsCenterUsesPreferredSize() {
    let parent = View(frame: Rect(x: 0, y: 0, width: 20, height: 10))
    let badge = SizedView(natural: Size(width: 6, height: 2))

    badge.anchors = .centered()
    parent.addSubview(badge)
    parent.layoutIfNeeded()

    #expect(badge.frame == Rect(x: 7, y: 4, width: 6, height: 2))
}

@Test @MainActor func underConstrainedAxesKeepCurrentValues() {
    let parent = View(frame: Rect(x: 0, y: 0, width: 20, height: 10))
    let child = View(frame: Rect(x: 3, y: 2, width: 5, height: 4))

    // Horizontal is fully pinned; vertical says nothing.
    child.anchors = AnchorSet(leading: 1, trailing: 1)
    parent.addSubview(child)
    parent.layoutIfNeeded()

    #expect(child.frame == Rect(x: 1, y: 2, width: 18, height: 4))
}

// MARK: - Stacks

@Test @MainActor func vstackSplitsSpaceAmongFlexibleChildren() {
    let stack = VStack(frame: Rect(x: 0, y: 0, width: 10, height: 9), spacing: 1)
    let top = View()
    let bottom = View()

    stack.addSubview(top)
    stack.addSubview(bottom)
    stack.layoutIfNeeded()

    #expect(top.frame == Rect(x: 0, y: 0, width: 10, height: 4))
    #expect(bottom.frame == Rect(x: 0, y: 5, width: 10, height: 4))
}

@Test @MainActor func hstackFixedChildrenKeepNaturalWidths() {
    let stack = HStack(frame: Rect(x: 0, y: 0, width: 20, height: 3), spacing: 1)
    let label = SizedView(natural: Size(width: 5, height: 1))
    let field = View()
    let button = SizedView(natural: Size(width: 4, height: 1))

    stack.addSubview(label)
    stack.addSubview(field)
    stack.addSubview(button)
    stack.layoutIfNeeded()

    // 20 wide, 2 spacing -> 18 for children; fixed 5 + 4 leaves 9 for field.
    #expect(label.frame == Rect(x: 0, y: 0, width: 5, height: 3))
    #expect(field.frame == Rect(x: 6, y: 0, width: 9, height: 3))
    #expect(button.frame == Rect(x: 16, y: 0, width: 4, height: 3))
}

@Test @MainActor func stackRemainderGoesToEarliestFlexibleChildren() {
    let stack = HStack(frame: Rect(x: 0, y: 0, width: 10, height: 1))
    let first = View()
    let second = View()
    let third = View()

    stack.addSubview(first)
    stack.addSubview(second)
    stack.addSubview(third)
    stack.layoutIfNeeded()

    // 10 / 3 = 3 remainder 1 -> widths 4, 3, 3 deterministically.
    #expect(first.frame.size.width == 4)
    #expect(second.frame.size.width == 3)
    #expect(third.frame.size.width == 3)
    #expect(third.frame.maxX == 10)
}

@Test @MainActor func stackSkipsHiddenChildren() {
    let stack = HStack(frame: Rect(x: 0, y: 0, width: 12, height: 1))
    let visible = View()
    let hidden = View()

    stack.addSubview(visible)
    stack.addSubview(hidden)
    hidden.isHidden = true
    stack.layoutIfNeeded()

    #expect(visible.frame.size.width == 12)
}

@Test @MainActor func stackInsetsAndCenterAlignment() {
    let stack = VStack(
        frame: Rect(x: 0, y: 0, width: 12, height: 8),
        alignment: .center,
        insets: EdgeInsets(all: 1)
    )
    let badge = SizedView(natural: Size(width: 4, height: 2))

    stack.addSubview(badge)
    stack.layoutIfNeeded()

    // Content is x 1..<11; centered 4-wide -> x = 1 + (10-4)/2 = 4.
    #expect(badge.frame.minX == 4)
    #expect(badge.frame.size.width == 4)
    #expect(badge.frame.minY == 1)
}

@Test @MainActor func stackRespectsMinimumAndMaximumSizes() {
    let stack = HStack(frame: Rect(x: 0, y: 0, width: 20, height: 1))
    let capped = View()
    let open = View()

    capped.maximumSize = Size(width: 4, height: 1)
    stack.addSubview(capped)
    stack.addSubview(open)
    stack.layoutIfNeeded()

    #expect(capped.frame.size.width == 4)
    #expect(open.frame.size.width == 10, "flexible split is computed before clamping")
}

@Test @MainActor func nestedStackReportsFitContentSize() {
    let inner = HStack(spacing: 1)
    inner.addSubview(SizedView(natural: Size(width: 3, height: 1)))
    inner.addSubview(SizedView(natural: Size(width: 4, height: 2)))

    #expect(inner.intrinsicContentSize == Size(width: 8, height: 2))
}

// MARK: - Grid

@Test @MainActor func gridResolvesFixedFitAndFlexibleColumns() {
    let grid = GridView(
        columns: [.fixed(4), .fitContent, .flexible()],
        frame: Rect(x: 0, y: 0, width: 20, height: 3)
    )

    let a = View()
    let b = SizedView(natural: Size(width: 6, height: 1))
    let c = View()

    grid.place(a, column: 0, row: 0)
    grid.place(b, column: 1, row: 0)
    grid.place(c, column: 2, row: 0)
    grid.setRow(0, .flexible())
    grid.layoutIfNeeded()

    #expect(a.frame == Rect(x: 0, y: 0, width: 4, height: 3))
    #expect(b.frame == Rect(x: 4, y: 0, width: 6, height: 3))
    #expect(c.frame == Rect(x: 10, y: 0, width: 10, height: 3))
}

@Test @MainActor func gridSpansCoverMultipleTracks() {
    let grid = GridView(
        columns: [.flexible(), .flexible()],
        frame: Rect(x: 0, y: 0, width: 10, height: 4),
        columnSpacing: 2
    )

    let header = View()
    let left = View()
    let right = View()

    grid.place(header, column: 0, row: 0, columnSpan: 2)
    grid.place(left, column: 0, row: 1)
    grid.place(right, column: 1, row: 1)
    grid.setRow(0, .fixed(1))
    grid.setRow(1, .flexible())
    grid.layoutIfNeeded()

    // Columns: (10 - 2 spacing) / 2 = 4 each; header spans both + spacing.
    #expect(header.frame == Rect(x: 0, y: 0, width: 10, height: 1))
    #expect(left.frame == Rect(x: 0, y: 1, width: 4, height: 3))
    #expect(right.frame == Rect(x: 6, y: 1, width: 4, height: 3))
}

@Test @MainActor func gridFitRowsUseTallestSingleSpanChild() {
    let grid = GridView(
        columns: [.flexible()],
        frame: Rect(x: 0, y: 0, width: 8, height: 10)
    )

    let short = SizedView(natural: Size(width: 2, height: 1))
    let tall = SizedView(natural: Size(width: 2, height: 3))

    grid.place(short, column: 0, row: 0)
    grid.place(tall, column: 0, row: 1)
    grid.layoutIfNeeded()

    #expect(short.frame.size.height == 1)
    #expect(tall.frame.minY == 1)
    #expect(tall.frame.size.height == 3)
}

@Test @MainActor func gridFlexibleWeightsShareProportionally() {
    let grid = GridView(
        columns: [.flexible(1), .flexible(3)],
        frame: Rect(x: 0, y: 0, width: 16, height: 1)
    )

    let narrow = View()
    let wide = View()

    grid.place(narrow, column: 0, row: 0)
    grid.place(wide, column: 1, row: 0)
    grid.setRow(0, .flexible())
    grid.layoutIfNeeded()

    #expect(narrow.frame.size.width == 4)
    #expect(wide.frame.size.width == 12)
}

// MARK: - Layout Pass Integration

@Test @MainActor func renderRunsPendingLayout() {
    let root = View(frame: Rect(x: 0, y: 0, width: 8, height: 2))
    let child = View()
    child.anchors = .fill(inset: 1)
    root.addSubview(child)

    _ = SceneRenderer(root: root).render(size: Size(width: 8, height: 2))

    #expect(child.frame == Rect(x: 1, y: 1, width: 6, height: 0))
}

@Test @MainActor func sizeChangeTriggersRelayout() {
    let stack = HStack(frame: Rect(x: 0, y: 0, width: 10, height: 1))
    let child = View()
    stack.addSubview(child)
    stack.layoutIfNeeded()

    #expect(child.frame.size.width == 10)

    stack.frame = Rect(x: 0, y: 0, width: 6, height: 1)
    stack.layoutIfNeeded()

    #expect(child.frame.size.width == 6)
}
