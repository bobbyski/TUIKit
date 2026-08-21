/// One segment of a `StatusBar`.
@MainActor
public final class StatusBarSegment {
    /// The one-row control the segment hosts.
    public let content: TUIView

    /// Smallest width in cells. `nil` means the content's natural width.
    public var minimumWidth: Int?

    /// Largest width in cells, when limited.
    public var maximumWidth: Int?

    /// Desired share of the leftover row, as a percentage weight.
    ///
    /// Zero-percentage segments stay at their minimum width.
    public var percentage: Int

    /// What gives way when the bar is too narrow: the LOWEST priority loses
    /// width first (ties: trailing segments first). Default 0.
    public var priority: Int

    init(content: TUIView, minimumWidth: Int?, maximumWidth: Int?, percentage: Int, priority: Int) {
        self.content = content
        self.minimumWidth = minimumWidth
        self.maximumWidth = maximumWidth
        self.percentage = max(0, percentage)
        self.priority = priority
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
public final class StatusBar: TUIView {
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

    /// The message currently flashed over the segments, if any.
    public private(set) var flashText: String?

    // Cancels the pending flash expiry.
    private var cancelFlashExpiry: (() -> Void)?

    // How an expiry is scheduled — the app's timer by default, or a test's
    // hand-cranked stand-in. Returns the cancel.
    var scheduleFlash: ((Duration, @escaping @MainActor () -> Void) -> (() -> Void))?

    /// Shows a message across the whole bar for a while, then restores the
    /// segments — "Saved", "Copied 3 items", "Connection lost".
    ///
    /// A new flash replaces a running one. The wait rides the app's timer;
    /// with no running `App` (a bare test window) the message stays until
    /// `clearFlash()`.
    ///
    /// - Parameters:
    ///   - text: The message.
    ///   - duration: How long it shows. Defaults to three seconds.
    public func flash(_ text: String, for duration: Duration = .seconds(3)) {
        cancelFlashExpiry?()
        cancelFlashExpiry = nil
        flashText = text
        setNeedsLayout()
        setNeedsDisplay()

        let scheduler = scheduleFlash ?? appScheduler

        cancelFlashExpiry = scheduler?(duration) { [weak self] in
            self?.cancelFlashExpiry = nil
            self?.clearFlash()
        }
    }

    /// Removes a flashed message early and restores the segments.
    public func clearFlash() {
        cancelFlashExpiry?()
        cancelFlashExpiry = nil

        guard flashText != nil else {
            return
        }

        flashText = nil
        setNeedsLayout()
        setNeedsDisplay()
    }

    private var appScheduler: ((Duration, @escaping @MainActor () -> Void) -> (() -> Void))? {
        guard let app = owningWindow?.app else {
            return nil
        }

        return { delay, body in
            let timer = app.schedule(after: delay, body)
            return { timer.cancel() }
        }
    }

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
    ///   - priority: What gives way first when too narrow — lowest loses
    ///     first. Defaults to 0.
    /// - Returns: The created segment.
    @discardableResult
    public func addSegment(
        _ content: TUIView,
        minimumWidth: Int? = nil,
        maximumWidth: Int? = nil,
        percentage: Int = 0,
        priority: Int = 0
    ) -> StatusBarSegment {
        let segment = StatusBarSegment(
            content: content,
            minimumWidth: minimumWidth,
            maximumWidth: maximumWidth,
            percentage: percentage,
            priority: priority
        )

        segments.append(segment)
        addSubview(content)
        setNeedsLayout()
        return segment
    }

    /// Paints the bar in the theme's `header` (chrome) slot behind the
    /// segments, so it reads as one strip like the menu bar. Segment controls
    /// that should blend in carry the header style too (see the demo).
    public override func draw(_ painter: Painter) {
        let header = effectiveTheme.header
        painter.fill(bounds, with: TerminalCell(character: " ", style: header))

        if let flashText {
            painter.write(" " + Label.truncated(flashText, width: max(0, bounds.size.width - 1)), at: .zero, style: header)
        }
    }

    /// One row at the sum of the minimum widths.
    public override var intrinsicContentSize: Size? {
        let widths = segments.reduce(0) { $0 + resolvedMinimum(of: $1) }
        let separators = showsSeparators ? max(0, segments.count - 1) : 0
        return Size(width: widths + separators, height: 1)
    }

    /// Resolves segment widths and positions the hosted controls.
    public override func layoutSubviews() {
        // A flash owns the whole row: segments and separators step aside.
        let flashing = flashText != nil

        for segment in segments {
            segment.content.isHidden = flashing
        }

        if flashing {
            for divider in separators {
                divider.isHidden = true
            }

            return
        }

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
            // Too narrow: the lowest-priority segments give up width first,
            // trailing ones first among equals — better truncated than
            // overlapping.
            var deficit = -leftover
            let order = segments.indices.sorted { a, b in
                let (pa, pb) = (segments[a].priority, segments[b].priority)
                return pa != pb ? pa < pb : a > b
            }

            for index in order where deficit > 0 {
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
