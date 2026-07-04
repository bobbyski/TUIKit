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

    /// The button's semantic weight in a set of choices.
    ///
    /// `.normal` buttons draw from `style` (the default); `.default` and
    /// `.destructive` draw as filled "pills" from the theme's
    /// `defaultButton`/`destructiveButton` slots — a solid green or red block
    /// in Turbo, colored text on a colorless theme.
    public enum Role: Sendable {
        /// An ordinary button; follows `style`.
        case normal
        /// The affirmative default (OK, Save); the `defaultButton` slot.
        case `default`
        /// A dangerous choice (Delete); the `destructiveButton` slot.
        case destructive
    }

    /// The button's semantic weight. `.normal` by default.
    public var role: Role = .normal {
        didSet {
            if role != oldValue {
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

    // The title parsed for its mnemonic; `&Save` highlights the S and binds Alt+S.
    private var accelerator: Accelerator {
        Accelerator(title)
    }

    /// One row at the decorated title width (excluding any `&` markers).
    public override var intrinsicContentSize: Size? {
        Size(width: accelerator.display.count + style.horizontalPadding, height: 1)
    }

    /// Activates the button, exactly as user interaction would.
    public func activate() {
        onActivate()
    }

    /// Draws the button: accent-tinted (or bracketed) at rest, the selection
    /// style when focused, and emphasized while pressed. A `.default` or
    /// `.destructive` role fills as a pill from its theme slot, keeping that
    /// color through focus (bold) and press (inverse).
    public override func draw(_ painter: Painter) {
        let theme = effectiveTheme
        var cellStyle: CellStyle

        switch role {
        case .normal:
            if isPressed {
                cellStyle = theme.selection
                cellStyle.flags.insert(.bold)
            } else if isFirstResponder {
                cellStyle = theme.selection
            } else {
                cellStyle = style.restingStyle(theme: theme)
            }

        case .default, .destructive:
            cellStyle = role == .default ? theme.defaultButton : theme.destructiveButton
            if isPressed {
                cellStyle.flags.insert(.inverse)
            } else if isFirstResponder {
                cellStyle.flags.insert(.bold)
            }
        }

        let accelerator = self.accelerator
        let innerWidth = max(0, bounds.size.width - style.horizontalPadding)
        let inner = Label.truncated(accelerator.display, width: innerWidth)
        painter.write(style.decorate(inner), at: .zero, style: cellStyle)

        // Paint the mnemonic letter in the accelerator color (red in Turbo),
        // keeping the surrounding button's background. `decorate` adds a
        // symmetric pad, so the letter sits `horizontalPadding / 2` in.
        if let index = accelerator.index, index < inner.count {
            let column = style.horizontalPadding / 2 + index
            painter.set(
                TerminalCell(character: Array(inner)[index], style: theme.accelerator(over: cellStyle)),
                at: Point(x: column, y: 0)
            )
        }
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

    /// Alt+mnemonic activates the button from anywhere in the window.
    public override func handleHotKey(_ key: KeyInput) -> Bool {
        guard accelerator.matches(key) else {
            return false
        }

        activate()
        return true
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
