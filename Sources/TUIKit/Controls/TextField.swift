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
public final class TextField: TUIView {
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

    /// Called when Backspace is pressed with the caret at the start and
    /// nothing selected — the one keystroke a field cannot use itself, and
    /// the one a `TokenField` wrapping it needs ("remove the last token").
    public var onDeleteBackwardAtStart: () -> Void = {}

    // Cursor position as a character offset into `text`.
    private var cursorIndex = 0

    // First visible character offset (horizontal scrolling).
    private var scrollOffset = 0

    /// The selected characters, or nil when there is only a caret.
    ///
    /// A field had a cursor and no selection until the escalating
    /// double-click needed somewhere to put "the word" — so this is the
    /// smallest selection that makes that behaviour honest: it draws, it is
    /// what ^C copies, and typing replaces it. It is not a full selection
    /// model — no shift-arrow, no drag — and it should grow into one rather
    /// than be worked around.
    public private(set) var selectedRange: Range<Int>?

    /// The selected text, when any.
    public var selectedText: String? {
        selectedRange.map { String(Array(text)[$0]) }
    }

    /// Selects everything (the top rung of the double-click ladder).
    public func selectAll() {
        selectedRange = text.isEmpty ? nil : 0..<text.count
        setNeedsDisplay()
    }

    /// Drops the selection, leaving the caret where it is.
    public func clearSelection() {
        guard selectedRange != nil else {
            return
        }

        selectedRange = nil
        setNeedsDisplay()
    }

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

        // The editable "well" comes from the theme's field slot: an underline in
        // `standard`, a solid colored background in themes like Turbo.
        let field = effectiveTheme.field

        if text.isEmpty, !placeholder.isEmpty, !isFirstResponder {
            // Placeholder state: de-emphasized text on the field well.
            var dim = field
            dim.foreground = effectiveTheme.placeholder.foreground
            dim.flags.insert(.dim)
            painter.write(String(repeating: " ", count: width), at: .zero, style: dim)
            painter.write(Label.truncated(placeholder, width: width), at: .zero, style: dim)
            return
        }

        painter.write(String(repeating: " ", count: width), at: .zero, style: field)

        adjustScroll(width: width)

        let characters = Array(text)
        let visibleEnd = min(characters.count, scrollOffset + width)

        if scrollOffset < visibleEnd {
            let visible = String(characters[scrollOffset..<visibleEnd])
            painter.write(visible, at: .zero, style: field)
        }

        if let selected = selectedRange {
            var style = effectiveTheme.selection

            // The field's own ground where the theme has nothing to say, so a
            // selection never turns the well a colour the field never wears.
            if style.background == .standard {
                style.background = field.background
                style.flags.insert(.inverse)
            }

            for index in selected where index >= scrollOffset && index < visibleEnd {
                painter.set(
                    TerminalCell(character: characters[index], style: style),
                    at: Point(x: index - scrollOffset, y: 0)
                )
            }
        }

        if isFirstResponder {
            let cursorColumn = cursorIndex - scrollOffset
            let underCursor: Character

            if cursorIndex < characters.count {
                underCursor = characters[cursorIndex]
            } else {
                underCursor = " "
            }

            var cursorStyle = field
            cursorStyle.flags.insert(.inverse)
            painter.set(
                TerminalCell(character: underCursor, style: cursorStyle),
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

        // Clipboard, before the plain-key switch below rejects modifiers.
        if key.modifiers == .control, case .character(let letter) = key.key {
            switch Character(letter.lowercased()) {
            case "v":
                paste()
                return true

            case "c":
                copyAll()
                return true

            case "x":
                clipboardCut()
                return true

            default:
                break
            }
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
            moveCursorClearingSelection(to: cursorIndex - 1)
            return true

        case .right:
            moveCursorClearingSelection(to: cursorIndex + 1)
            return true

        case .home:
            moveCursorClearingSelection(to: 0)
            return true

        case .end:
            moveCursorClearingSelection(to: text.count)
            return true

        default:
            return false
        }
    }

    // MARK: - Clipboard

    /// The clipboard cut/copy/paste use — the app's, via the window.
    ///
    /// A text field had NO clipboard at all before this: `^V` fell through
    /// the modifier guard below and did nothing, so the Find field was a box
    /// you could only type into. Assign to override.
    public var pasteboard: Pasteboard?

    // The injected one, or the app's.
    private var resolvedPasteboard: Pasteboard? {
        pasteboard ?? owningWindow?.app?.pasteboard
    }

    /// Inserts the clipboard at the cursor.
    ///
    /// Newlines become spaces: a field is one line, and a pasted path or
    /// query with a stray newline should land as text rather than silently
    /// losing everything after it.
    public func paste() {
        guard let clipboard = resolvedPasteboard?.string, !clipboard.isEmpty else {
            return
        }

        let flattened = clipboard
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")

        for character in flattened {
            insert(character)
        }
    }

    /// Copies the selection, or the whole field when there is none.
    ///
    /// Everything, still, for a field with only a caret in it: that is what
    /// ^C means in a one-line box, and it is what this did before there was
    /// any selection to speak of.
    public func copyAll() {
        let copied = selectedText ?? text

        guard !copied.isEmpty else {
            return
        }

        resolvedPasteboard?.copy(copied)
    }

    /// Click places the cursor; double-click walks word → everything → none.
    public override func mouseEvent(_ mouse: MouseInput) -> Bool {
        guard mouse.button == .left else {
            return false
        }

        switch mouse.action {
        case .press:
            // Stashed before the caret clears it: the press of a double-click
            // lands first, and the ladder has to know which rung it was on.
            selectionBeforeClick = selectedRange
            clearSelection()
            moveCursor(to: scrollOffset + mouse.position.x)
            return true

        case .click where mouse.clickCount >= 2:
            escalateSelection(at: scrollOffset + mouse.position.x)
            return true

        default:
            return false
        }
    }

    // A one-line field: its line IS everything, so the ladder is word, then
    // all, then nothing — one rung shorter than an editor's, which falls out
    // of passing the same range for both.
    private func escalateSelection(at index: Int) {
        let characters = Array(text)

        guard !characters.isEmpty else {
            return
        }

        let word = wordRange(around: min(index, characters.count - 1), in: characters)
        let all = 0..<characters.count
        let current = selectionBeforeClick

        switch SelectionEscalation.nextScope(
            isWord: current == word,
            isLine: current == all,
            isAll: current == all
        ) {
        case .word:
            selectedRange = word
            moveCursor(to: word.upperBound)

        case .line, .all:
            selectedRange = all
            moveCursor(to: all.upperBound)

        case .none:
            clearSelection()
        }

        setNeedsDisplay()
    }

    // The run of word characters around an index, or the run of non-word
    // characters when the click landed on punctuation or spaces — the same
    // rule the source editor uses, so a double-click means one thing.
    private func wordRange(around index: Int, in characters: [Character]) -> Range<Int> {
        func isWord(_ character: Character) -> Bool {
            character.isLetter || character.isNumber || character == "_"
        }

        let inWord = isWord(characters[index])
        var start = index
        var end = index

        while start > 0, isWord(characters[start - 1]) == inWord {
            start -= 1
        }

        while end < characters.count, isWord(characters[end]) == inWord {
            end += 1
        }

        return start..<end
    }

    // MARK: - Editing

    private func insert(_ character: Character) {
        deleteSelection()
        var characters = Array(text)
        characters.insert(character, at: cursorIndex)
        text = String(characters)
        cursorIndex += 1
        changed()
    }

    private func deleteBackward() {
        if deleteSelection() {
            return   // Backspace over a selection removes the selection
        }

        guard cursorIndex > 0 else {
            onDeleteBackwardAtStart()   // a token field removes its last token
            return
        }

        var characters = Array(text)
        characters.remove(at: cursorIndex - 1)
        text = String(characters)
        cursorIndex -= 1
        changed()
    }

    /// Removes the selected text, if any.
    ///
    /// - Returns: Whether anything was removed.
    @discardableResult
    private func deleteSelection() -> Bool {
        guard let selected = selectedRange, !selected.isEmpty else {
            clearSelection()
            return false
        }

        var characters = Array(text)
        characters.removeSubrange(selected)
        text = String(characters)
        cursorIndex = selected.lowerBound
        clearSelection()
        changed()
        return true
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

    // What was selected when this click sequence began.
    private var selectionBeforeClick: Range<Int>?

    private func moveCursorClearingSelection(to index: Int) {
        clearSelection()
        moveCursor(to: index)
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

extension TextField: ClipboardEditing {
    public func clipboardCopy() { copyAll() }

    public func clipboardCut() {
        copyAll()

        // The selection when there is one, the whole field when there is not
        // — the same rule copy follows, so cut is copy plus delete rather
        // than a second opinion about what "the text" means.
        if !deleteSelection() {
            setText("")
            onChanged(text)
        }
    }

    public func clipboardPaste() { paste() }
}
