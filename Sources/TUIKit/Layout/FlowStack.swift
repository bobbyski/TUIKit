/// A stack that wraps: children fill a row, then start the next.
///
/// ```text
///   [swift] [terminal] [tui]
///   [concurrency] [testing]        ← wrapped where the row ran out
/// ```
///
/// The missing `StackView` mode: tag clouds, button rows that reflow when
/// the terminal narrows, chips. Children keep their natural width (a child
/// without one gets `defaultChildWidth`) and their natural height; each
/// row is as tall as its tallest child. Hidden children are skipped. The
/// natural height depends on the width — a flow stack in a vertical stack
/// reports the height it needs at its current width.
///
/// ```swift
/// let tags = FlowStack(spacing: 1, lineSpacing: 0)
/// for tag in tags { tags.addSubview(Button(tag) {}) }
/// ```
@MainActor
public final class FlowStack: TUIView {
    /// Cells between children on a row.
    public var spacing: Int {
        didSet {
            if spacing != oldValue {
                setNeedsLayout()
            }
        }
    }

    /// Rows between lines.
    public var lineSpacing: Int {
        didSet {
            if lineSpacing != oldValue {
                setNeedsLayout()
            }
        }
    }

    /// Padding inside the bounds.
    public var insets: EdgeInsets {
        didSet {
            if insets != oldValue {
                setNeedsLayout()
            }
        }
    }

    /// Width given to a child with no natural size.
    public var defaultChildWidth = 10

    /// Creates a flow stack.
    ///
    /// - Parameters:
    ///   - spacing: Cells between children on a row.
    ///   - lineSpacing: Rows between lines.
    ///   - insets: Padding inside the bounds.
    public init(spacing: Int = 1, lineSpacing: Int = 0, insets: EdgeInsets = .zero) {
        self.spacing = spacing
        self.lineSpacing = lineSpacing
        self.insets = insets
        super.init(frame: .zero)
    }

    // The height the last layout needed at its width. A flow's height
    // depends on its width, which its parent only knows after a first
    // layout — so the first measurement guesses one row, and the layout
    // that follows corrects the parent.
    private var measuredHeight: Int?

    /// The rows needed at the current width — the last laid-out height, or
    /// a one-row guess before any layout.
    public override var intrinsicContentSize: Size? {
        if let measuredHeight {
            return Size(width: rowsWidthHint, height: measuredHeight)
        }

        let rows = rows(forWidth: rowsWidthHint)
        return Size(width: rowsWidthHint, height: height(of: rows))
    }

    /// Flows the children, and re-measures the ancestors when the rows
    /// needed at this width differ from what they were told.
    public override func layoutSubviews() {
        let content = insets.inset(bounds)
        let rows = rows(forWidth: bounds.size.width)
        var y = content.minY

        for row in rows {
            var x = content.minX

            for child in row.children {
                let size = childSize(child)
                child.frame = Rect(x: x, y: y, width: size.width, height: size.height)
                x += size.width + spacing
            }

            y += row.height + lineSpacing
        }

        let needed = height(of: rows)

        if needed != measuredHeight {
            measuredHeight = needed
            var view = superview

            while let current = view {
                current.setNeedsLayout()
                view = current.superview
            }
        }
    }

    private func height(of rows: [Row]) -> Int {
        rows.reduce(0) { $0 + $1.height } + lineSpacing * max(0, rows.count - 1) + insets.top + insets.bottom
    }

    // MARK: - Flow

    private struct Row {
        var children: [TUIView] = []
        var height = 0
        var width = 0
    }

    private var rowsWidthHint: Int {
        subviews.filter { !$0.isHidden }.map { childSize($0).width }.reduce(0, +)
            + spacing * max(0, subviews.count - 1) + insets.left + insets.right
    }

    private func childSize(_ child: TUIView) -> Size {
        let natural = child.intrinsicContentSize ?? Size(width: defaultChildWidth, height: 1)
        var width = max(natural.width, child.minimumSize.width)
        var height = max(natural.height, child.minimumSize.height)

        if let maximum = child.maximumSize {
            width = min(width, maximum.width)
            height = min(height, maximum.height)
        }

        return Size(width: max(1, width), height: max(1, height))
    }

    private func rows(forWidth width: Int) -> [Row] {
        let available = max(1, width - insets.left - insets.right)
        var rows: [Row] = []
        var current = Row()

        for child in subviews where !child.isHidden {
            let size = childSize(child)
            let needed = current.children.isEmpty ? size.width : current.width + spacing + size.width

            if !current.children.isEmpty, needed > available {
                rows.append(current)
                current = Row()
            }

            current.width = current.children.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.children.append(child)
        }

        if !current.children.isEmpty {
            rows.append(current)
        }

        return rows
    }
}
