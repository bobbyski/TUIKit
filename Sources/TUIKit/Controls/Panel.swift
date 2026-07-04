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

    /// Whether a maximize/restore box appears in the top border, left of `[x]`.
    public var showsMaximizeButton = false {
        didSet {
            if showsMaximizeButton != oldValue {
                setNeedsDisplay()
            }
        }
    }

    /// Drives the maximize box glyph: `[+]` when normal, `[=]` when maximized.
    public var isMaximized = false {
        didSet {
            if isMaximized != oldValue {
                setNeedsDisplay()
            }
        }
    }

    /// Called when the maximize/restore box is clicked.
    public var onMaximize: () -> Void = {}

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

        // Reserve the right-hand border for the buttons: [x] alone, or the
        // maximize box plus [x].
        let reserved = showsMaximizeButton ? 10 : 6

        if !title.isEmpty, width > reserved {
            let text = " " + Label.truncated(title, width: width - reserved) + " "
            painter.write(text, at: Point(x: 2, y: 0), style: theme.header)
        }

        if showsMaximizeButton, width >= 11 {
            painter.write(isMaximized ? "[=]" : "[+]", at: Point(x: maximizeButtonX, y: 0), style: theme.border)
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
    private func drawDividerJunctions(_ painter: Painter, theme: ResolvedTheme) {
        // Only weld when the theme asks for it.
        guard theme.dividerConnection == .welded else {
            return
        }

        // The tee welds the interior line (`dividerStyle` — the nub) into the
        // frame (`borderStyle`), e.g. a single divider into a double frame → ╟.
        let frame = theme.borderStyle
        let nub = theme.dividerStyle
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

                if origin.x <= 0, let glyph = frame.tee(.left, nub: nub) {
                    painter.set(TerminalCell(character: glyph, style: theme.border), at: Point(x: 0, y: y))
                }

                if origin.x + divider.frame.size.width >= contentSize.width, let glyph = frame.tee(.right, nub: nub) {
                    painter.set(TerminalCell(character: glyph, style: theme.border), at: Point(x: bounds.size.width - 1, y: y))
                }

            case .vertical:
                let x = origin.x + 1

                if origin.y <= 0, let glyph = frame.tee(.top, nub: nub) {
                    painter.set(TerminalCell(character: glyph, style: theme.border), at: Point(x: x, y: 0))
                }

                if origin.y + divider.frame.size.height >= contentSize.height, let glyph = frame.tee(.bottom, nub: nub) {
                    painter.set(TerminalCell(character: glyph, style: theme.border), at: Point(x: x, y: bounds.size.height - 1))
                }
            }
        }

        visit(content, offset: .zero)
    }

    /// Click on `[x]` closes; click on `[+]`/`[=]` maximizes/restores.
    public override func mouseEvent(_ mouse: MouseInput) -> Bool {
        guard mouse.action == .press, mouse.button == .left, mouse.position.y == 0 else {
            return false
        }

        if showsCloseButton, mouse.position.x >= closeButtonX, mouse.position.x < closeButtonX + 3 {
            onClose()
            return true
        }

        if showsMaximizeButton, mouse.position.x >= maximizeButtonX, mouse.position.x < maximizeButtonX + 3 {
            onMaximize()
            return true
        }

        return false
    }

    // Leading cell of the [x] affordance in the top border.
    private var closeButtonX: Int {
        bounds.size.width - 4
    }

    // Leading cell of the maximize box, one gap left of [x].
    private var maximizeButtonX: Int {
        bounds.size.width - 8
    }
}
