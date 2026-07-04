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
public final class Button: TUIView {
    /// Title shown inside the button.
    public var title: String {
        didSet {
            if title != oldValue {
                superview?.setNeedsLayout()
                setNeedsDisplay()
            }
        }
    }

    /// How the button signals it is actionable: accent color (`.tinted`,
    /// the default) or bracketed (`.bordered`).
    public var style: ControlStyle = .tinted {
        didSet {
            if style != oldValue {
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

    /// One row at the decorated title width.
    public override var intrinsicContentSize: Size? {
        Size(width: title.count + style.horizontalPadding, height: 1)
    }

    /// Activates the button, exactly as user interaction would.
    public func activate() {
        onActivate()
    }

    /// Draws the button: accent-tinted (or bracketed) at rest, the selection
    /// style when focused, and emphasized while pressed.
    public override func draw(_ painter: Painter) {
        let theme = effectiveTheme
        var cellStyle: CellStyle

        if isPressed {
            cellStyle = theme.selection
            cellStyle.flags.insert(.bold)
        } else if isFirstResponder {
            cellStyle = theme.selection
        } else {
            cellStyle = style.restingStyle(theme: theme)
        }

        let inner = Label.truncated(title, width: max(0, bounds.size.width - style.horizontalPadding))
        painter.write(style.decorate(inner), at: .zero, style: cellStyle)
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
