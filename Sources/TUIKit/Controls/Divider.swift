/// A visible dividing line, horizontal or vertical.
///
/// ```text
///   ┌─ Inspector ────┬──────┐
///   │  details       │ side │   ← the ┬, ├, and ┼ junctions appear
///   ├────────┬───────┤      │     automatically for connected dividers
///   │  logs  │ notes │      │
///   └────────┴───────┴──────┘
/// ```
///
/// Dividers draw from the theme's border slot in its `borderStyle` glyphs.
/// Two properties shape their behavior:
///
/// - `isConnected` (default `true`): endpoints and crossings against other
///   connected dividers render tee/cross junctions, and an enclosing
///   `Panel` joins dividers that reach its content edges into its border —
///   so composed dividers read as one piece of window chrome. Opt out for
///   a plain floating line.
/// - `isDraggable` (default `false`): the divider can be dragged (mouse,
///   with window capture; or arrow keys while focused) and it resizes the
///   adjacent sibling views on either side.
///
/// A horizontal divider is a `─` row (1 cell tall); a vertical divider is
/// a `│` column (1 cell wide). Both report an intrinsic size of 1×1 so
/// stacks give them exactly one cell on the stacking axis.
@MainActor
public final class Divider: TUIView {
    /// Line direction: `.horizontal` is a `─` row, `.vertical` a `│` column.
    public let axis: StackView.Axis

    /// Whether junctions render where this divider meets borders and other
    /// connected dividers.
    public var isConnected = true {
        didSet {
            if isConnected != oldValue {
                setNeedsDisplay()
            }
        }
    }

    /// Whether dragging (or arrows while focused) moves the divider,
    /// resizing the adjacent sibling views.
    public var isDraggable = false {
        didSet {
            if isDraggable != oldValue {
                setNeedsDisplay()
            }
        }
    }

    /// Called after a drag moves the divider (its new origin on the axis).
    public var onMoved: (Int) -> Void = { _ in }

    // In-flight drag.
    private var isDragging = false

    /// Creates a divider.
    ///
    /// - Parameter axis: Line direction.
    public init(axis: StackView.Axis = .horizontal) {
        self.axis = axis
        super.init(frame: .zero)
    }

    /// One cell of thickness on the stacking axis.
    public override var intrinsicContentSize: Size? {
        Size(width: 1, height: 1)
    }

    /// Draggable dividers take keyboard focus.
    public override var acceptsFirstResponder: Bool {
        isDraggable
    }

    /// Draws the line, then junctions against perpendicular siblings.
    public override func draw(_ painter: Painter) {
        let theme = effectiveTheme
        let characters = theme.borderStyle.characters
            ?? BorderStyle.single.characters!

        // Focus/drag cue: the line recolors to the accent — never bold and
        // never inverse (bold box-drawing glyphs render unevenly in common
        // terminal fonts, which reads as a dashed line). Colorless themes
        // (mono) show no cue.
        var style = theme.border

        if isDraggable, isFirstResponder || isDragging, theme.accent != .standard {
            style.foreground = theme.accent
        }

        switch axis {
        case .horizontal:
            for x in 0..<bounds.size.width {
                painter.set(TerminalCell(character: characters.horizontal, style: style), at: Point(x: x, y: 0))
            }

        case .vertical:
            for y in 0..<bounds.size.height {
                painter.set(TerminalCell(character: characters.vertical, style: style), at: Point(x: 0, y: y))
            }
        }

        if isConnected {
            drawJunctions(painter, style: style)
        }
    }

    // Junctions with perpendicular connected sibling dividers. Each
    // divider draws only cells inside its own frame: crossings are shared
    // cells (both siblings compute the same glyph), and a sibling's
    // endpoint abutting this line is this divider's cell to decorate.
    private func drawJunctions(_ painter: Painter, style: CellStyle) {
        guard let junctions = effectiveTheme.borderStyle.junctions
            ?? BorderStyle.single.junctions else {
            return
        }

        let siblings = (superview?.subviews ?? []).compactMap { view -> Divider? in
            guard let divider = view as? Divider,
                  divider !== self,
                  divider.isConnected,
                  !divider.isHidden,
                  divider.axis != axis else {
                return nil
            }

            return divider
        }

        for sibling in siblings {
            switch axis {
            case .horizontal:
                let row = frame.origin.y
                let column = sibling.frame.origin.x

                guard column >= frame.minX, column < frame.maxX else {
                    continue
                }

                let crossesLine = sibling.frame.minY <= row && sibling.frame.maxY > row
                let startsBelow = sibling.frame.minY == row + 1
                let endsAbove = sibling.frame.maxY == row

                let glyph: Character

                if crossesLine {
                    let above = sibling.frame.minY < row
                    let below = sibling.frame.maxY > row + 1
                    glyph = above && below
                        ? junctions.cross
                        : (below ? junctions.teeTop : junctions.teeBottom)
                } else if startsBelow {
                    glyph = junctions.teeTop
                } else if endsAbove {
                    glyph = junctions.teeBottom
                } else {
                    continue
                }

                painter.set(
                    TerminalCell(character: glyph, style: style),
                    at: Point(x: column - frame.origin.x, y: 0)
                )

            case .vertical:
                let column = frame.origin.x
                let row = sibling.frame.origin.y

                guard sibling.frame.minX <= column, sibling.frame.maxX > column else {
                    // The sibling's endpoint may abut this column.
                    if sibling.frame.origin.y >= frame.minY, sibling.frame.origin.y < frame.maxY {
                        if sibling.frame.maxX == frame.minX {
                            painter.set(
                                TerminalCell(character: junctions.teeRight, style: style),
                                at: Point(x: 0, y: sibling.frame.origin.y - frame.origin.y)
                            )
                        } else if sibling.frame.minX == frame.maxX {
                            painter.set(
                                TerminalCell(character: junctions.teeLeft, style: style),
                                at: Point(x: 0, y: sibling.frame.origin.y - frame.origin.y)
                            )
                        }
                    }

                    continue
                }

                guard row >= frame.minY, row < frame.maxY else {
                    continue
                }

                let left = sibling.frame.minX < column
                let right = sibling.frame.maxX > column + 1

                let glyph: Character = left && right
                    ? junctions.cross
                    : (right ? junctions.teeLeft : junctions.teeRight)
                painter.set(
                    TerminalCell(character: glyph, style: style),
                    at: Point(x: 0, y: row - frame.origin.y)
                )
            }
        }
    }

    // MARK: - Dragging

    /// Arrows move a focused draggable divider one cell.
    public override func keyDown(_ key: KeyInput) -> Bool {
        guard isDraggable, key.modifiers.isEmpty else {
            return false
        }

        switch (key.key, axis) {
        case (.up, .horizontal):
            moveBy(-1)
            return true

        case (.down, .horizontal):
            moveBy(1)
            return true

        case (.left, .vertical):
            moveBy(-1)
            return true

        case (.right, .vertical):
            moveBy(1)
            return true

        default:
            return false
        }
    }

    /// Press grabs a draggable divider; drags move it.
    public override func mouseEvent(_ mouse: MouseInput) -> Bool {
        guard isDraggable else {
            return false
        }

        switch mouse.action {
        case .press where mouse.button == .left:
            isDragging = true
            setNeedsDisplay()
            return true

        case .drag where isDragging:
            // Local coordinates: the pointer's offset from the line is the
            // amount to move.
            moveBy(axis == .horizontal ? mouse.position.y : mouse.position.x)
            return true

        case .release where isDragging:
            isDragging = false
            setNeedsDisplay()
            return true

        default:
            return false
        }
    }

    // Moves the divider along its perpendicular axis, resizing the sibling
    // views that touch it on either side.
    private func moveBy(_ delta: Int) {
        guard delta != 0, let superview else {
            return
        }

        let limit = axis == .horizontal ? superview.bounds.size.height : superview.bounds.size.width
        let position = axis == .horizontal ? frame.origin.y : frame.origin.x
        let target = min(max(1, position + delta), limit - 2)

        guard target != position else {
            return
        }

        let change = target - position

        // Resize only the views whose edges actually abut the line —
        // pane-style behavior. Views elsewhere (captions, crossing
        // dividers) are untouched.
        for sibling in superview.subviews where sibling !== self {
            var siblingFrame = sibling.frame

            if axis == .horizontal {
                if siblingFrame.maxY == position {
                    siblingFrame.size.height = max(0, siblingFrame.size.height + change)
                } else if siblingFrame.minY == position + 1 {
                    siblingFrame.origin.y += change
                    siblingFrame.size.height = max(0, siblingFrame.size.height - change)
                }
            } else {
                if siblingFrame.maxX == position {
                    siblingFrame.size.width = max(0, siblingFrame.size.width + change)
                } else if siblingFrame.minX == position + 1 {
                    siblingFrame.origin.x += change
                    siblingFrame.size.width = max(0, siblingFrame.size.width - change)
                }
            }

            sibling.frame = siblingFrame
        }

        var newFrame = frame

        if axis == .horizontal {
            newFrame.origin.y = target
        } else {
            newFrame.origin.x = target
        }

        frame = newFrame

        // Relayout so anchored siblings resolve against their (possibly
        // adjusted) frames; the divider's own dragged position survives
        // because its perpendicular axis is anchor-under-constrained.
        superview.setNeedsLayout()
        superview.setNeedsDisplay()
        onMoved(target)
    }
}
