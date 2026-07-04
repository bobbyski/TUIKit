/// Two panes separated by a draggable one-cell divider.
///
/// ```text
///   ┌─────────┬──────────────┐        horizontal axis:
///   │  first  │    second    │        panes side by side,
///   │  pane   │     pane     │        divider is a │ column
///   └─────────┴──────────────┘
/// ```
///
/// The divider moves three ways: dragging it with the mouse (the window's
/// capture keeps the drag alive once grabbed), arrow keys while the split
/// view is focused (`←`/`→` on the horizontal axis, `↑`/`↓` on the
/// vertical), and Home/End to snap against the minimum sizes. Pane minimums
/// are respected by every path.
///
/// ```swift
/// let split = SplitView(axis: .horizontal, first: sidebar, second: editor)
/// split.minimumFirstLength = 12
/// split.setDividerPosition(20)
/// split.onDividerMoved = { position in save(position) }
/// ```
@MainActor
public final class SplitView: TUIView {
    /// Direction panes flow (`.horizontal` = side by side).
    public let axis: StackView.Axis

    /// Leading/top pane.
    public let first: TUIView

    /// Trailing/bottom pane.
    public let second: TUIView

    /// Smallest length of the first pane, in cells.
    public var minimumFirstLength = 0 {
        didSet {
            setNeedsLayout()
        }
    }

    /// Smallest length of the second pane, in cells.
    public var minimumSecondLength = 0 {
        didSet {
            setNeedsLayout()
        }
    }

    /// Called when the divider moves through interaction or
    /// `setDividerPosition(_:notify:)`.
    public var onDividerMoved: (Int) -> Void = { _ in }

    // First pane's length along the axis.
    private var dividerPosition: Int

    // Whether a divider drag is in flight.
    private var isDraggingDivider = false

    /// Creates a split view.
    ///
    /// - Parameters:
    ///   - axis: Direction panes flow. Defaults to `.horizontal`.
    ///   - first: Leading/top pane.
    ///   - second: Trailing/bottom pane.
    ///   - dividerPosition: Initial first-pane length. Defaults to half.
    public init(
        axis: StackView.Axis = .horizontal,
        first: TUIView,
        second: TUIView,
        dividerPosition: Int = -1
    ) {
        self.axis = axis
        self.first = first
        self.second = second
        self.dividerPosition = dividerPosition
        super.init(frame: .zero)
        addSubview(first)
        addSubview(second)
    }

    /// The first pane's current length along the axis.
    public var currentDividerPosition: Int {
        dividerPosition
    }

    /// Split views take keyboard focus to own the divider keys.
    public override var acceptsFirstResponder: Bool {
        true
    }

    /// Moves the divider programmatically, clamped to the minimums.
    ///
    /// - Parameters:
    ///   - position: First-pane length in cells.
    ///   - notify: Whether `onDividerMoved` fires. Defaults to silent.
    public func setDividerPosition(_ position: Int, notify: Bool = false) {
        let clamped = clampedDivider(position)

        guard clamped != dividerPosition else {
            return
        }

        dividerPosition = clamped
        setNeedsLayout()

        if notify {
            onDividerMoved(dividerPosition)
        }
    }

    /// Positions the panes on either side of the divider.
    public override func layoutSubviews() {
        // First layout with an unset position: split in half.
        if dividerPosition < 0 {
            dividerPosition = (totalLength - 1) / 2
        }

        dividerPosition = clampedDivider(dividerPosition)

        switch axis {
        case .horizontal:
            first.frame = Rect(x: 0, y: 0, width: dividerPosition, height: bounds.size.height)
            second.frame = Rect(
                x: dividerPosition + 1,
                y: 0,
                width: max(0, bounds.size.width - dividerPosition - 1),
                height: bounds.size.height
            )

        case .vertical:
            first.frame = Rect(x: 0, y: 0, width: bounds.size.width, height: dividerPosition)
            second.frame = Rect(
                x: 0,
                y: dividerPosition + 1,
                width: bounds.size.width,
                height: max(0, bounds.size.height - dividerPosition - 1)
            )
        }
    }

    /// Draws the divider line, emphasized while focused or dragging.
    public override func draw(_ painter: Painter) {
        let theme = effectiveTheme
        let characters = theme.borderStyle.characters ?? BorderStyle.single.characters!
        var style = theme.border

        // Focus/drag cue: recolor the line to the accent only — never bold or
        // inverse. Bold box-drawing glyphs render unevenly and read as a dashed
        // line, so this matches the Divider control (no cue on colorless themes).
        if isFirstResponder || isDraggingDivider, theme.accent != .standard {
            style.foreground = theme.accent
        }

        switch axis {
        case .horizontal:
            for y in 0..<bounds.size.height {
                painter.set(TerminalCell(character: characters.vertical, style: style), at: Point(x: dividerPosition, y: y))
            }

        case .vertical:
            for x in 0..<bounds.size.width {
                painter.set(TerminalCell(character: characters.horizontal, style: style), at: Point(x: x, y: dividerPosition))
            }
        }
    }

    /// Arrows move the divider; Home/End snap it against the minimums.
    public override func keyDown(_ key: KeyInput) -> Bool {
        guard key.modifiers.isEmpty else {
            return false
        }

        switch (key.key, axis) {
        case (.left, .horizontal), (.up, .vertical):
            moveDivider(by: -1)
            return true

        case (.right, .horizontal), (.down, .vertical):
            moveDivider(by: 1)
            return true

        case (.home, _):
            moveDivider(to: minimumFirstLength)
            return true

        case (.end, _):
            moveDivider(to: totalLength - 1 - minimumSecondLength)
            return true

        default:
            return false
        }
    }

    /// Press on the divider grabs it; drags follow the pointer.
    public override func mouseEvent(_ mouse: MouseInput) -> Bool {
        switch mouse.action {
        case .press where mouse.button == .left:
            guard pointerLength(of: mouse.position) == dividerPosition else {
                return false
            }

            isDraggingDivider = true
            setNeedsDisplay()
            return true

        case .drag:
            guard isDraggingDivider else {
                return false
            }

            moveDivider(to: pointerLength(of: mouse.position))
            return true

        case .release:
            guard isDraggingDivider else {
                return false
            }

            isDraggingDivider = false
            setNeedsDisplay()
            return true

        default:
            return false
        }
    }

    // MARK: - Divider internals

    // Available length along the axis.
    private var totalLength: Int {
        axis == .horizontal ? bounds.size.width : bounds.size.height
    }

    // Pointer coordinate along the axis.
    private func pointerLength(of position: Point) -> Int {
        axis == .horizontal ? position.x : position.y
    }

    private func clampedDivider(_ position: Int) -> Int {
        let upper = max(minimumFirstLength, totalLength - 1 - minimumSecondLength)
        return min(max(minimumFirstLength, position), upper)
    }

    private func moveDivider(by offset: Int) {
        moveDivider(to: dividerPosition + offset)
    }

    private func moveDivider(to position: Int) {
        let clamped = clampedDivider(position)

        guard clamped != dividerPosition else {
            return
        }

        dividerPosition = clamped
        setNeedsLayout()
        onDividerMoved(dividerPosition)
    }
}
