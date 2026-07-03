/// One segment of a `StatusBar`.
@MainActor
public final class StatusBarSegment {
    /// The one-row control the segment hosts.
    public let content: View

    /// Smallest width in cells. `nil` means the content's natural width.
    public var minimumWidth: Int?

    /// Largest width in cells, when limited.
    public var maximumWidth: Int?

    /// Desired share of the leftover row, as a percentage weight.
    ///
    /// Zero-percentage segments stay at their minimum width.
    public var percentage: Int

    init(content: View, minimumWidth: Int?, maximumWidth: Int?, percentage: Int) {
        self.content = content
        self.minimumWidth = minimumWidth
        self.maximumWidth = maximumWidth
        self.percentage = max(0, percentage)
    }
}

/// One-row segmented container, typically pinned to a window bottom.
///
/// ```text
///   Ready — 3 files selected           │ Live │ [ Ocean ▾ ]
///   └────────── 100% ─────────┘          └fit┘   └─fit───┘
/// ```
///
/// Each segment hosts any one-row control — labels, toggle buttons,
/// pop-up menus — and declares how it claims width: a minimum (defaulting
/// to the content's natural width), an optional maximum, and a
/// `percentage` weight for sharing the leftover. Resolution mirrors the
/// stack algorithm: minimums are honored first, the leftover is split by
/// percentage with deterministic remainders to the earliest segments, and
/// maximums clamp. Optional `│` separators come from the border slot.
///
/// ```swift
/// let bar = StatusBar()
/// bar.addSegment(statusLabel, percentage: 100)
/// bar.addSegment(liveToggle)
/// bar.addSegment(themePopUp)
/// bar.anchors = AnchorSet(leading: 0, trailing: 0, bottom: 0, height: 1)
/// ```
@MainActor
public final class StatusBar: View {
    /// Segments in display order.
    public private(set) var segments: [StatusBarSegment] = []

    /// Whether `│` separators draw between segments.
    public var showsSeparators = true {
        didSet {
            if showsSeparators != oldValue {
                setNeedsLayout()
            }
        }
    }

    // Separators are real connected Dividers, so an enclosing Panel welds
    // them into its border (┴ where the bar sits on the bottom row).
    private var separators: [Divider] = []

    /// Creates an empty status bar.
    public init() {
        super.init(frame: .zero)
    }

    /// Appends a segment hosting a control.
    ///
    /// - Parameters:
    ///   - content: One-row control to host.
    ///   - minimumWidth: Smallest width; `nil` uses the content's natural
    ///     width.
    ///   - maximumWidth: Largest width, when limited.
    ///   - percentage: Weight for sharing leftover width. Defaults to 0
    ///     (fixed at the minimum).
    /// - Returns: The created segment.
    @discardableResult
    public func addSegment(
        _ content: View,
        minimumWidth: Int? = nil,
        maximumWidth: Int? = nil,
        percentage: Int = 0
    ) -> StatusBarSegment {
        let segment = StatusBarSegment(
            content: content,
            minimumWidth: minimumWidth,
            maximumWidth: maximumWidth,
            percentage: percentage
        )

        segments.append(segment)
        addSubview(content)
        setNeedsLayout()
        return segment
    }

    /// One row at the sum of the minimum widths.
    public override var intrinsicContentSize: Size? {
        let widths = segments.reduce(0) { $0 + resolvedMinimum(of: $1) }
        let separators = showsSeparators ? max(0, segments.count - 1) : 0
        return Size(width: widths + separators, height: 1)
    }

    /// Resolves segment widths and positions the hosted controls.
    public override func layoutSubviews() {
        guard !segments.isEmpty else {
            return
        }

        let separatorWidth = showsSeparators ? segments.count - 1 : 0
        let available = max(0, bounds.size.width - separatorWidth)

        // Start every segment at its minimum.
        var widths = segments.map { resolvedMinimum(of: $0) }
        let leftover = available - widths.reduce(0, +)

        // Split the leftover by percentage weight, clamping to maximums;
        // remainder cells go one each to the earliest weighted segments.
        let totalWeight = segments.reduce(0) { $0 + $1.percentage }

        if leftover > 0, totalWeight > 0 {
            var extras = segments.map { segment in
                segment.percentage > 0 ? leftover * segment.percentage / totalWeight : 0
            }

            var remainder = leftover - extras.reduce(0, +)

            for (index, segment) in segments.enumerated()
            where segment.percentage > 0 && remainder > 0 {
                extras[index] += 1
                remainder -= 1
            }

            for (index, segment) in segments.enumerated() {
                widths[index] += extras[index]

                if let maximum = segment.maximumWidth, widths[index] > maximum {
                    widths[index] = maximum
                }
            }
        } else if leftover < 0 {
            // Too narrow: shrink from the trailing end, honoring nothing —
            // better truncated than overlapping.
            var deficit = -leftover

            for index in stride(from: widths.count - 1, through: 0, by: -1) where deficit > 0 {
                let cut = min(widths[index], deficit)
                widths[index] -= cut
                deficit -= cut
            }
        }

        var x = 0

        for (index, segment) in segments.enumerated() {
            segment.content.frame = Rect(x: x, y: 0, width: widths[index], height: 1)
            x += widths[index]

            if showsSeparators, index < segments.count - 1 {
                separator(at: index).frame = Rect(x: x, y: 0, width: 1, height: 1)
                x += 1
            }
        }

        // Hide any leftover separators (and all of them when disabled).
        let needed = showsSeparators ? max(0, segments.count - 1) : 0

        for (index, divider) in separators.enumerated() {
            divider.isHidden = index >= needed
        }
    }

    // Reuses or creates the divider between segment `index` and the next.
    private func separator(at index: Int) -> Divider {
        while separators.count <= index {
            let divider = Divider(axis: .vertical)
            separators.append(divider)
            addSubview(divider)
        }

        separators[index].isHidden = false
        return separators[index]
    }

    // A segment's effective minimum: explicit, else content natural width.
    private func resolvedMinimum(of segment: StatusBarSegment) -> Int {
        if let minimum = segment.minimumWidth {
            return max(0, minimum)
        }

        return segment.content.intrinsicContentSize?.width ?? 0
    }
}
