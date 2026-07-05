import RichSwift

/// Editable multi-line code view with syntax highlighting, selection,
/// clipboard, undo, and find.
///
/// ```text
///    1 │ func greet() {
///    2 │     print("hi")      ← RichSwift Syntax colors keywords,
///    3 │ }                      strings, numbers, and comments
/// ```
///
/// The document itself — lines, cursor, selection, undo history, search —
/// lives in ``TextEditBuffer``; this view owns input translation, painting,
/// and the viewport. Editing is line-oriented: arrows/Home/End/Page keys
/// move (with Shift, they extend the selection), Return splits a line,
/// Backspace/Delete edit and join lines, Tab inserts spaces (Shift+Tab
/// still moves focus away), and printable characters insert at the cursor.
///
/// Clipboard and history chords (both modern and classic families):
/// `^C`/`Ctrl+Insert` copy, `^X`/`Shift+Delete` cut, `^V`/`Shift+Insert`
/// paste, `^Z`/`Alt+Backspace` undo, `^Y` redo, `^A` select all. Copies
/// reach the system clipboard through the app pasteboard (OSC 52 on real
/// terminals). Note: `^C` is only consumed when a selection exists — apps
/// that keep TUIKit's default Ctrl+C-quit should consider disabling it
/// (`app.stopsOnControlC = false`) when hosting an editor.
///
/// Mouse: click places the cursor, drag selects, double-click selects the
/// word, triple-click selects the line; the wheel scrolls.
///
/// A read-only editor (`isEditable = false`) still takes focus, scrolls,
/// selects, and copies — good for a source viewer — but shows no cursor
/// and ignores edits.
///
/// For prose that should wrap rather than scroll sideways, use `TextView`.
///
/// ```swift
/// let editor = SyntaxTextView(text: source, language: "swift")
/// editor.onChanged = { source in store(source) }
/// ```
@MainActor
public final class SyntaxTextView: TUIView {
    /// Language identifier passed to RichSwift (`"swift"`, `"python"`, …).
    public var language: String {
        didSet {
            if language != oldValue {
                highlightCache.removeAll()
                setNeedsDisplay()
            }
        }
    }

    /// Whether the line-number gutter shows.
    public var showsLineNumbers = true {
        didSet {
            if showsLineNumbers != oldValue {
                setNeedsDisplay()
            }
        }
    }

    /// Spaces inserted by the Tab key.
    public var tabWidth = 4

    /// Whether keystrokes edit the text. A read-only editor still takes focus,
    /// scrolls, selects, and copies — good for a source viewer — but shows no
    /// cursor and ignores edits (Tab bubbles for focus movement).
    public var isEditable = true {
        didSet {
            if isEditable != oldValue {
                setNeedsDisplay()
            }
        }
    }

    /// Called after every edit with the full text (typing, paste, undo, …).
    public var onChanged: (String) -> Void = { _ in }

    /// Pasteboard override, mainly for tests. When `nil` (the default) the
    /// editor uses its window's application pasteboard.
    public var pasteboard: Pasteboard?

    // The document: lines, cursor, selection, undo, search.
    private let buffer: TextEditBuffer

    // Convenience alias so viewport/drawing code reads naturally.
    private var lines: [String] {
        buffer.lines
    }

    // First visible (column, line).
    private var offset = Point.zero

    // In-flight scrollbar-thumb drags: the grab offset within each thumb.
    private var scrollbarGrab: Int?    // vertical
    private var hScrollbarGrab: Int?   // horizontal

    // Whether a mouse drag is extending the selection.
    private var isDragSelecting = false

    // Highlighted runs by line index.
    private var highlightCache: [Int: [StyledRun]] = [:]

    // Active find state (nil query = find inactive).
    private var findQuery: String?
    private var findCaseSensitive = false
    private var findMatches: [TextEditBuffer.Match] = []
    private var findMatchesByLine: [Int: [Range<Int>]] = [:]
    private var currentMatchIndex: Int?

    /// Creates an editor.
    ///
    /// - Parameters:
    ///   - text: Initial contents.
    ///   - language: Language identifier for highlighting.
    public init(text: String = "", language: String = "swift") {
        self.buffer = TextEditBuffer(text: text)
        self.language = language
        super.init(frame: .zero)
    }

    /// Full text (lines joined with newlines).
    public var text: String {
        buffer.text
    }

    /// Number of lines.
    public var lineCount: Int {
        buffer.lineCount
    }

    /// Cursor position as (column, line).
    public var cursorPosition: Point {
        buffer.cursor
    }

    /// Replaces the text programmatically (silent; cursor to the top,
    /// selection cleared, undo history reset).
    ///
    /// - Parameter newText: New contents.
    public func setText(_ newText: String) {
        buffer.setText(newText)
        offset = .zero
        highlightCache.removeAll()
        clearFind()
        setNeedsDisplay()
    }

    /// Editors take keyboard focus.
    public override var acceptsFirstResponder: Bool {
        true
    }

    // MARK: - Editing commands (the Edit-menu surface)

    /// Whether a non-empty selection exists.
    public var hasSelection: Bool {
        buffer.hasSelection
    }

    /// The selected text, when any.
    public var selectedText: String? {
        buffer.selectedText
    }

    /// Whether an edit can be undone.
    public var canUndo: Bool {
        buffer.canUndo
    }

    /// Whether an undone edit can be reapplied.
    public var canRedo: Bool {
        buffer.canRedo
    }

    /// Selects the whole document.
    public func selectAll() {
        buffer.selectAll()
        setNeedsDisplay()
    }

    /// Copies the selection to the pasteboard.
    ///
    /// - Returns: True when there was a selection to copy.
    @discardableResult
    public func copySelection() -> Bool {
        guard let selected = buffer.selectedText else {
            return false
        }

        resolvedPasteboard?.copy(selected)
        return true
    }

    /// Copies the selection, then deletes it.
    public func cutSelection() {
        guard isEditable, copySelection() else {
            return
        }

        apply(buffer.deleteBackward())
    }

    /// Inserts the pasteboard contents, replacing any selection.
    public func paste() {
        guard isEditable, let contents = resolvedPasteboard?.string, !contents.isEmpty else {
            return
        }

        buffer.breakUndoCoalescing()
        apply(buffer.insert(contents))
    }

    /// Undoes the most recent edit (a typing run undoes as one step).
    public func undo() {
        apply(buffer.undo())
    }

    /// Reapplies the most recently undone edit.
    public func redo() {
        apply(buffer.redo())
    }

    // The editor's pasteboard: the injected one, or the app's.
    private var resolvedPasteboard: Pasteboard? {
        pasteboard ?? owningWindow?.app?.pasteboard
    }

    // MARK: - Find & goto

    /// Number of active find matches.
    public var findMatchCount: Int {
        findMatches.count
    }

    /// Starts (or updates) a find, highlighting every match. Matches stay
    /// current across edits until ``clearFind()``.
    ///
    /// - Parameters:
    ///   - query: Text to find; empty clears the find.
    ///   - caseSensitive: Whether case must match. Defaults to false.
    /// - Returns: Number of matches.
    @discardableResult
    public func findMatches(of query: String, caseSensitive: Bool = false) -> Int {
        guard !query.isEmpty else {
            clearFind()
            return 0
        }

        findQuery = query
        findCaseSensitive = caseSensitive
        currentMatchIndex = nil
        recomputeMatches()
        setNeedsDisplay()
        return findMatches.count
    }

    /// Ends the find, removing all match highlights.
    public func clearFind() {
        findQuery = nil
        findMatches = []
        findMatchesByLine = [:]
        currentMatchIndex = nil
        setNeedsDisplay()
    }

    /// Selects and reveals the next match after the cursor, wrapping.
    ///
    /// - Returns: True when there was a match to land on.
    @discardableResult
    public func findNext() -> Bool {
        step(forward: true)
    }

    /// Selects and reveals the previous match before the cursor, wrapping.
    ///
    /// - Returns: True when there was a match to land on.
    @discardableResult
    public func findPrevious() -> Bool {
        step(forward: false)
    }

    /// Replaces the current match (the one `findNext` landed on) and moves
    /// to the next one.
    ///
    /// - Parameter replacement: Text to substitute.
    /// - Returns: True when a current match was replaced.
    @discardableResult
    public func replaceCurrentMatch(with replacement: String) -> Bool {
        guard isEditable, let index = currentMatchIndex, index < findMatches.count else {
            return false
        }

        buffer.select(findMatches[index])
        buffer.breakUndoCoalescing()
        apply(buffer.insert(replacement))
        findNext()
        return true
    }

    /// Replaces every match.
    ///
    /// - Parameter replacement: Text to substitute.
    /// - Returns: Number of replacements made.
    @discardableResult
    public func replaceAllMatches(with replacement: String) -> Int {
        guard isEditable, let query = findQuery else {
            return 0
        }

        let count = buffer.replaceAll(of: query, with: replacement, caseSensitive: findCaseSensitive)
        highlightCache.removeAll()
        recomputeMatches()
        ensureCursorVisible()
        setNeedsDisplay()

        if count > 0 {
            onChanged(text)
        }

        return count
    }

    /// Moves the cursor to a position and centers it in the viewport (the
    /// goto-line / jump-to-diagnostic operation).
    ///
    /// - Parameters:
    ///   - line: Target line index (zero-based, clamped).
    ///   - column: Target column. Defaults to 0.
    public func scrollTo(line: Int, column: Int = 0) {
        buffer.moveCursor(to: Point(x: column, y: line))

        let contentHeight = max(1, scrollLayout().contentHeight)
        offset.y = min(
            max(0, lines.count - contentHeight),
            max(0, buffer.cursor.y - contentHeight / 2)
        )

        ensureCursorVisible()
        setNeedsDisplay()
    }

    // Lands on the next/previous match relative to the cursor, wrapping.
    private func step(forward: Bool) -> Bool {
        guard !findMatches.isEmpty else {
            return false
        }

        let cursor = buffer.cursor
        let index: Int

        if forward {
            index = findMatches.firstIndex {
                $0.line > cursor.y || ($0.line == cursor.y && $0.range.lowerBound >= cursor.x)
            } ?? 0
        } else {
            index = findMatches.lastIndex {
                $0.line < cursor.y || ($0.line == cursor.y && $0.range.upperBound < cursor.x)
            } ?? findMatches.count - 1
        }

        currentMatchIndex = index
        buffer.select(findMatches[index])
        scrollTo(line: findMatches[index].line, column: findMatches[index].range.lowerBound)
        return true
    }

    // Recomputes matches from the buffer (after edits or a new query).
    private func recomputeMatches() {
        guard let query = findQuery else {
            return
        }

        findMatches = buffer.matches(of: query, caseSensitive: findCaseSensitive)
        findMatchesByLine = Dictionary(grouping: findMatches, by: \.line)
            .mapValues { $0.map(\.range) }

        if let current = currentMatchIndex, current >= findMatches.count {
            currentMatchIndex = nil
        }
    }

    // MARK: - Scroll geometry

    /// Whether the view draws its own interior scrollbars (the default).
    /// Window chrome flips this off when it embeds the bars into its border
    /// (`Panel.embedScrollbars`), returning the reserved column/row to text.
    public var showsOwnScrollbars = true {
        didSet {
            if showsOwnScrollbars != oldValue {
                setNeedsDisplay()
            }
        }
    }

    // The longest line, in characters — the horizontal scroll extent.
    private var longestLine: Int {
        lines.reduce(0) { max($0, $1.count) }
    }

    // Which scrollbars are needed and the resulting content area. Two-pass:
    // reserving one axis's bar can push the other axis into overflow. With
    // embedded (border) bars nothing is reserved — the full area is content.
    private func scrollLayout() -> (needsV: Bool, needsH: Bool, gutter: Int, contentWidth: Int, contentHeight: Int) {
        let width = bounds.size.width
        let height = bounds.size.height
        let gutter = gutterWidth
        let bareWidth = max(0, width - gutter)

        guard showsOwnScrollbars else {
            return (false, false, gutter, bareWidth, height)
        }

        var needsV = lines.count > height && bareWidth > 1
        var needsH = longestLine > bareWidth - (needsV ? 1 : 0)
        needsV = lines.count > height - (needsH ? 1 : 0) && bareWidth > 1
        needsH = longestLine > bareWidth - (needsV ? 1 : 0)

        return (
            needsV,
            needsH,
            gutter,
            max(0, width - gutter - (needsV ? 1 : 0)),
            max(0, height - (needsH ? 1 : 0))
        )
    }

    // MARK: - Drawing

    /// Draws the gutter and the visible, highlighted slice of lines, with
    /// selection and find-match overlays.
    public override func draw(_ painter: Painter) {
        let width = bounds.size.width
        let height = bounds.size.height

        guard height > 0, width > 0 else {
            return
        }

        let layout = scrollLayout()
        let gutter = layout.gutter
        let contentWidth = layout.contentWidth
        let contentHeight = layout.contentHeight
        let theme = effectiveTheme
        let currentMatch = currentMatchIndex.map { findMatches[$0] }

        for viewportRow in 0..<contentHeight {
            let lineIndex = offset.y + viewportRow

            guard lineIndex < lines.count else {
                break
            }

            if gutter > 0 {
                let number = String(lineIndex + 1)
                let padded = String(repeating: " ", count: max(0, gutter - 2 - number.count)) + number + " │"
                painter.write(padded, at: Point(x: 0, y: viewportRow), style: CellStyle(flags: .dim))
            }

            let selection = buffer.selection(onLine: lineIndex)
            let matchRanges = findMatchesByLine[lineIndex] ?? []

            // Highlighted runs, sliced by the horizontal offset, with the
            // selection and match overlays applied per character.
            var documentColumn = 0

            for run in highlightedRuns(for: lineIndex) {
                for character in run.text {
                    let viewportColumn = documentColumn - offset.x

                    if viewportColumn >= 0, viewportColumn < contentWidth {
                        var style = run.style

                        if matchRanges.contains(where: { $0.contains(documentColumn) }) {
                            let isCurrent = currentMatch?.line == lineIndex
                                && currentMatch?.range.contains(documentColumn) == true
                            style = theme.selection

                            if !isCurrent {
                                style.flags.insert(.dim)
                            }
                        }

                        if selection?.contains(documentColumn) == true {
                            style = theme.selection

                            if isFirstResponder {
                                style.flags.insert(.bold)
                            }
                        }

                        painter.set(
                            TerminalCell(character: character, style: style),
                            at: Point(x: gutter + viewportColumn, y: viewportRow)
                        )
                    }

                    documentColumn += 1
                }
            }

            // A selected empty line still shows one selected cell, so
            // multi-line selections stay visible across blank lines.
            if lines[lineIndex].isEmpty, buffer.selection(onLine: lineIndex) != nil || selectedLineIsInside(lineIndex) {
                if offset.x == 0 {
                    painter.set(
                        TerminalCell(character: " ", style: theme.selection),
                        at: Point(x: gutter, y: viewportRow)
                    )
                }
            }
        }

        if layout.needsV {
            drawVScrollbar(painter, at: width - 1, height: contentHeight)
        }

        if layout.needsH {
            drawHScrollbar(painter, at: height - 1, x0: gutter, width: contentWidth)
        }

        // Cursor cell inverts while focused (editable only — a read-only
        // viewer scrolls but shows no insertion point).
        let cursor = buffer.cursor

        if isFirstResponder, isEditable,
           cursor.y >= offset.y, cursor.y < offset.y + contentHeight,
           cursor.x >= offset.x, cursor.x < offset.x + contentWidth {
            let line = lines[cursor.y]
            let character: Character = cursor.x < line.count
                ? line[line.index(line.startIndex, offsetBy: cursor.x)]
                : " "

            painter.set(
                TerminalCell(character: character, style: CellStyle(flags: .inverse)),
                at: Point(x: gutter + cursor.x - offset.x, y: cursor.y - offset.y)
            )
        }
    }

    // Whether a whole (empty) line sits strictly inside a multi-line selection.
    private func selectedLineIsInside(_ line: Int) -> Bool {
        guard let (start, end) = buffer.selectedRange else {
            return false
        }

        return line > start.y && line < end.y
    }

    // A solid proportional indicator (dim track, bright thumb — no glyph
    // patterns), reusing ScrollView's indicator styling.
    private func drawVScrollbar(_ painter: Painter, at column: Int, height: Int) {
        let (track, thumb) = ScrollView.indicatorStyles(for: effectiveTheme, focused: isFirstResponder)
        let (start, length) = vScrollbarThumb(height: height)

        for y in 0..<height {
            let inThumb = y >= start && y < start + length
            painter.set(TerminalCell(character: " ", style: inThumb ? thumb : track), at: Point(x: column, y: y))
        }
    }

    private func drawHScrollbar(_ painter: Painter, at row: Int, x0: Int, width: Int) {
        let (track, thumb) = ScrollView.indicatorStyles(for: effectiveTheme, focused: isFirstResponder)
        let (start, length) = hScrollbarThumb(width: width)

        for x in 0..<width {
            let inThumb = x >= start && x < start + length
            painter.set(TerminalCell(character: " ", style: inThumb ? thumb : track), at: Point(x: x0 + x, y: row))
        }
    }

    // Thumb start/length over the line count / longest line — shared by drawing
    // and dragging so the thumb the user grabs is the one drawn.
    private func vScrollbarThumb(height: Int) -> (start: Int, length: Int) {
        let count = lines.count
        let length = max(1, height * height / max(1, count))
        let maxStart = max(0, height - length)
        let maxOffset = max(1, count - height)
        let start = min(maxStart, offset.y * maxStart / maxOffset)
        return (start, length)
    }

    private func hScrollbarThumb(width: Int) -> (start: Int, length: Int) {
        let total = longestLine
        let length = max(1, width * width / max(1, total))
        let maxStart = max(0, width - length)
        let maxOffset = max(1, total - width)
        let start = min(maxStart, offset.x * maxStart / maxOffset)
        return (start, length)
    }

    // MARK: - Keyboard

    /// Movement (Shift extends), editing, clipboard, and history keys.
    public override func keyDown(_ key: KeyInput) -> Bool {
        if let handled = handleChord(key) {
            return handled
        }

        // Movement accepts plain or Shift (extend); editing accepts plain.
        // Plain characters may arrive with a stray shift flag on some
        // terminals, so character insertion tolerates it.
        let extending = key.modifiers == .shift

        guard key.modifiers.isEmpty || extending else {
            return false
        }

        let cursor = buffer.cursor

        switch key.key {
        case .up:
            move(to: Point(x: cursor.x, y: cursor.y - 1), extending: extending)
            return true

        case .down:
            move(to: Point(x: cursor.x, y: cursor.y + 1), extending: extending)
            return true

        case .left:
            if !extending, let (start, _) = buffer.selectedRange {
                move(to: start, extending: false)   // collapse to the left edge
            } else if cursor.x > 0 {
                move(to: Point(x: cursor.x - 1, y: cursor.y), extending: extending)
            } else if cursor.y > 0 {
                move(to: Point(x: lines[cursor.y - 1].count, y: cursor.y - 1), extending: extending)
            }

            return true

        case .right:
            if !extending, let (_, end) = buffer.selectedRange {
                move(to: end, extending: false)   // collapse to the right edge
            } else if cursor.x < lines[cursor.y].count {
                move(to: Point(x: cursor.x + 1, y: cursor.y), extending: extending)
            } else if cursor.y < lines.count - 1 {
                move(to: Point(x: 0, y: cursor.y + 1), extending: extending)
            }

            return true

        case .home:
            move(to: Point(x: 0, y: cursor.y), extending: extending)
            return true

        case .end:
            move(to: Point(x: lines[cursor.y].count, y: cursor.y), extending: extending)
            return true

        case .pageUp:
            move(to: Point(x: cursor.x, y: cursor.y - max(1, bounds.size.height - 1)), extending: extending)
            return true

        case .pageDown:
            move(to: Point(x: cursor.x, y: cursor.y + max(1, bounds.size.height - 1)), extending: extending)
            return true

        case .enter where isEditable && !extending:
            buffer.breakUndoCoalescing()
            apply(buffer.insert("\n"))
            return true

        case .backspace where isEditable && !extending:
            apply(buffer.deleteBackward())
            return true

        case .delete where isEditable && !extending:
            apply(buffer.deleteForward())
            return true

        case .tab where isEditable && !extending:
            apply(buffer.insert(String(repeating: " ", count: max(1, tabWidth))))
            return true

        case .character(let character) where isEditable:
            apply(buffer.insert(String(character)))
            return true

        default:
            return false
        }
    }

    // Clipboard/history/select-all chords, both families. Returns nil when
    // the key is not a chord (movement/editing handling continues).
    private func handleChord(_ key: KeyInput) -> Bool? {
        if key.modifiers == .control {
            switch key.key {
            case .character("a"):
                selectAll()
                return true

            case .character("c") where hasSelection, .insert where hasSelection:
                copySelection()
                return true

            case .character("x") where isEditable && hasSelection:
                cutSelection()
                return true

            case .character("v") where isEditable:
                paste()
                return true

            case .character("z") where isEditable:
                undo()
                return true

            case .character("y") where isEditable:
                redo()
                return true

            default:
                return nil
            }
        }

        if key.modifiers == .shift {
            switch key.key {
            case .insert where isEditable:
                paste()
                return true

            case .delete where isEditable && hasSelection:
                cutSelection()
                return true

            default:
                return nil
            }
        }

        if key.modifiers == .alt, key.key == .backspace, isEditable {
            undo()
            return true
        }

        return nil
    }

    // MARK: - Mouse

    /// Click places the cursor (or works a scrollbar), drag selects,
    /// double-click selects the word, triple-click the line; wheel scrolls.
    public override func mouseEvent(_ mouse: MouseInput) -> Bool {
        let width = bounds.size.width
        let height = bounds.size.height
        let layout = scrollLayout()

        switch mouse.action {
        case .press where mouse.button == .left:
            // The reserved last column / bottom row are the scrollbars: drag a
            // thumb, or click the track to page toward the click.
            if layout.needsV, mouse.position.x == width - 1, mouse.position.y < layout.contentHeight {
                pressVScrollbar(atRow: mouse.position.y, height: layout.contentHeight)
                return true
            }

            if layout.needsH, mouse.position.y == height - 1,
               mouse.position.x >= layout.gutter, mouse.position.x < layout.gutter + layout.contentWidth {
                pressHScrollbar(atColumn: mouse.position.x - layout.gutter, width: layout.contentWidth)
                return true
            }

            isDragSelecting = true
            move(to: documentPosition(of: mouse.position), extending: mouse.modifiers.contains(.shift))
            return true

        case .drag where scrollbarGrab != nil:
            dragVScrollbar(toRow: mouse.position.y, height: layout.contentHeight)
            return true

        case .drag where hScrollbarGrab != nil:
            dragHScrollbar(toColumn: mouse.position.x - layout.gutter, width: layout.contentWidth)
            return true

        case .drag where isDragSelecting:
            move(to: documentPosition(of: mouse.position), extending: true)
            return true

        case .release:
            guard scrollbarGrab != nil || hScrollbarGrab != nil || isDragSelecting else {
                return false
            }

            scrollbarGrab = nil
            hScrollbarGrab = nil
            isDragSelecting = false
            return true

        case .click where mouse.clickCount == 2:
            buffer.selectWord(at: documentPosition(of: mouse.position))
            setNeedsDisplay()
            return true

        case .click where mouse.clickCount >= 3:
            buffer.selectLine(documentPosition(of: mouse.position).y)
            setNeedsDisplay()
            return true

        case .scrollUp:
            offset.y = max(0, offset.y - 1)
            setNeedsDisplay()
            return true

        case .scrollDown:
            offset.y = min(max(0, lines.count - layout.contentHeight), offset.y + 1)
            setNeedsDisplay()
            return true

        default:
            return false
        }
    }

    // Converts a viewport mouse position to a document position.
    private func documentPosition(of position: Point) -> Point {
        Point(
            x: max(0, offset.x + position.x - gutterWidth),
            y: min(max(0, offset.y + position.y), lines.count - 1)
        )
    }

    // Press on the vertical scrollbar: grab the thumb, or page the track.
    private func pressVScrollbar(atRow row: Int, height: Int) {
        let (start, length) = vScrollbarThumb(height: height)

        if row >= start, row < start + length {
            scrollbarGrab = row - start
        } else {
            let page = max(1, height - 1)
            offset.y = min(max(0, lines.count - height), max(0, offset.y + (row < start ? -page : page)))
            setNeedsDisplay()
        }
    }

    private func dragVScrollbar(toRow row: Int, height: Int) {
        let (_, length) = vScrollbarThumb(height: height)
        let maxStart = max(0, height - length)
        let targetStart = min(maxStart, max(0, row - (scrollbarGrab ?? 0)))
        let maxOffset = max(0, lines.count - height)

        offset.y = maxStart > 0 ? targetStart * maxOffset / maxStart : 0
        setNeedsDisplay()
    }

    // Press on the horizontal scrollbar: grab the thumb, or page the track.
    private func pressHScrollbar(atColumn column: Int, width: Int) {
        let (start, length) = hScrollbarThumb(width: width)

        if column >= start, column < start + length {
            hScrollbarGrab = column - start
        } else {
            let page = max(1, width - 1)
            offset.x = min(max(0, longestLine - width), max(0, offset.x + (column < start ? -page : page)))
            setNeedsDisplay()
        }
    }

    private func dragHScrollbar(toColumn column: Int, width: Int) {
        let (_, length) = hScrollbarThumb(width: width)
        let maxStart = max(0, width - length)
        let targetStart = min(maxStart, max(0, column - (hScrollbarGrab ?? 0)))
        let maxOffset = max(0, longestLine - width)

        offset.x = maxStart > 0 ? targetStart * maxOffset / maxStart : 0
        setNeedsDisplay()
    }

    // MARK: - Buffer plumbing

    // Cursor movement (never an edit): move, reveal, repaint.
    private func move(to target: Point, extending: Bool) {
        buffer.moveCursor(to: target, extending: extending)
        ensureCursorVisible()
        setNeedsDisplay()
    }

    // Applies a mutation's aftermath: cache invalidation, live find refresh,
    // viewport, repaint, change notification.
    private func apply(_ impact: TextEditBuffer.EditImpact) {
        switch impact {
        case .none:
            return

        case .line(let line):
            highlightCache[line] = nil

        case .from(let line):
            highlightCache = highlightCache.filter { $0.key < line }
        }

        recomputeMatches()
        ensureCursorVisible()
        setNeedsDisplay()
        onChanged(text)
    }

    private func ensureCursorVisible() {
        let layout = scrollLayout()
        let contentHeight = max(1, layout.contentHeight)
        let contentWidth = max(1, layout.contentWidth)
        let cursor = buffer.cursor

        if cursor.y < offset.y {
            offset.y = cursor.y
        }

        if cursor.y > offset.y + contentHeight - 1 {
            offset.y = cursor.y - contentHeight + 1
        }

        if cursor.x < offset.x {
            offset.x = cursor.x
        }

        if cursor.x > offset.x + contentWidth - 1 {
            offset.x = cursor.x - contentWidth + 1
        }
    }

    // MARK: - Highlighting

    // Gutter width: line numbers, one space, and the │ rule.
    private var gutterWidth: Int {
        showsLineNumbers ? String(lines.count).count + 2 : 0
    }

    // Cached per-line highlighting through RichSwift Syntax.
    private func highlightedRuns(for index: Int) -> [StyledRun] {
        if let cached = highlightCache[index] {
            return cached
        }

        let line = lines[index]
        let runs: [StyledRun]

        if line.isEmpty {
            runs = []
        } else {
            let rendered = Syntax(line, language: language)
                .render(in: RenderContext(width: 4096, colorMode: .standard, markup: false))
            runs = SGRDecoder.lines(from: rendered).first ?? []
        }

        highlightCache[index] = runs
        return runs
    }
}

// MARK: - Border-embedded scrollbars

extension SyntaxTextView: BorderScrollable {
    /// Vertical scroll state. Always reported (even when every line fits) so
    /// an embedding window draws the bar as permanent chrome, Borland-style —
    /// the thumb simply fills the track while there's nothing to scroll.
    public var verticalScrollSpan: ScrollSpan? {
        let viewport = scrollLayout().contentHeight

        guard viewport > 0 else {
            return nil
        }

        return ScrollSpan(offset: offset.y, viewport: viewport, content: lines.count)
    }

    /// Horizontal scroll state; permanent like the vertical span.
    public var horizontalScrollSpan: ScrollSpan? {
        let viewport = scrollLayout().contentWidth

        guard viewport > 0 else {
            return nil
        }

        return ScrollSpan(offset: offset.x, viewport: viewport, content: longestLine)
    }

    /// Scrolls to a first-visible line, clamped.
    public func setScrollOffset(vertical newOffset: Int) {
        let viewport = scrollLayout().contentHeight
        offset.y = min(max(0, lines.count - viewport), max(0, newOffset))
        setNeedsDisplay()
    }

    /// Scrolls to a first-visible column, clamped.
    public func setScrollOffset(horizontal newOffset: Int) {
        let viewport = scrollLayout().contentWidth
        offset.x = min(max(0, longestLine - viewport), max(0, newOffset))
        setNeedsDisplay()
    }
}
