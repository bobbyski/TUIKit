/// Insets from a rectangle's edges, in cells.
public struct EdgeInsets: Hashable, Codable, Sendable {
    /// Inset from the top edge.
    public var top: Int

    /// Inset from the left edge.
    public var left: Int

    /// Inset from the bottom edge.
    public var bottom: Int

    /// Inset from the right edge.
    public var right: Int

    /// No insets.
    public static let zero = EdgeInsets()

    /// Creates edge insets.
    ///
    /// - Parameters:
    ///   - top: Inset from the top edge.
    ///   - left: Inset from the left edge.
    ///   - bottom: Inset from the bottom edge.
    ///   - right: Inset from the right edge.
    public init(top: Int = 0, left: Int = 0, bottom: Int = 0, right: Int = 0) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }

    /// Creates uniform insets on all edges.
    ///
    /// - Parameter all: Inset applied to every edge.
    public init(all: Int) {
        self.init(top: all, left: all, bottom: all, right: all)
    }

    /// Shrinks a rectangle by these insets, clamping to zero size.
    ///
    /// - Parameter rect: Rectangle to inset.
    /// - Returns: The inset rectangle.
    public func inset(_ rect: Rect) -> Rect {
        Rect(
            x: rect.minX + left,
            y: rect.minY + top,
            width: rect.size.width - left - right,
            height: rect.size.height - top - bottom
        )
    }
}

/// AppKit-flavored edge/center pinning for the default layout pass.
///
/// A view with anchors gets its frame computed by its parent's default
/// `layoutSubviews()`; layout containers (stacks, grids) own their children's
/// frames and ignore anchors. Each axis resolves independently:
///
/// ```text
///   leading + trailing        stretch between the edges
///   leading|trailing + length pin to one edge at a fixed length
///   length + center           center at a fixed length
///   center alone              center at the preferred/current length
///   nothing                   keep the current frame value
/// ```
///
/// `width`/`height` fall back to the view's `intrinsicContentSize` when
/// unset and a center or single-edge pin needs a length.
public struct AnchorSet: Hashable, Sendable {
    /// Inset from the parent's leading (left) edge, when pinned.
    public var leading: Int?

    /// Inset from the parent's trailing (right) edge, when pinned.
    public var trailing: Int?

    /// Inset from the parent's top edge, when pinned.
    public var top: Int?

    /// Inset from the parent's bottom edge, when pinned.
    public var bottom: Int?

    /// Fixed width, when set.
    public var width: Int?

    /// Fixed height, when set.
    public var height: Int?

    /// Whether the view centers horizontally.
    public var centerX: Bool

    /// Whether the view centers vertically.
    public var centerY: Bool

    /// Creates an anchor set.
    ///
    /// - Parameters:
    ///   - leading: Inset from the parent's leading edge, when pinned.
    ///   - trailing: Inset from the parent's trailing edge, when pinned.
    ///   - top: Inset from the parent's top edge, when pinned.
    ///   - bottom: Inset from the parent's bottom edge, when pinned.
    ///   - width: Fixed width, when set.
    ///   - height: Fixed height, when set.
    ///   - centerX: Whether the view centers horizontally.
    ///   - centerY: Whether the view centers vertically.
    public init(
        leading: Int? = nil,
        trailing: Int? = nil,
        top: Int? = nil,
        bottom: Int? = nil,
        width: Int? = nil,
        height: Int? = nil,
        centerX: Bool = false,
        centerY: Bool = false
    ) {
        self.leading = leading
        self.trailing = trailing
        self.top = top
        self.bottom = bottom
        self.width = width
        self.height = height
        self.centerX = centerX
        self.centerY = centerY
    }

    /// Fills the parent, optionally inset on every edge.
    ///
    /// - Parameter inset: Uniform inset from all edges.
    /// - Returns: Anchors that stretch to the parent's bounds.
    public static func fill(inset: Int = 0) -> AnchorSet {
        AnchorSet(leading: inset, trailing: inset, top: inset, bottom: inset)
    }

    /// Centers the view at a size (or its preferred size when omitted).
    ///
    /// - Parameters:
    ///   - width: Fixed width, or `nil` to use the preferred width.
    ///   - height: Fixed height, or `nil` to use the preferred height.
    /// - Returns: Anchors that center the view both ways.
    public static func centered(width: Int? = nil, height: Int? = nil) -> AnchorSet {
        AnchorSet(width: width, height: height, centerX: true, centerY: true)
    }

    /// Resolves the frame for a view in its parent's bounds.
    ///
    /// - Parameters:
    ///   - bounds: Parent bounds.
    ///   - current: The view's current frame (under-constrained axes keep
    ///     their current values).
    ///   - preferred: The view's preferred size, when it has one.
    /// - Returns: The resolved frame.
    public func resolvedFrame(in bounds: Rect, current: Rect, preferred: Size?) -> Rect {
        let horizontal = Self.resolveAxis(
            span: bounds.size.width,
            leadingInset: leading,
            trailingInset: trailing,
            length: width ?? (needsWidthFallback ? preferred?.width : nil),
            centered: centerX,
            currentStart: current.minX,
            currentLength: current.size.width
        )

        let vertical = Self.resolveAxis(
            span: bounds.size.height,
            leadingInset: top,
            trailingInset: bottom,
            length: height ?? (needsHeightFallback ? preferred?.height : nil),
            centered: centerY,
            currentStart: current.minY,
            currentLength: current.size.height
        )

        return Rect(
            x: horizontal.start,
            y: vertical.start,
            width: horizontal.length,
            height: vertical.length
        )
    }

    // Whether the horizontal axis will need a length from somewhere.
    private var needsWidthFallback: Bool {
        width == nil && !(leading != nil && trailing != nil)
    }

    // Whether the vertical axis will need a length from somewhere.
    private var needsHeightFallback: Bool {
        height == nil && !(top != nil && bottom != nil)
    }

    // Resolves one axis to (start, length).
    private static func resolveAxis(
        span: Int,
        leadingInset: Int?,
        trailingInset: Int?,
        length: Int?,
        centered: Bool,
        currentStart: Int,
        currentLength: Int
    ) -> (start: Int, length: Int) {
        if let leadingInset, let trailingInset {
            return (leadingInset, max(0, span - leadingInset - trailingInset))
        }

        let resolvedLength = length ?? currentLength

        if let leadingInset {
            return (leadingInset, resolvedLength)
        }

        if let trailingInset {
            return (span - trailingInset - resolvedLength, resolvedLength)
        }

        if centered {
            return ((span - resolvedLength) / 2, resolvedLength)
        }

        return (currentStart, resolvedLength)
    }
}
