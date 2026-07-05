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

    /// One row at the decorated title width (excluding any `&` markers) — or,
    /// when the theme gives buttons a drop shadow, one extra column and row
    /// for it (the shadow sits offset (1, 1) behind the face).
    public override var intrinsicContentSize: Size? {
        let width = accelerator.display.count + style.horizontalPadding

        guard effectiveTheme.buttonShadow != nil else {
            return Size(width: width, height: 1)
        }

        return Size(width: width + 1, height: 2)
    }

    /// Activates the button, exactly as user interaction would.
    public func activate() {
        onActivate()
    }

    /// Draws the button: accent-tinted (or bracketed) at rest, the selection
    /// style when focused, and emphasized while pressed. A `.default` or
    /// `.destructive` role fills as a pill from its theme slot, keeping that
    /// color through focus (bold) and press (inverse).
    ///
    /// When the theme sets `buttonShadowColor` (Turbo: black), the face casts
    /// a drop shadow one cell right and one row below — and a press animates
    /// the face *onto* the shadow position, popping back on release, so the
    /// motion itself is the pressed cue (no inverse/selection recolor).
    public override func draw(_ painter: Painter) {
        let theme = effectiveTheme

        // Shadow only when the theme asks for one AND the frame has the extra
        // column/row (a hand-framed 1-row button just renders flat).
        let shadowColor = theme.buttonShadow
        let hasShadow = shadowColor != nil
            && bounds.size.height >= 2
            && bounds.size.width > style.horizontalPadding
        let pressedOntoShadow = isPressed && hasShadow

        var cellStyle: CellStyle

        switch role {
        case .normal:
            if isPressed, !hasShadow {
                cellStyle = theme.selection
                cellStyle.flags.insert(.bold)
            } else if isFirstResponder, !pressedOntoShadow {
                cellStyle = theme.selection
            } else {
                cellStyle = style.restingStyle(theme: theme)
            }

        case .default, .destructive:
            cellStyle = role == .default ? theme.defaultButton : theme.destructiveButton
            if isPressed, !hasShadow {
                cellStyle.flags.insert(.inverse)
            } else if isFirstResponder, !pressedOntoShadow {
                cellStyle.flags.insert(.bold)
            }
        }

        let accelerator = self.accelerator
        let faceWidth = bounds.size.width - (hasShadow ? 1 : 0)
        let faceOrigin = pressedOntoShadow ? Point(x: 1, y: 1) : Point.zero
        let innerWidth = max(0, faceWidth - style.horizontalPadding)
        let inner = Label.truncated(accelerator.display, width: innerWidth)
        painter.write(style.decorate(inner), at: faceOrigin, style: cellStyle)

        // Paint the mnemonic letter in the accelerator color (red in Turbo),
        // keeping the surrounding button's background. `decorate` adds a
        // symmetric pad, so the letter sits `horizontalPadding / 2` in.
        if let index = accelerator.index, index < inner.count {
            let column = faceOrigin.x + style.horizontalPadding / 2 + index
            painter.set(
                TerminalCell(character: Array(inner)[index], style: theme.accelerator(over: cellStyle)),
                at: Point(x: column, y: faceOrigin.y)
            )
        }

        // The resting shadow: below the face, shifted one right (the Borland
        // look — see the Turbo reference dialogs). Pressing hides it (the
        // face is there).
        if hasShadow, let shadowColor, !isPressed {
            let shadow = CellStyle(background: shadowColor)

            for x in 1...faceWidth {
                painter.set(TerminalCell(character: " ", style: shadow), at: Point(x: x, y: 1))
            }
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
