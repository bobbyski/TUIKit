/// Checkbox semantics with button presentation: state shown by color.
///
/// The `NSSwitch` of TUIKit — where `Checkbox` renders `[x]`, a toggle
/// button renders its title as a colored capsule: **on** wears the theme's
/// selection colors, **off** the placeholder (dim) style, and focus adds
/// emphasis. All state colors come from theme slots, so toggle buttons
/// restyle with themes and stylesheets like everything else.
///
/// ```swift
/// let live = ToggleButton("Live", isOn: true)
/// live.onChange = { enabled in stream.setLive(enabled) }
/// ```
///
/// Space, Return, or a click toggles; `setOn(_:notify:)` is the silent
/// programmatic path.
@MainActor
public final class ToggleButton: TUIView {
    /// Text shown inside the toggle.
    public var title: String {
        didSet {
            if title != oldValue {
                superview?.setNeedsLayout()
                setNeedsDisplay()
            }
        }
    }

    /// Whether the toggle is on.
    public private(set) var isOn: Bool

    /// Called when the state changes through interaction or
    /// `setOn(_:notify:)`.
    public var onChange: (Bool) -> Void = { _ in }

    /// Creates a toggle button.
    ///
    /// - Parameters:
    ///   - title: Text shown inside the toggle.
    ///   - isOn: Initial state.
    public init(_ title: String, isOn: Bool = false) {
        self.title = title
        self.isOn = isOn
        super.init(frame: .zero)
    }

    /// Toggle buttons take keyboard focus.
    public override var acceptsFirstResponder: Bool {
        true
    }

    /// One row at ` Title ` width.
    public override var intrinsicContentSize: Size? {
        Size(width: title.count + 2, height: 1)
    }

    /// Sets the state programmatically.
    ///
    /// - Parameters:
    ///   - on: New state.
    ///   - notify: Whether `onChange` fires. Defaults to silent.
    public func setOn(_ on: Bool, notify: Bool = false) {
        guard on != isOn else {
            return
        }

        isOn = on
        setNeedsDisplay()

        if notify {
            onChange(isOn)
        }
    }

    /// Toggles the state, exactly as user interaction would.
    public func toggle() {
        isOn.toggle()
        setNeedsDisplay()
        onChange(isOn)
    }

    /// Draws the title capsule in state colors.
    public override func draw(_ painter: Painter) {
        let theme = effectiveTheme
        var style = isOn ? theme.selection : theme.placeholder

        if isFirstResponder {
            style.flags.insert(isOn ? .bold : .inverse)
        }

        let text = " " + Label.truncated(title, width: max(0, bounds.size.width - 2)) + " "
        painter.write(text, at: .zero, style: style)
    }

    /// Space or Return toggles.
    public override func keyDown(_ key: KeyInput) -> Bool {
        guard key.modifiers.isEmpty else {
            return false
        }

        switch key.key {
        case .enter, .character(" "):
            toggle()
            return true

        default:
            return false
        }
    }

    /// Click toggles.
    public override func mouseEvent(_ mouse: MouseInput) -> Bool {
        guard mouse.action == .press, mouse.button == .left else {
            return false
        }

        toggle()
        return true
    }
}
