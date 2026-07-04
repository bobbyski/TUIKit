/// Bordered, titled container — the standard TUIKit chrome.
///
/// A panel draws a single-line box with its title in the top border and
/// keeps application content inside `content`, which is inset by the
/// border. Add subviews to `content`, never to the panel itself:
///
/// ```swift
/// let panel = Panel("Inspector")
/// panel.content.addSubview(form)      // form fills inside the border
/// ```
///
/// ```text
///   ┌ Inspector ─────────[x]┐
///   │ (content view area)   │
///   └───────────────────────┘
/// ```
///
/// The optional close button emits `onClose`; the panel never removes
/// itself — the application decides what closing means.
@MainActor
public final class Panel: TUIView {
    /// Title shown in the top border.
    public var title: String {
        didSet {
            if title != oldValue {
                setNeedsDisplay()
            }
        }
    }

    /// Whether `[x]` appears in the top-right border.
    public var showsCloseButton = false {
        didSet {
            if showsCloseButton != oldValue {
                setNeedsDisplay()
            }
        }
    }

    /// Called when the close button is clicked.
    public var onClose: () -> Void = {}

    /// Whether the bottom-right corner renders as a resize handle (`◢`).
    ///
    /// Visual only — `FloatingWindow` owns the actual resize interaction.
    public var showsResizeHandle = false {
        didSet {
            if showsResizeHandle != oldValue {
                setNeedsDisplay()
            }
        }
    }

    /// Container for application content, inset by the border.
    public let content = TUIView()

    /// Creates a panel.
    ///
    /// - Parameter title: Title shown in the top border.
    public init(_ title: String = "") {
        self.title = title
        super.init(frame: .zero)
        addSubview(content)
    }

    /// Positions the content view inside the border.
    public override func layoutSubviews() {
        content.frame = Rect(
            x: 1,
            y: 1,
            width: max(0, bounds.size.width - 2),
            height: max(0, bounds.size.height - 2)
        )
    }

    /// Draws the background, border, title, and close button.
    public override func draw(_ painter: Painter) {
        let theme = effectiveTheme

        painter.fill(bounds, with: .blank)
        painter.drawBox(bounds, style: theme.border, border: theme.borderStyle)

        let width = bounds.size.width

        if !title.isEmpty, width > 6 {
            let text = " " + Label.truncated(title, width: width - 6) + " "
            painter.write(text, at: Point(x: 2, y: 0), style: theme.header)
        }

        if showsCloseButton, width >= 7 {
            painter.write("[x]", at: Point(x: closeButtonX, y: 0), style: theme.border)
        }

        if showsResizeHandle, width >= 2, bounds.size.height >= 2 {
            painter.write(
                "◢",
                at: Point(x: width - 1, y: bounds.size.height - 1),
                style: theme.border
            )
        }

        drawDividerJunctions(painter, theme: theme)
    }

    // Joins connected dividers anywhere in the content subtree that reach
    // the content edges into this panel's border with tee junctions, so
    // divided layouts read as one piece of chrome.
    private func drawDividerJunctions(_ painter: Painter, theme: Theme) {
        guard let junctions = theme.borderStyle.junctions else {
            return
        }

        let contentSize = content.frame.size

        func visit(_ view: TUIView, offset: Point) {
            for subview in view.subviews where !subview.isHidden {
                if let divider = subview as? Divider, divider.isConnected {
                    join(divider, at: offset + divider.frame.origin)
                } else {
                    visit(subview, offset: offset + subview.frame.origin)
                }
            }
        }

        // `origin` is the divider's position in content coordinates.
        func join(_ divider: Divider, at origin: Point) {
            switch divider.axis {
            case .horizontal:
                let y = origin.y + 1   // content is inset by 1

                if origin.x <= 0 {
                    painter.set(
                        TerminalCell(character: junctions.teeLeft, style: theme.border),
                        at: Point(x: 0, y: y)
                    )
                }

                if origin.x + divider.frame.size.width >= contentSize.width {
                    painter.set(
                        TerminalCell(character: junctions.teeRight, style: theme.border),
                        at: Point(x: bounds.size.width - 1, y: y)
                    )
                }

            case .vertical:
                let x = origin.x + 1

                if origin.y <= 0 {
                    painter.set(
                        TerminalCell(character: junctions.teeTop, style: theme.border),
                        at: Point(x: x, y: 0)
                    )
                }

                if origin.y + divider.frame.size.height >= contentSize.height {
                    painter.set(
                        TerminalCell(character: junctions.teeBottom, style: theme.border),
                        at: Point(x: x, y: bounds.size.height - 1)
                    )
                }
            }
        }

        visit(content, offset: .zero)
    }

    /// Click on `[x]` closes.
    public override func mouseEvent(_ mouse: MouseInput) -> Bool {
        guard showsCloseButton,
              mouse.action == .press,
              mouse.button == .left,
              mouse.position.y == 0,
              mouse.position.x >= closeButtonX,
              mouse.position.x < closeButtonX + 3 else {
            return false
        }

        onClose()
        return true
    }

    // Leading cell of the [x] affordance in the top border.
    private var closeButtonX: Int {
        bounds.size.width - 4
    }
}
