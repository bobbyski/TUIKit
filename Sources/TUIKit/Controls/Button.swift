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

        // On a VTG terminal, a theme with button chrome draws the rounded
        // gradient pill instead of any cell decoration (Phase 10).
        if let chrome = painter.chrome, let pill = theme.vector?.button {
            drawVectorPill(painter, chrome: chrome, theme: theme, pill: pill)
            return
        }

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

    // The vector face (Phase 10): a rounded gradient pill under the label,
    // with the label cells gone transparent so the pill shows through. Focus
    // wears the theme's glow stroke (plus bold); a press flips the gradient.
    // Role pills (`.default`/`.destructive`) derive their gradient from the
    // theme's cell slot, so the semantics stay theme-driven.
    private func drawVectorPill(
        _ painter: Painter,
        chrome: ChromeSurface,
        theme: ResolvedTheme,
        pill: VectorChrome.Button
    ) {
        let width = bounds.size.width

        guard width > 0, bounds.size.height > 0 else {
            return
        }

        var top: ChromeColor
        var bottom: ChromeColor
        var labelColor: TerminalColor

        switch role {
        case .normal:
            top = pill.topColor
            bottom = pill.bottomColor
            labelColor = pill.textColor ?? theme.buttonForeground

        case .default, .destructive:
            let slot = role == .default ? theme.defaultButton : theme.destructiveButton
            let fill = ChromeColor(slot.background) ?? pill.topColor
            top = ChromeColor.lerp(fill, ChromeColor(red: 255, green: 255, blue: 255), 0.18)
            bottom = ChromeColor.lerp(fill, ChromeColor(red: 0, green: 0, blue: 0), 0.12)
            labelColor = slot.foreground
        }

        if isPressed {
            if role == .normal, let pressedTop = pill.pressedTopColor {
                top = pressedTop
                bottom = pill.pressedBottomColor ?? pill.topColor
            } else {
                swap(&top, &bottom)
            }
        }

        let focused = isFirstResponder
        let stroke = focused ? (pill.focusStrokeColor ?? pill.strokeColor) : pill.strokeColor

        chrome.verticalGradient(
            "pill",
            ChromeRect(x: 0, y: 0, width: Double(width), height: 1),
            top: top,
            bottom: bottom,
            steps: 6,
            radius: pill.cornerRadius ?? 0.4,
            corners: .all,
            stroke: stroke,
            lineWidth: focused && pill.focusStrokeColor != nil ? 0.09 : 0.05
        )

        // Label cells keep the terminal-default background (neutral base
        // defeats theme substitution) so the pill shows behind the text.
        let transparent = painter.withBase(CellStyle())
        transparent.fill(bounds, with: .blank)

        var labelStyle = CellStyle(foreground: labelColor)
        if focused {
            labelStyle.flags.insert(.bold)
        }

        let accelerator = self.accelerator
        let innerWidth = max(0, width - style.horizontalPadding)
        let inner = Label.truncated(accelerator.display, width: innerWidth)
        transparent.write(style.decorate(inner), at: .zero, style: labelStyle)

        if let index = accelerator.index, index < inner.count {
            let column = style.horizontalPadding / 2 + index
            transparent.set(
                TerminalCell(character: Array(inner)[index], style: theme.accelerator(over: labelStyle)),
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
