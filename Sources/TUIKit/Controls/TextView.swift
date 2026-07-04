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

    // In-flight scrollbar-thumb drag: the grab offset within the thumb.
    private var scrollbarGrab: Int?

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

    /// Draws the visible wrapped rows, the cursor, and — when the content
    /// overflows — a proportional scroll indicator in the reserved last column.
    public override func draw(_ painter: Painter) {
        let height = bounds.size.height
        let width = bounds.size.width

        guard height > 0, width > 0 else {
            return
        }

        let (rows, contentWidth, scrollbar) = layout()

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

        if scrollbar {
            drawScrollbar(painter, at: width - 1, rowCount: rows.count, height: height)
        }

        // Cursor cell inverts while focused and editable.
        guard isFirstResponder, isEditable else {
            return
        }

        let position = visualPosition(line: cursor.y, column: cursor.x, in: rows)

        if position.row >= offset.y, position.row < offset.y + height, position.column < contentWidth {
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

    // A solid proportional indicator (dim track, bright thumb — no glyph
    // patterns), reusing ScrollView's indicator styling.
    private func drawScrollbar(_ painter: Painter, at column: Int, rowCount: Int, height: Int) {
        let (track, thumb) = ScrollView.indicatorStyles(for: effectiveTheme, focused: isFirstResponder)
        let (start, length) = scrollbarThumb(rowCount: rowCount, height: height)

        for y in 0..<height {
            let inThumb = y >= start && y < start + length
            painter.set(TerminalCell(character: " ", style: inThumb ? thumb : track), at: Point(x: column, y: y))
        }
    }

    // Thumb start row and length for the current scroll — shared by drawing
    // and dragging so the thumb the user grabs is the one drawn.
    private func scrollbarThumb(rowCount: Int, height: Int) -> (start: Int, length: Int) {
        let length = max(1, height * height / rowCount)
        let maxStart = max(0, height - length)
        let maxOffset = max(1, rowCount - height)
        let start = min(maxStart, offset.y * maxStart / maxOffset)
        return (start, length)
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

    /// Click places the cursor (or works the scrollbar); the wheel scrolls.
    public override func mouseEvent(_ mouse: MouseInput) -> Bool {
        let height = bounds.size.height

        switch mouse.action {
        case .press where mouse.button == .left:
            let (rows, _, scrollbar) = layout()

            // The reserved last column is the scrollbar: drag the thumb, or
            // click the track to page toward the click.
            if scrollbar, mouse.position.x == bounds.size.width - 1 {
                pressScrollbar(atRow: mouse.position.y, rowCount: rows.count, height: height)
                return true
            }

            let logical = logicalPosition(row: offset.y + mouse.position.y, column: max(0, mouse.position.x), in: rows)
            moveCursor(line: logical.line, column: logical.column)
            return true

        case .drag where scrollbarGrab != nil:
            dragScrollbar(toRow: mouse.position.y, height: height)
            return true

        case .release where scrollbarGrab != nil:
            scrollbarGrab = nil
            return true

        case .scrollUp:
            offset.y = max(0, offset.y - 1)
            setNeedsDisplay()
            return true

        case .scrollDown:
            offset.y = min(max(0, layout().rows.count - height), offset.y + 1)
            setNeedsDisplay()
            return true

        default:
            return false
        }
    }

    // Press on the scrollbar: grab the thumb, or page the track.
    private func pressScrollbar(atRow row: Int, rowCount: Int, height: Int) {
        let (start, length) = scrollbarThumb(rowCount: rowCount, height: height)

        if row >= start, row < start + length {
            scrollbarGrab = row - start
        } else {
            let page = max(1, height - 1)
            offset.y = min(max(0, rowCount - height), max(0, offset.y + (row < start ? -page : page)))
            setNeedsDisplay()
        }
    }

    // Drag maps the thumb's top row to a proportional scroll offset.
    private func dragScrollbar(toRow row: Int, height: Int) {
        let rowCount = layout().rows.count
        let (_, length) = scrollbarThumb(rowCount: rowCount, height: height)
        let maxStart = max(0, height - length)
        let targetStart = min(maxStart, max(0, row - (scrollbarGrab ?? 0)))
        let maxOffset = max(0, rowCount - height)

        offset.y = maxStart > 0 ? targetStart * maxOffset / maxStart : 0
        setNeedsDisplay()
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
        let rows = layout().rows
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

        let rows = layout().rows
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

    // The wrapped rows plus the layout they were wrapped for: the text width
    // and whether the last column is reserved for a scrollbar. The scrollbar
    // shows only when content overflows; reserving its column narrows the
    // wrap width, so this decides both together. (Narrowing can only add
    // rows, never remove them, so the overflow test stays consistent.)
    private func layout() -> (rows: [VisualRow], contentWidth: Int, scrollbar: Bool) {
        let width = max(1, bounds.size.width)
        let height = bounds.size.height
        let full = visualRows(width: width)

        if width > 1, full.count > height {
            return (visualRows(width: width - 1), width - 1, true)
        }

        return (full, width, false)
    }

    // Word-wraps every logical line to `width`. An empty line still occupies
    // one visual row.
    private func visualRows(width rawWidth: Int) -> [VisualRow] {
        let width = max(1, rawWidth)
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
