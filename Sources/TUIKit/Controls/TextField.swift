/// Single-line text editor.
///
/// The field owns every editing mechanic — cursor movement, insertion,
/// deletion, horizontal scrolling for long text, placeholder display — and
/// surfaces two semantic events:
///
/// ```swift
/// let name = TextField(placeholder: "Name")
/// name.onChanged = { draft in validate(draft) }
/// name.onSubmit = { value in save(value) }
/// ```
///
/// The cursor renders as an inverted cell while the field is focused.
@MainActor
public final class TextField: View {
    /// Current text.
    public private(set) var text: String = ""

    /// Dimmed text shown while empty.
    public var placeholder: String {
        didSet {
            if placeholder != oldValue {
                setNeedsDisplay()
            }
        }
    }

    /// Called after every text change.
    public var onChanged: (String) -> Void = { _ in }

    /// Called when Return is pressed.
    public var onSubmit: (String) -> Void = { _ in }

    // Cursor position as a character offset into `text`.
    private var cursorIndex = 0

    // First visible character offset (horizontal scrolling).
    private var scrollOffset = 0

    /// Creates a text field.
    ///
    /// - Parameters:
    ///   - text: Initial text.
    ///   - placeholder: Dimmed text shown while empty.
    public init(text: String = "", placeholder: String = "") {
        self.placeholder = placeholder
        super.init(frame: .zero)
        setText(text)
    }

    /// Text fields take keyboard focus.
    public override var acceptsFirstResponder: Bool {
        true
    }

    /// Replaces the text programmatically.
    ///
    /// The cursor moves to the end. `onChanged` is not called for
    /// programmatic changes.
    ///
    /// - Parameter newText: Replacement text.
    public func setText(_ newText: String) {
        text = newText
        cursorIndex = text.count
        setNeedsDisplay()
    }

    /// Draws the visible slice, placeholder, and cursor.
    public override func draw(_ painter: Painter) {
        let width = bounds.size.width

        guard width > 0, bounds.size.height > 0 else {
            return
        }

        if text.isEmpty, !placeholder.isEmpty, !isFirstResponder {
            // Placeholder state: de-emphasize the whole line, not just the text.
            var dim = effectiveTheme.placeholder
            dim.flags.insert(.underline)
            painter.write(String(repeating: " ", count: width), at: .zero, style: dim)
            painter.write(Label.truncated(placeholder, width: width), at: .zero, style: dim)
            return
        }

        // Underline marks the editable area.
        painter.write(String(repeating: " ", count: width), at: .zero, style: CellStyle(flags: .underline))

        adjustScroll(width: width)

        let characters = Array(text)
        let visibleEnd = min(characters.count, scrollOffset + width)

        if scrollOffset < visibleEnd {
            let visible = String(characters[scrollOffset..<visibleEnd])
            painter.write(visible, at: .zero, style: CellStyle(flags: .underline))
        }

        if isFirstResponder {
            let cursorColumn = cursorIndex - scrollOffset
            let underCursor: Character

            if cursorIndex < characters.count {
                underCursor = characters[cursorIndex]
            } else {
                underCursor = " "
            }

            painter.set(
                TerminalCell(character: underCursor, style: CellStyle(flags: [.inverse, .underline])),
                at: Point(x: cursorColumn, y: 0)
            )
        }
    }

    /// Editing keys, cursor movement, and submit.
    public override func keyDown(_ key: KeyInput) -> Bool {
        // Plain and shifted characters insert; anything with control or alt
        // is not ours.
        if case .character(let character) = key.key,
           key.modifiers.subtracting(.shift).isEmpty {
            insert(character)
            return true
        }

        guard key.modifiers.isEmpty else {
            return false
        }

        switch key.key {
        case .enter:
            onSubmit(text)
            return true

        case .backspace:
            deleteBackward()
            return true

        case .delete:
            deleteForward()
            return true

        case .left:
            moveCursor(to: cursorIndex - 1)
            return true

        case .right:
            moveCursor(to: cursorIndex + 1)
            return true

        case .home:
            moveCursor(to: 0)
            return true

        case .end:
            moveCursor(to: text.count)
            return true

        default:
            return false
        }
    }

    /// Click places the cursor.
    public override func mouseEvent(_ mouse: MouseInput) -> Bool {
        guard mouse.action == .press, mouse.button == .left else {
            return false
        }

        moveCursor(to: scrollOffset + mouse.position.x)
        return true
    }

    // MARK: - Editing

    private func insert(_ character: Character) {
        var characters = Array(text)
        characters.insert(character, at: cursorIndex)
        text = String(characters)
        cursorIndex += 1
        changed()
    }

    private func deleteBackward() {
        guard cursorIndex > 0 else {
            return
        }

        var characters = Array(text)
        characters.remove(at: cursorIndex - 1)
        text = String(characters)
        cursorIndex -= 1
        changed()
    }

    private func deleteForward() {
        var characters = Array(text)

        guard cursorIndex < characters.count else {
            return
        }

        characters.remove(at: cursorIndex)
        text = String(characters)
        changed()
    }

    private func moveCursor(to index: Int) {
        cursorIndex = min(max(0, index), text.count)
        setNeedsDisplay()
    }

    private func changed() {
        setNeedsDisplay()
        onChanged(text)
    }

    // Keeps the cursor inside the visible window.
    private func adjustScroll(width: Int) {
        if cursorIndex < scrollOffset {
            scrollOffset = cursorIndex
        }

        if cursorIndex > scrollOffset + width - 1 {
            scrollOffset = cursorIndex - width + 1
        }

        scrollOffset = max(0, min(scrollOffset, max(0, text.count - width + 1)))
    }
}
