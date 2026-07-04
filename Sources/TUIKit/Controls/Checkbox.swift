/// Toggleable option rendered as `[x] Label`.
///
/// Space, Return, or a click toggles; the application receives one semantic
/// event:
///
/// ```swift
/// let wrap = Checkbox("Wrap lines", isChecked: true)
/// wrap.onChange = { enabled in editor.wraps = enabled }
/// ```
@MainActor
public final class Checkbox: TUIView {
    /// Text shown beside the box.
    public var label: String {
        didSet {
            if label != oldValue {
                superview?.setNeedsLayout()
                setNeedsDisplay()
            }
        }
    }

    /// Whether the box is checked.
    public private(set) var isChecked: Bool

    /// Called when the checked state changes through interaction or
    /// `setChecked(_:notify:)`.
    public var onChange: (Bool) -> Void = { _ in }

    /// Creates a checkbox.
    ///
    /// - Parameters:
    ///   - label: Text shown beside the box.
    ///   - isChecked: Initial checked state.
    public init(_ label: String, isChecked: Bool = false) {
        self.label = label
        self.isChecked = isChecked
        super.init(frame: .zero)
    }

    /// Checkboxes take keyboard focus.
    public override var acceptsFirstResponder: Bool {
        true
    }

    /// One row at `[x] Label` width.
    public override var intrinsicContentSize: Size? {
        Size(width: label.count + 4, height: 1)
    }

    /// Sets the checked state programmatically.
    ///
    /// - Parameters:
    ///   - checked: New state.
    ///   - notify: Whether `onChange` fires. Defaults to silent.
    public func setChecked(_ checked: Bool, notify: Bool = false) {
        guard checked != isChecked else {
            return
        }

        isChecked = checked
        setNeedsDisplay()

        if notify {
            onChange(isChecked)
        }
    }

    /// Toggles the state, exactly as user interaction would.
    public func toggle() {
        isChecked.toggle()
        setNeedsDisplay()
        onChange(isChecked)
    }

    /// Draws the box and label, inverting the box when focused.
    public override func draw(_ painter: Painter) {
        let boxStyle = CellStyle(flags: isFirstResponder ? .inverse : [])
        let mark = isChecked ? "[x]" : "[ ]"

        painter.write(mark, at: .zero, style: boxStyle)
        painter.write(
            Label.truncated(label, width: max(0, bounds.size.width - 4)),
            at: Point(x: 4, y: 0)
        )
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
