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

    /// A stretch of the text, from where it started to where it ended.
    public struct Selection: Equatable, Sendable {
        /// Where the selection was begun.
        public var anchor: Point

        /// Where it ended — before the anchor when dragged backwards.
        public var head: Point

        /// The earlier end.
        public var start: Point {
            (anchor.y, anchor.x) <= (head.y, head.x) ? anchor : head
        }

        /// The later end.
        public var end: Point {
            (anchor.y, anchor.x) <= (head.y, head.x) ? head : anchor
        }

        /// Whether it covers nothing.
        public var isEmpty: Bool {
            anchor == head
        }

        /// Creates a selection.
        public init(anchor: Point, head: Point) {
            self.anchor = anchor
            self.head = head
        }
    }

    /// What is selected, or nil for a bare caret.
    public private(set) var selection: Selection? {
        didSet {
            if selection != oldValue {
                setNeedsDisplay()
            }
        }
    }

    /// The selected text, when any.
    public var selectedText: String? {
        guard let selection, !selection.isEmpty else {
            return nil
        }

        let start = selection.start
        let end = selection.end

        guard start.y < lines.count, end.y < lines.count else {
            return nil
        }

        if start.y == end.y {
            let characters = Array(lines[start.y])
            let from = min(max(0, start.x), characters.count)
            let to = min(max(from, end.x), characters.count)
            return String(characters[from..<to])
        }

        var pieces: [String] = [String(Array(lines[start.y]).dropFirst(min(start.x, lines[start.y].count)))]

        for line in (start.y + 1)..<end.y {
            pieces.append(lines[line])
        }

        pieces.append(String(Array(lines[end.y]).prefix(end.x)))
        return pieces.joined(separator: "\n")
    }

    /// Selects everything.
    public func selectAll() {
        guard let last = lines.indices.last else {
            return
        }

        selection = Selection(anchor: .zero, head: Point(x: lines[last].count, y: last))
    }

    /// Drops the selection.
    public func clearSelection() {
        selection = nil
    }

    /// Foreground colour per LINE, for a view showing text that means
    /// different things.
    ///
    /// A transcript is the case: an error in the same ink as an answer is an
    /// error nobody sees. Per line rather than per range because that is the
    /// grain the thing showing it thinks in — a message is lines — and a
    /// range model would be a span table to keep in step with every edit.
    public var lineColors: [Int: TerminalColor] = [:] {
        didSet {
            if lineColors != oldValue {
                setNeedsDisplay()
            }
        }
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

            // A wrapped row keeps the colour of the LINE it came from, so a
            // long error stays red all the way down.
            var style = CellStyle()

            if let color = lineColors[row.line] {
                style.foreground = color
            }

            for column in 0..<row.length {
                let character = characters[row.start + column]
                var cellStyle = style

                if isSelected(line: row.line, column: row.start + column) {
                    cellStyle = effectiveTheme.selection
                }

                painter.set(TerminalCell(character: character, style: cellStyle), at: Point(x: column, y: viewportRow))
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

    // One shared painter and one shared geometry — see `ScrollbarRun`.
    private func drawScrollbar(_ painter: Painter, at column: Int, rowCount: Int, height: Int) {
        let (track, thumb) = ScrollView.indicatorStyles(for: effectiveTheme, focused: isFirstResponder)
        scrollbarRun(rowCount: rowCount, height: height)
            .draw(in: painter, vertical: true, at: column, track: track, thumb: thumb)
    }

    private func scrollbarRun(rowCount: Int, height: Int) -> ScrollbarRun {
        ScrollbarRun(
            start: 0,
            length: height,
            span: ScrollSpan(offset: offset.y, viewport: height, content: max(1, rowCount))
        )
    }

    // MARK: - Keyboard

    /// Movement and editing keys (Tab is left for focus movement).
    public override func keyDown(_ key: KeyInput) -> Bool {
        // Clipboard first: the guard below rejects every modified key, which
        // is why ^V did nothing in a commit message box.
        if isEditable, key.modifiers == .control, case .character(let letter) = key.key {
            switch Character(letter.lowercased()) {
            case "v":
                paste()
                return true

            case "c":
                copy()
                return true

            default:
                break
            }
        }

        // Shift extends the selection from wherever it was anchored; a plain
        // move collapses it, the way every other editor does.
        let extending = key.modifiers == .shift

        guard key.modifiers.isEmpty || extending else {
            return false
        }

        switch key.key {
        case .up:
            moveCursorVisually(rowDelta: -1, extending: extending)
            return true

        case .down:
            moveCursorVisually(rowDelta: 1, extending: extending)
            return true

        case .left:
            if !extending, let selection, !selection.isEmpty {
                moveCursor(line: selection.start.y, column: selection.start.x)   // collapse to the left edge
            } else if cursor.x > 0 {
                moveCursor(line: cursor.y, column: cursor.x - 1, extending: extending)
            } else if cursor.y > 0 {
                moveCursor(line: cursor.y - 1, column: lines[cursor.y - 1].count, extending: extending)
            }
            return true

        case .right:
            if !extending, let selection, !selection.isEmpty {
                moveCursor(line: selection.end.y, column: selection.end.x)   // collapse to the right edge
            } else if cursor.x < lines[cursor.y].count {
                moveCursor(line: cursor.y, column: cursor.x + 1, extending: extending)
            } else if cursor.y < lines.count - 1 {
                moveCursor(line: cursor.y + 1, column: 0, extending: extending)
            }
            return true

        case .home:
            moveCursor(line: cursor.y, column: 0, extending: extending)
            return true

        case .end:
            moveCursor(line: cursor.y, column: lines[cursor.y].count, extending: extending)
            return true

        case .pageUp:
            moveCursorVisually(rowDelta: -max(1, bounds.size.height - 1), extending: extending)
            return true

        case .pageDown:
            moveCursorVisually(rowDelta: max(1, bounds.size.height - 1), extending: extending)
            return true

        case .enter where isEditable && !extending:
            splitLine()
            return true

        case .backspace where isEditable && !extending:
            deleteBackward()
            return true

        case .delete where isEditable && !extending:
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

            // Focus on click. Without this a read-only view — a transcript,
            // a log — could never be the first responder, so ^C found no
            // editor to copy from and did nothing at all.
            owningWindow?.makeFirstResponder(self)

            selectionBeforeClick = selection
            clearSelection()

            let logical = logicalPosition(row: offset.y + mouse.position.y, column: max(0, mouse.position.x), in: rows)
            moveCursor(line: logical.line, column: logical.column)
            return true

        case .click where mouse.clickCount >= 2:
            let (rows, _, _) = layout()
            let logical = logicalPosition(row: offset.y + mouse.position.y, column: max(0, mouse.position.x), in: rows)
            escalateSelection(at: logical)
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

    // Press on the scrollbar: an arrow steps, the track pages, the thumb
    // starts a drag — all from the shared run.
    private func pressScrollbar(atRow row: Int, rowCount: Int, height: Int) {
        let run = scrollbarRun(rowCount: rowCount, height: height)
        offset.y = clampedOffset(run.offset(forPress: row, grab: &scrollbarGrab), rowCount: rowCount, height: height)
        setNeedsDisplay()
    }

    // Drag maps the thumb's top row to a proportional scroll offset.
    private func dragScrollbar(toRow row: Int, height: Int) {
        let rowCount = layout().rows.count
        let run = scrollbarRun(rowCount: rowCount, height: height)
        let target = run.offset(forThumbStart: row - (scrollbarGrab ?? 0))

        offset.y = clampedOffset(target, rowCount: rowCount, height: height)
        setNeedsDisplay()
    }

    private func clampedOffset(_ value: Int, rowCount: Int, height: Int) -> Int {
        min(max(0, value), max(0, rowCount - height))
    }

    // MARK: - Clipboard

    /// The clipboard, when a host injects one.
    public var pasteboard: Pasteboard?

    // The injected one, or the app's — the same shape `SyntaxTextView` has
    // had all along.
    private var resolvedPasteboard: Pasteboard? {
        pasteboard ?? owningWindow?.app?.pasteboard
    }

    /// Inserts the clipboard at the cursor.
    ///
    /// Newlines are KEPT here, unlike a one-line `TextField`: this is a
    /// paragraph view, and a pasted commit message is meant to have them.
    public func paste() {
        guard isEditable, let clipboard = resolvedPasteboard?.string, !clipboard.isEmpty else {
            return
        }

        for character in clipboard where character != "\r" {
            if character == "\n" {
                splitLine()
            } else {
                insert(String(character))
            }
        }
    }

    /// Copies the selection, or the whole text when nothing is selected.
    ///
    /// A transcript with no selection still copies with ^C — the whole thing,
    /// which for a log is what people want.
    public func copy() {
        if let selectedText {
            resolvedPasteboard?.copy(selectedText)
        } else {
            copyAll()
        }
    }

    /// Copies the whole text regardless of any selection.
    public func copyAll() {
        guard !text.isEmpty else {
            return
        }

        resolvedPasteboard?.copy(text)
    }

    // MARK: - Editing

    private func insert(_ string: String) {
        deleteSelection()

        var line = lines[cursor.y]
        line.insert(contentsOf: string, at: line.index(line.startIndex, offsetBy: cursor.x))
        lines[cursor.y] = line
        cursor.x += string.count
        contentsChanged()
    }

    private func splitLine() {
        deleteSelection()

        let line = lines[cursor.y]
        let split = line.index(line.startIndex, offsetBy: cursor.x)

        lines[cursor.y] = String(line[..<split])
        lines.insert(String(line[split...]), at: cursor.y + 1)
        cursor = Point(x: 0, y: cursor.y + 1)
        contentsChanged()
    }

    private func deleteBackward() {
        if deleteSelection() {
            contentsChanged()
            return
        }

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
        if deleteSelection() {
            contentsChanged()
            return
        }

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

    // Removes the selected text and leaves the cursor where it began. Every
    // edit goes through here first: typing, Enter, Backspace, Delete and
    // paste all REPLACE a selection rather than landing next to it.
    //
    // - Returns: Whether anything was selected.
    @discardableResult
    private func deleteSelection() -> Bool {
        guard let selection, !selection.isEmpty else {
            return false
        }

        self.selection = nil

        let start = selection.start
        let end = selection.end

        guard start.y < lines.count, end.y < lines.count else {
            return false
        }

        let head = Array(lines[start.y]).prefix(min(max(0, start.x), lines[start.y].count))
        let tail = Array(lines[end.y]).dropFirst(min(max(0, end.x), lines[end.y].count))

        lines.replaceSubrange(start.y...end.y, with: [String(head) + String(tail)])
        cursor = Point(x: head.count, y: start.y)
        return true
    }

    private func contentsChanged() {
        ensureCursorVisible()
        setNeedsDisplay()
        onChanged(text)
    }

    // MARK: - Cursor & viewport

    // What was selected when this click sequence began.
    private var selectionBeforeClick: Selection?

    // Whether a character falls inside the selection.
    private func isSelected(line: Int, column: Int) -> Bool {
        guard let selection, !selection.isEmpty else {
            return false
        }

        let start = selection.start
        let end = selection.end

        guard line >= start.y, line <= end.y else {
            return false
        }

        let from = line == start.y ? start.x : 0
        let to = line == end.y ? end.x : Int.max
        return column >= from && column < to
    }

    // Word, then line, then everything, then nothing — the same ladder as the
    // source editor and the text field, because a double-click should mean
    // one thing everywhere.
    private func escalateSelection(at position: (line: Int, column: Int)) {
        guard position.line < lines.count else {
            return
        }

        let characters = Array(lines[position.line])
        let word = Self.wordRange(around: min(position.column, max(0, characters.count - 1)), in: characters)
        let wordSelection = Selection(
            anchor: Point(x: word.lowerBound, y: position.line),
            head: Point(x: word.upperBound, y: position.line)
        )
        let lineSelection = Selection(
            anchor: Point(x: 0, y: position.line),
            head: Point(x: characters.count, y: position.line)
        )
        let last = max(0, lines.count - 1)
        let all = Selection(anchor: .zero, head: Point(x: lines[last].count, y: last))

        func covers(_ other: Selection) -> Bool {
            guard let current = selectionBeforeClick else {
                return false
            }

            return current.start == other.start && current.end == other.end
        }

        switch SelectionEscalation.nextScope(
            isWord: covers(wordSelection),
            isLine: covers(lineSelection),
            isAll: covers(all)
        ) {
        case .word: selection = wordSelection
        case .line: selection = lineSelection
        case .all: selection = all
        case .none: clearSelection()
        }
    }

    private static func wordRange(around index: Int, in characters: [Character]) -> Range<Int> {
        guard characters.indices.contains(index) else {
            return 0..<0
        }

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

    /// Scrolls to the bottom and puts the caret there.
    ///
    /// What a view showing a growing transcript needs after every append: a
    /// log you have to scroll to the end of yourself is a log you stop
    /// reading. Public because the alternative — a host reaching for the End
    /// key on the view's behalf — is a keystroke standing in for an intent.
    public func scrollToEnd() {
        moveCursor(line: lines.count - 1, column: lines.last?.count ?? 0)
        ensureCursorVisible()
        setNeedsDisplay()
    }

    // Moves the cursor; extending keeps (or starts) a selection anchored where
    // the cursor was, a plain move drops whatever was selected.
    private func moveCursor(line: Int, column: Int, extending: Bool = false) {
        let clampedLine = min(max(0, line), lines.count - 1)
        let clampedColumn = min(max(0, column), lines[clampedLine].count)
        let target = Point(x: clampedColumn, y: clampedLine)

        if extending {
            let anchor = selection?.anchor ?? cursor
            selection = anchor == target ? nil : Selection(anchor: anchor, head: target)
        } else {
            selection = nil
        }

        guard target != cursor else {
            return
        }

        cursor = target
        ensureCursorVisible()
        setNeedsDisplay()
    }

    // Moves the cursor up/down by visual rows, keeping its visual column.
    private func moveCursorVisually(rowDelta: Int, extending: Bool = false) {
        let rows = layout().rows
        let position = visualPosition(line: cursor.y, column: cursor.x, in: rows)
        let target = min(max(0, position.row + rowDelta), rows.count - 1)
        let logical = logicalPosition(row: target, column: position.column, in: rows)
        moveCursor(line: logical.line, column: logical.column, extending: extending)
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

extension TextView: ClipboardEditing {
    public func clipboardCopy() {
        guard let selected = selectedText, !selected.isEmpty else {
            copyAll()   // nothing chosen means the lot, as it always did
            return
        }

        resolvedPasteboard?.copy(selected)
    }

    public func clipboardCut() {
        guard isEditable else { return }

        copyAll()
        setText("", notify: true)
    }

    public func clipboardPaste() { paste() }
}
