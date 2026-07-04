/// Cross-axis placement for stacked children.
public enum StackAlignment: Hashable, Sendable {
    /// Pin to the leading (left/top) edge.
    case leading

    /// Center on the cross axis.
    case center

    /// Pin to the trailing (right/bottom) edge.
    case trailing

    /// Stretch to the full cross-axis extent.
    case fill
}

/// Lays out children in a line — the shared engine behind `HStack` and
/// `VStack`.
///
/// Children with an `intrinsicContentSize` keep their natural main-axis
/// length (clamped by their `minimumSize`/`maximumSize`); children without
/// one are flexible and share the leftover space equally, with any remainder
/// cells distributed to the earliest flexible children so the result is
/// deterministic. Hidden children are skipped entirely.
///
/// ```text
///   HStack(spacing: 1):  [fixed][ flex ][ flex ][fixed]
///                              ^ leftover split equally ^
/// ```
///
/// Stacks own their children's frames; child `anchors` are ignored here.
@MainActor
open class StackView: TUIView {
    /// Direction of a stack's main axis.
    public enum Axis: Hashable, Sendable {
        /// Children flow left to right.
        case horizontal

        /// Children flow top to bottom.
        case vertical
    }

    /// The stack's main axis.
    public let axis: Axis

    /// Cells between adjacent children.
    public var spacing: Int {
        didSet {
            if spacing != oldValue {
                setNeedsLayout()
            }
        }
    }

    /// Padding inside the stack's bounds.
    public var insets: EdgeInsets {
        didSet {
            if insets != oldValue {
                setNeedsLayout()
            }
        }
    }

    /// Cross-axis placement for children.
    public var alignment: StackAlignment {
        didSet {
            if alignment != oldValue {
                setNeedsLayout()
            }
        }
    }

    /// Creates a stack.
    ///
    /// - Parameters:
    ///   - axis: Direction of the main axis.
    ///   - frame: Position and size in the parent's coordinate space.
    ///   - spacing: Cells between adjacent children.
    ///   - alignment: Cross-axis placement for children.
    ///   - insets: Padding inside the stack's bounds.
    public init(
        axis: Axis,
        frame: Rect = .zero,
        spacing: Int = 0,
        alignment: StackAlignment = .fill,
        insets: EdgeInsets = .zero
    ) {
        self.axis = axis
        self.spacing = spacing
        self.alignment = alignment
        self.insets = insets
        super.init(frame: frame)
    }

    /// The natural size of the stacked content, when any child has one.
    ///
    /// Main axis: sum of child natural lengths plus spacing. Cross axis: the
    /// largest child natural length. Flexible children contribute zero, so
    /// nesting a stack inside another treats it as fit-content when its
    /// children have natural sizes.
    open override var intrinsicContentSize: Size? {
        let visible = subviews.filter { !$0.isHidden }
        let intrinsics = visible.compactMap(\.intrinsicContentSize)

        guard !intrinsics.isEmpty else {
            return nil
        }

        let mainSum = intrinsics.map { mainLength(of: $0) }.reduce(0, +)
        let crossMax = intrinsics.map { crossLength(of: $0) }.max() ?? 0
        let spacingTotal = spacing * max(0, visible.count - 1)

        return size(
            main: mainSum + spacingTotal + mainLength(of: insetTotals),
            cross: crossMax + crossLength(of: insetTotals)
        )
    }

    /// Distributes children along the main axis.
    open override func layoutSubviews() {
        let content = insets.inset(bounds)
        let visible = subviews.filter { !$0.isHidden }

        guard !visible.isEmpty else {
            return
        }

        let spacingTotal = spacing * (visible.count - 1)
        let availableMain = max(0, mainLength(of: content.size) - spacingTotal)

        // Fixed children keep their natural length; flexible ones share the
        // rest, earliest children absorbing any remainder cells.
        let naturalLengths: [Int?] = visible.map { child in
            child.intrinsicContentSize.map { clampMain(mainLength(of: $0), for: child) }
        }

        let fixedTotal = naturalLengths.compactMap { $0 }.reduce(0, +)
        let flexibleCount = naturalLengths.filter { $0 == nil }.count
        let leftover = max(0, availableMain - fixedTotal)
        let flexibleEach = flexibleCount > 0 ? leftover / flexibleCount : 0
        var flexibleRemainder = flexibleCount > 0 ? leftover % flexibleCount : 0

        var offset = mainStart(of: content)

        for (index, child) in visible.enumerated() {
            var length: Int

            if let natural = naturalLengths[index] {
                length = natural
            } else {
                length = flexibleEach + (flexibleRemainder > 0 ? 1 : 0)
                flexibleRemainder -= flexibleRemainder > 0 ? 1 : 0
                length = clampMain(length, for: child)
            }

            child.frame = frameFor(
                child: child,
                mainOffset: offset,
                mainLength: length,
                content: content
            )

            offset += length + spacing
        }
    }

    // MARK: - Axis Helpers

    private var insetTotals: Size {
        Size(width: insets.left + insets.right, height: insets.top + insets.bottom)
    }

    private func mainLength(of size: Size) -> Int {
        axis == .horizontal ? size.width : size.height
    }

    private func crossLength(of size: Size) -> Int {
        axis == .horizontal ? size.height : size.width
    }

    private func size(main: Int, cross: Int) -> Size {
        axis == .horizontal
            ? Size(width: main, height: cross)
            : Size(width: cross, height: main)
    }

    private func mainStart(of rect: Rect) -> Int {
        axis == .horizontal ? rect.minX : rect.minY
    }

    private func clampMain(_ length: Int, for child: TUIView) -> Int {
        var clamped = max(length, mainLength(of: child.minimumSize))

        if let maximum = child.maximumSize {
            clamped = min(clamped, mainLength(of: maximum))
        }

        return clamped
    }

    // Builds a child's frame from its main-axis slot and the alignment.
    private func frameFor(
        child: TUIView,
        mainOffset: Int,
        mainLength: Int,
        content: Rect
    ) -> Rect {
        let contentCross = crossLength(of: content.size)
        let naturalCross = child.intrinsicContentSize.map { crossLength(of: $0) }

        let crossLengthValue: Int
        let crossOffsetValue: Int
        let crossStart = axis == .horizontal ? content.minY : content.minX

        switch alignment {
        case .fill:
            crossLengthValue = contentCross
            crossOffsetValue = crossStart

        case .leading:
            crossLengthValue = min(naturalCross ?? contentCross, contentCross)
            crossOffsetValue = crossStart

        case .center:
            crossLengthValue = min(naturalCross ?? contentCross, contentCross)
            crossOffsetValue = crossStart + (contentCross - crossLengthValue) / 2

        case .trailing:
            crossLengthValue = min(naturalCross ?? contentCross, contentCross)
            crossOffsetValue = crossStart + contentCross - crossLengthValue
        }

        return axis == .horizontal
            ? Rect(x: mainOffset, y: crossOffsetValue, width: mainLength, height: crossLengthValue)
            : Rect(x: crossOffsetValue, y: mainOffset, width: crossLengthValue, height: mainLength)
    }
}

/// Horizontal stack: children flow left to right.
@MainActor
public final class HStack: StackView {
    /// Creates a horizontal stack.
    ///
    /// - Parameters:
    ///   - frame: Position and size in the parent's coordinate space.
    ///   - spacing: Cells between adjacent children.
    ///   - alignment: Cross-axis (vertical) placement for children.
    ///   - insets: Padding inside the stack's bounds.
    public init(
        frame: Rect = .zero,
        spacing: Int = 0,
        alignment: StackAlignment = .fill,
        insets: EdgeInsets = .zero
    ) {
        super.init(axis: .horizontal, frame: frame, spacing: spacing, alignment: alignment, insets: insets)
    }
}

/// Vertical stack: children flow top to bottom.
@MainActor
public final class VStack: StackView {
    /// Creates a vertical stack.
    ///
    /// - Parameters:
    ///   - frame: Position and size in the parent's coordinate space.
    ///   - spacing: Cells between adjacent children.
    ///   - alignment: Cross-axis (horizontal) placement for children.
    ///   - insets: Padding inside the stack's bounds.
    public init(
        frame: Rect = .zero,
        spacing: Int = 0,
        alignment: StackAlignment = .fill,
        insets: EdgeInsets = .zero
    ) {
        super.init(axis: .vertical, frame: frame, spacing: spacing, alignment: alignment, insets: insets)
    }
}
