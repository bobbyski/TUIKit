/// Editable multi-line plain-text view with word wrap.
///
/// ```text
///   Commander of the Continental   ← long lines wrap to the view
///   Army in the Revolutionary        width at word boundaries;
///   War and the first President.     Return starts a new paragraph.
/// ```
///
/// This is the prose counterpart to `SyntaxTextView`: no gutter, no syntax
/// highlighting, and lines **wrap** to the view width instead of scrolling
/// sideways — the right control for notes, comments, and descriptions. Editing
/// is line-oriented (arrows/Home/End/PageUp/PageDown move the cursor, Return
/// splits a paragraph, Backspace/Delete edit and join, printable characters
/// insert); the cursor, clicks, and the wheel all map through the wrapped
/// layout. Tab is left for focus movement, so a `TextView` sits naturally in a
/// form. Set `isEditable = false` for a scrollable read-only view.
///
/// ```swift
/// let notes = TextView(text: person.notes)
/// notes.onChanged = { person.notes = $0 }
/// ```
@MainActor
public final class TextView: TUIView {
    // Logical lines (paragraphs); wrapping is a display concern.
    private var lines: [String]

    // Cursor in logical (column, line) coordinates.
    private var cursor = Point.zero

    // First visible *visual* row and (unused while wrapping) horizontal scroll.
    private var offset = Point.zero

    /// Whether keystrokes edit the text. A read-only view still scrolls and
    /// takes focus, but shows no cursor and ignores edits.
    public var isEditable = true

    /// Called after every edit with the full text.
    public var onChanged: (String) -> Void = { _ in }

    /// Creates a text view.
    ///
    /// - Parameter text: Initial contents.
    public init(text: String = "") {
        self.lines = text.isEmpty ? [""] : text.components(separatedBy: "\n")
        super.init(frame: .zero)
    }

    /// The full text, paragraphs joined by newlines.
    public var text: String {
        lines.joined(separator: "\n")
    }

    /// Cursor position in logical (column, line) coordinates.
    public var cursorPosition: Point {
        cursor
    }

    /// Replaces the contents.
    ///
    /// - Parameters:
    ///   - newText: New contents.
    ///   - notify: Whether `onChanged` fires. Defaults to silent.
    public func setText(_ newText: String, notify: Bool = false) {
        lines = newText.isEmpty ? [""] : newText.components(separatedBy: "\n")
        cursor = .zero
        offset = .zero
        setNeedsDisplay()

        if notify {
            onChanged(text)
        }
    }

    /// Text views take keyboard focus (for editing or scrolling).
    public override var acceptsFirstResponder: Bool {
        true
    }

    // MARK: - Drawing

    /// Draws the visible wrapped rows and the cursor.
    public override func draw(_ painter: Painter) {
        let height = bounds.size.height
        let width = bounds.size.width

        guard height > 0, width > 0 else {
            return
        }

        let rows = visualRows()

        for viewportRow in 0..<height {
            let rowIndex = offset.y + viewportRow

            guard rowIndex < rows.count else {
                break
            }

            let row = rows[rowIndex]
            let characters = Array(lines[row.line])

            for column in 0..<row.length {
                let character = characters[row.start + column]
                painter.set(TerminalCell(character: character, style: CellStyle()), at: Point(x: column, y: viewportRow))
            }
        }

        // Cursor cell inverts while focused and editable.
        guard isFirstResponder, isEditable else {
            return
        }

        let position = visualPosition(line: cursor.y, column: cursor.x, in: rows)

        if position.row >= offset.y, position.row < offset.y + height, position.column < width {
            let line = lines[cursor.y]
            let character: Character = cursor.x < line.count
                ? line[line.index(line.startIndex, offsetBy: cursor.x)]
                : " "

            painter.set(
                TerminalCell(character: character, style: CellStyle(flags: .inverse)),
                at: Point(x: position.column, y: position.row - offset.y)
            )
        }
    }

    // MARK: - Keyboard

    /// Movement and editing keys (Tab is left for focus movement).
    public override func keyDown(_ key: KeyInput) -> Bool {
        guard key.modifiers.isEmpty else {
            return false
        }

        switch key.key {
        case .up:
            moveCursorVisually(rowDelta: -1)
            return true

        case .down:
            moveCursorVisually(rowDelta: 1)
            return true

        case .left:
            if cursor.x > 0 {
                moveCursor(line: cursor.y, column: cursor.x - 1)
            } else if cursor.y > 0 {
                moveCursor(line: cursor.y - 1, column: lines[cursor.y - 1].count)
            }
            return true

        case .right:
            if cursor.x < lines[cursor.y].count {
                moveCursor(line: cursor.y, column: cursor.x + 1)
            } else if cursor.y < lines.count - 1 {
                moveCursor(line: cursor.y + 1, column: 0)
            }
            return true

        case .home:
            moveCursor(line: cursor.y, column: 0)
            return true

        case .end:
            moveCursor(line: cursor.y, column: lines[cursor.y].count)
            return true

        case .pageUp:
            moveCursorVisually(rowDelta: -max(1, bounds.size.height - 1))
            return true

        case .pageDown:
            moveCursorVisually(rowDelta: max(1, bounds.size.height - 1))
            return true

        case .enter where isEditable:
            splitLine()
            return true

        case .backspace where isEditable:
            deleteBackward()
            return true

        case .delete where isEditable:
            deleteForward()
            return true

        case .character(let character) where isEditable:
            insert(String(character))
            return true

        default:
            return false
        }
    }

    // MARK: - Mouse

    /// Click places the cursor; the wheel scrolls.
    public override func mouseEvent(_ mouse: MouseInput) -> Bool {
        switch mouse.action {
        case .press where mouse.button == .left:
            let rows = visualRows()
            let logical = logicalPosition(row: offset.y + mouse.position.y, column: max(0, mouse.position.x), in: rows)
            moveCursor(line: logical.line, column: logical.column)
            return true

        case .scrollUp:
            offset.y = max(0, offset.y - 1)
            setNeedsDisplay()
            return true

        case .scrollDown:
            offset.y = min(max(0, visualRows().count - bounds.size.height), offset.y + 1)
            setNeedsDisplay()
            return true

        default:
            return false
        }
    }

    // MARK: - Editing

    private func insert(_ string: String) {
        var line = lines[cursor.y]
        line.insert(contentsOf: string, at: line.index(line.startIndex, offsetBy: cursor.x))
        lines[cursor.y] = line
        cursor.x += string.count
        contentsChanged()
    }

    private func splitLine() {
        let line = lines[cursor.y]
        let split = line.index(line.startIndex, offsetBy: cursor.x)

        lines[cursor.y] = String(line[..<split])
        lines.insert(String(line[split...]), at: cursor.y + 1)
        cursor = Point(x: 0, y: cursor.y + 1)
        contentsChanged()
    }

    private func deleteBackward() {
        if cursor.x > 0 {
            var line = lines[cursor.y]
            line.remove(at: line.index(line.startIndex, offsetBy: cursor.x - 1))
            lines[cursor.y] = line
            cursor.x -= 1
            contentsChanged()
        } else if cursor.y > 0 {
            let removed = lines.remove(at: cursor.y)
            cursor = Point(x: lines[cursor.y - 1].count, y: cursor.y - 1)
            lines[cursor.y] += removed
            contentsChanged()
        }
    }

    private func deleteForward() {
        let line = lines[cursor.y]

        if cursor.x < line.count {
            var edited = line
            edited.remove(at: edited.index(edited.startIndex, offsetBy: cursor.x))
            lines[cursor.y] = edited
            contentsChanged()
        } else if cursor.y < lines.count - 1 {
            lines[cursor.y] = line + lines.remove(at: cursor.y + 1)
            contentsChanged()
        }
    }

    private func contentsChanged() {
        ensureCursorVisible()
        setNeedsDisplay()
        onChanged(text)
    }

    // MARK: - Cursor & viewport

    private func moveCursor(line: Int, column: Int) {
        let clampedLine = min(max(0, line), lines.count - 1)
        let clampedColumn = min(max(0, column), lines[clampedLine].count)

        guard Point(x: clampedColumn, y: clampedLine) != cursor else {
            return
        }

        cursor = Point(x: clampedColumn, y: clampedLine)
        ensureCursorVisible()
        setNeedsDisplay()
    }

    // Moves the cursor up/down by visual rows, keeping its visual column.
    private func moveCursorVisually(rowDelta: Int) {
        let rows = visualRows()
        let position = visualPosition(line: cursor.y, column: cursor.x, in: rows)
        let target = min(max(0, position.row + rowDelta), rows.count - 1)
        let logical = logicalPosition(row: target, column: position.column, in: rows)
        moveCursor(line: logical.line, column: logical.column)
    }

    private func ensureCursorVisible() {
        let height = bounds.size.height

        guard height > 0 else {
            return
        }

        let rows = visualRows()
        let position = visualPosition(line: cursor.y, column: cursor.x, in: rows)

        if position.row < offset.y {
            offset.y = position.row
        }

        if position.row > offset.y + height - 1 {
            offset.y = position.row - height + 1
        }
    }

    // MARK: - Soft wrap

    // A visual row: which logical line it belongs to, and the [start, start +
    // length) character range of that line it shows.
    private typealias VisualRow = (line: Int, start: Int, length: Int)

    // Word-wraps every logical line to the view width. An empty line still
    // occupies one visual row.
    private func visualRows() -> [VisualRow] {
        let width = max(1, bounds.size.width)
        var rows: [VisualRow] = []

        for (lineIndex, text) in lines.enumerated() {
            let characters = Array(text)

            if characters.isEmpty {
                rows.append((lineIndex, 0, 0))
                continue
            }

            var start = 0

            while start < characters.count {
                let remaining = characters.count - start

                if remaining <= width {
                    rows.append((lineIndex, start, remaining))
                    break
                }

                // Break at the last space within the window; hard-break a word
                // that is longer than the width.
                var breakAt = -1
                var scan = start + width - 1

                while scan > start {
                    if characters[scan] == " " {
                        breakAt = scan
                        break
                    }
                    scan -= 1
                }

                if breakAt > start {
                    rows.append((lineIndex, start, breakAt - start))
                    start = breakAt + 1
                } else {
                    rows.append((lineIndex, start, width))
                    start += width
                }
            }
        }

        return rows.isEmpty ? [(0, 0, 0)] : rows
    }

    // Logical (line, column) → visual (row index, column within the row).
    private func visualPosition(line: Int, column: Int, in rows: [VisualRow]) -> (row: Int, column: Int) {
        var lastRow = 0

        for (index, row) in rows.enumerated() where row.line == line {
            lastRow = index

            if column < row.start + row.length || index + 1 >= rows.count || rows[index + 1].line != line {
                return (index, max(0, column - row.start))
            }
        }

        return (lastRow, 0)
    }

    // Visual (row index, column) → logical (line, column).
    private func logicalPosition(row: Int, column: Int, in rows: [VisualRow]) -> (line: Int, column: Int) {
        let clamped = rows[min(max(0, row), rows.count - 1)]
        return (clamped.line, min(clamped.start + max(0, column), clamped.start + clamped.length))
    }
}
