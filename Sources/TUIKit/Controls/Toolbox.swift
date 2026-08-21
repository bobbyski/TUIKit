/// A tool palette — a radio group with pictures, docked to an edge.
///
/// ```text
///   ┃ ↖ Select ┃      vertical, down a window's left edge
///     ✎ Pen
///     ▭ Rect
///     ◯ Ellipse
///
///   [↖ Select] ✎ Pen  ▭ Rect  ◯ Ellipse     horizontal
/// ```
///
/// Exactly one tool is selected at a time. Arrows move, Space or a click
/// selects, Enter activates the selected tool's `action`. Each tool is a
/// glyph and a caption; set `showsCaptions` false for the glyph-only strip.
///
/// ```swift
/// let tools = Toolbox(axis: .vertical, tools: [
///     .init(glyph: "↖", caption: "Select"),
///     .init(glyph: "✎", caption: "Pen"),
/// ])
/// tools.onSelectionChanged = { index in canvas.tool = index }
/// ```
@MainActor
public final class Toolbox: TUIView {
    /// One tool.
    public struct Tool {
        /// The picture.
        public var glyph: Character

        /// The name.
        public var caption: String

        /// Runs when the tool is activated (Enter, double-click).
        public var action: () -> Void

        /// Creates a tool.
        public init(glyph: Character, caption: String, action: @escaping () -> Void = {}) {
            self.glyph = glyph
            self.caption = caption
            self.action = action
        }
    }

    /// The tools, in order.
    public var tools: [Tool] {
        didSet {
            selectedIndex = min(selectedIndex, max(0, tools.count - 1))
            superview?.setNeedsLayout()
            setNeedsDisplay()
        }
    }

    /// Down an edge, or along one.
    public let axis: StackView.Axis

    /// Whether captions draw beside the glyphs.
    public var showsCaptions = true {
        didSet {
            superview?.setNeedsLayout()
            setNeedsDisplay()
        }
    }

    /// The selected tool.
    public private(set) var selectedIndex = 0

    /// Called with the new selection.
    public var onSelectionChanged: (Int) -> Void = { _ in }

    /// Creates a toolbox.
    ///
    /// - Parameters:
    ///   - axis: Vertical (the default) or horizontal.
    ///   - tools: The tools.
    public init(axis: StackView.Axis = .vertical, tools: [Tool]) {
        self.axis = axis
        self.tools = tools
        super.init(frame: .zero)
    }

    /// Toolboxes take keyboard focus.
    public override var acceptsFirstResponder: Bool {
        true
    }

    /// One cell per tool along the axis.
    public override var intrinsicContentSize: Size? {
        switch axis {
        case .vertical:
            return Size(width: cellWidth, height: tools.count)

        case .horizontal:
            return Size(width: tools.count * cellWidth + max(0, tools.count - 1), height: 1)
        }
    }

    /// Selects a tool programmatically.
    ///
    /// - Parameters:
    ///   - index: The tool.
    ///   - notify: Whether `onSelectionChanged` fires. Defaults to silent.
    public func select(_ index: Int, notify: Bool = false) {
        guard tools.indices.contains(index), index != selectedIndex else {
            return
        }

        selectedIndex = index
        setNeedsDisplay()

        if notify {
            onSelectionChanged(index)
        }
    }

    /// Draws the tools; the selected one wears the selection style.
    public override func draw(_ painter: Painter) {
        let theme = effectiveTheme
        painter.fill(bounds, with: .blank)

        for (index, tool) in tools.enumerated() {
            let origin = cellOrigin(index)
            var style = index == selectedIndex ? theme.selection : theme.base

            if index == selectedIndex, isFirstResponder, let cue = theme.cueAccent(over: style.background), style.background == theme.background {
                style.foreground = cue
            }

            var text = " \(tool.glyph)"

            if showsCaptions {
                text += " " + tool.caption
            }

            text = text.padding(toLength: cellWidth, withPad: " ", startingAt: 0)
            painter.write(text, at: origin, style: style)
        }
    }

    /// Arrows move the selection; Enter activates.
    public override func keyDown(_ key: KeyInput) -> Bool {
        guard key.modifiers.isEmpty, !tools.isEmpty else {
            return false
        }

        switch key.key {
        case .up where axis == .vertical, .left where axis == .horizontal:
            choose(selectedIndex - 1)
            return true

        case .down where axis == .vertical, .right where axis == .horizontal:
            choose(selectedIndex + 1)
            return true

        case .home:
            choose(0)
            return true

        case .end:
            choose(tools.count - 1)
            return true

        case .enter, .character(" "):
            tools[selectedIndex].action()
            return true

        default:
            return false
        }
    }

    /// A click selects; a double-click activates.
    public override func mouseEvent(_ mouse: MouseInput) -> Bool {
        guard mouse.button == .left, let index = cellIndex(at: mouse.position) else {
            return false
        }

        switch mouse.action {
        case .press:
            choose(index)
            return true

        case .click where mouse.clickCount >= 2:
            tools[index].action()
            return true

        default:
            return false
        }
    }

    // MARK: - Geometry

    private var cellWidth: Int {
        let captions = showsCaptions ? (tools.map(\.caption.count).max() ?? 0) + 1 : 0
        return 2 + captions + 1
    }

    private func cellOrigin(_ index: Int) -> Point {
        axis == .vertical ? Point(x: 0, y: index) : Point(x: index * (cellWidth + 1), y: 0)
    }

    private func cellIndex(at point: Point) -> Int? {
        let index: Int

        switch axis {
        case .vertical:
            index = point.y

        case .horizontal:
            guard point.x % (cellWidth + 1) < cellWidth else { return nil }
            index = point.x / (cellWidth + 1)
        }

        return tools.indices.contains(index) ? index : nil
    }

    private func choose(_ index: Int) {
        let clamped = min(max(0, index), tools.count - 1)

        guard clamped != selectedIndex else {
            return
        }

        selectedIndex = clamped
        setNeedsDisplay()
        onSelectionChanged(clamped)
    }
}
