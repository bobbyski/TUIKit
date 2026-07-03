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
public final class Panel: View {
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

    /// Container for application content, inset by the border.
    public let content = View()

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

    /// Draws the border, title, and close button.
    public override func draw(_ painter: Painter) {
        painter.drawBox(bounds)

        let width = bounds.size.width

        if !title.isEmpty, width > 6 {
            let text = " " + Label.truncated(title, width: width - 6) + " "
            painter.write(text, at: Point(x: 2, y: 0), style: CellStyle(flags: .bold))
        }

        if showsCloseButton, width >= 7 {
            painter.write("[x]", at: Point(x: closeButtonX, y: 0))
        }
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
