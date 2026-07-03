/// Activatable control rendered as `[ Title ]`.
///
/// The button owns its whole interaction: Return/Space activate it from the
/// keyboard, a press-and-release activates it from the mouse (with pressed
/// feedback), and focus draws inverted. Application code sees exactly one
/// semantic event:
///
/// ```swift
/// let save = Button("Save") { store.save() }
/// ```
@MainActor
public final class Button: View {
    /// Title shown inside the button.
    public var title: String {
        didSet {
            if title != oldValue {
                superview?.setNeedsLayout()
                setNeedsDisplay()
            }
        }
    }

    /// Called when the button activates.
    public var onActivate: () -> Void

    /// Whether a mouse press is currently held on the button.
    public private(set) var isPressed = false {
        didSet {
            if isPressed != oldValue {
                setNeedsDisplay()
            }
        }
    }

    /// Creates a button.
    ///
    /// - Parameters:
    ///   - title: Title shown inside the button.
    ///   - onActivate: Called when the button activates.
    public init(_ title: String, onActivate: @escaping () -> Void = {}) {
        self.title = title
        self.onActivate = onActivate
        super.init(frame: .zero)
    }

    /// Buttons take keyboard focus.
    public override var acceptsFirstResponder: Bool {
        true
    }

    /// One row at `[ Title ]` width.
    public override var intrinsicContentSize: Size? {
        Size(width: title.count + 4, height: 1)
    }

    /// Activates the button, exactly as user interaction would.
    public func activate() {
        onActivate()
    }

    /// Draws the button, inverting when focused or pressed.
    public override func draw(_ painter: Painter) {
        var style = CellStyle()

        if isPressed {
            style.flags = [.inverse, .bold]
        } else if isFirstResponder {
            style.flags = .inverse
        }

        let text = "[ \(Label.truncated(title, width: max(0, bounds.size.width - 4))) ]"
        painter.write(text, at: .zero, style: style)
    }

    /// Return or Space activates.
    public override func keyDown(_ key: KeyInput) -> Bool {
        guard key.modifiers.isEmpty else {
            return false
        }

        switch key.key {
        case .enter, .character(" "):
            activate()
            return true

        default:
            return false
        }
    }

    /// Press shows feedback; release inside the button activates.
    public override func mouseEvent(_ mouse: MouseInput) -> Bool {
        guard mouse.button == .left || mouse.action == .release else {
            return false
        }

        switch mouse.action {
        case .press:
            isPressed = true
            return true

        case .release:
            let wasPressed = isPressed
            isPressed = false

            if wasPressed, bounds.contains(mouse.position) {
                activate()
            }

            return wasPressed

        default:
            return false
        }
    }
}
