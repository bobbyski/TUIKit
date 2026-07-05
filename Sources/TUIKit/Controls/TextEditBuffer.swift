/// The pure text-editing engine behind `SyntaxTextView`.
///
/// Owns the *document*: lines, cursor, selection, undo history, and search —
/// no drawing, no input decoding, no scrolling. The view translates keys and
/// mouse gestures into calls here and paints what the buffer holds, which
/// keeps each half small and lets every editing behavior be unit-tested
/// without rendering a cell.
///
/// ```text
///   SyntaxTextView  (input + painting + viewport)
///        │  moveCursor / insert / undo / matches …
///        ▼
///   TextEditBuffer  (lines · cursor · selection · undo · find)
/// ```
///
/// Positions are `Point`s with `x` = character column, `y` = line index,
/// following the view's existing convention. All mutating operations clamp
/// their inputs, are selection-aware, and are undoable. Mutations report an
/// ``EditImpact`` so the caller can invalidate exactly the highlight cache
/// lines that changed.
@MainActor
public final class TextEditBuffer {
    /// What part of the document a mutation touched.
    public enum EditImpact: Equatable, Sendable {
        /// Nothing changed.
        case none

        /// One line's content changed.
        case line(Int)

        /// Structure changed from this line down (insert/join/split).
        case from(Int)
    }

    /// One search hit: a line index and the matched column range.
    public struct Match: Equatable, Sendable {
        /// Line index of the match.
        public let line: Int

        /// Matched character-column range within the line.
        public let range: Range<Int>
    }

    // MARK: - State

    /// Document lines; always at least one (possibly empty) line.
    public private(set) var lines: [String]

    /// Cursor as (column, line), clamped to the document.
    public private(set) var cursor = Point.zero

    /// Selection anchor, when a selection is active. The selection spans
    /// anchor↔cursor; equal endpoints mean no selection.
    public private(set) var selectionAnchor: Point?

    // Undo/redo stacks of applied operations.
    private var undoStack: [EditOperation] = []
    private var redoStack: [EditOperation] = []

    // Whether the next single-character insert may extend the top undo op.
    private var coalescing = false

    /// Creates a buffer.
    ///
    /// - Parameter text: Initial contents.
    public init(text: String = "") {
        self.lines = Self.split(text)
    }

    /// Full text (lines joined with newlines).
    public var text: String {
        lines.joined(separator: "\n")
    }

    /// Number of lines.
    public var lineCount: Int {
        lines.count
    }

    /// Replaces the text programmatically: cursor to the top, selection
    /// cleared, undo history reset. The "load a document" operation.
    ///
    /// - Parameter newText: New contents.
    public func setText(_ newText: String) {
        lines = Self.split(newText)
        cursor = .zero
        selectionAnchor = nil
        undoStack = []
        redoStack = []
        coalescing = false
    }

    // MARK: - Selection

    /// Whether a non-empty selection exists.
    public var hasSelection: Bool {
        selectedRange != nil
    }

    /// The selection as (start, end), normalized start ≤ end, or `nil`.
    public var selectedRange: (start: Point, end: Point)? {
        guard let anchor = selectionAnchor, anchor != cursor else {
            return nil
        }

        return isOrdered(anchor, cursor) ? (anchor, cursor) : (cursor, anchor)
    }

    /// The selected text, or `nil` without a selection.
    public var selectedText: String? {
        selectedRange.map { textIn(from: $0.start, to: $0.end) }
    }

    /// The selected column range on one line, for drawing, or `nil` when
    /// the selection does not touch that line.
    ///
    /// - Parameter line: Line index.
    /// - Returns: The selected columns on that line.
    public func selection(onLine line: Int) -> Range<Int>? {
        guard let (start, end) = selectedRange,
              line >= start.y, line <= end.y, line < lines.count else {
            return nil
        }

        let from = line == start.y ? start.x : 0
        let to = line == end.y ? end.x : lines[line].count

        return from < to ? from..<to : nil
    }

    /// Moves the cursor, optionally extending the selection.
    ///
    /// - Parameters:
    ///   - target: Destination (clamped to the document).
    ///   - extending: True keeps/starts a selection from the old position
    ///     (Shift+movement); false clears any selection.
    public func moveCursor(to target: Point, extending: Bool = false) {
        if extending {
            if selectionAnchor == nil {
                selectionAnchor = cursor
            }
        } else {
            selectionAnchor = nil
        }

        cursor = clamp(target)
        coalescing = false
    }

    /// Selects the whole document.
    public func selectAll() {
        selectionAnchor = .zero
        cursor = endOfDocument
        coalescing = false
    }

    /// Selects the word at a position (double-click). Word characters are
    /// letters, digits, and underscore; on a non-word character only that
    /// character is selected.
    ///
    /// - Parameter position: Position inside the word.
    public func selectWord(at position: Point) {
        let clamped = clamp(position)
        let line = lines[clamped.y]

        guard !line.isEmpty else {
            moveCursor(to: clamped)
            return
        }

        let characters = Array(line)
        let column = min(clamped.x, characters.count - 1)

        var start = column
        var end = column + 1

        if Self.isWordCharacter(characters[column]) {
            while start > 0, Self.isWordCharacter(characters[start - 1]) {
                start -= 1
            }

            while end < characters.count, Self.isWordCharacter(characters[end]) {
                end += 1
            }
        }

        selectionAnchor = Point(x: start, y: clamped.y)
        cursor = Point(x: end, y: clamped.y)
        coalescing = false
    }

    /// Selects one whole line (triple-click), including its line break when
    /// a next line exists.
    ///
    /// - Parameter line: Line index.
    public func selectLine(_ line: Int) {
        let index = min(max(0, line), lines.count - 1)
        selectionAnchor = Point(x: 0, y: index)
        cursor = index < lines.count - 1
            ? Point(x: 0, y: index + 1)
            : Point(x: lines[index].count, y: index)
        coalescing = false
    }

    /// Clears the selection, leaving the cursor in place.
    public func clearSelection() {
        selectionAnchor = nil
    }

    // MARK: - Editing

    /// Inserts text at the cursor, replacing any selection. Single printable
    /// characters coalesce into the previous typing run for undo.
    ///
    /// - Parameter string: Text to insert (may contain newlines).
    /// - Returns: What changed, for cache invalidation.
    @discardableResult
    public func insert(_ string: String) -> EditImpact {
        let range = selectedRange ?? (cursor, cursor)
        let isTyping = string.count == 1 && !string.contains("\n") && !hasSelection

        let impact = perform(EditOperation(
            start: range.start,
            removed: textIn(from: range.start, to: range.end),
            inserted: string,
            cursorBefore: cursor,
            anchorBefore: selectionAnchor
        ))

        if isTyping, coalescing, redoStack.isEmpty, undoStack.count >= 2 {
            // Merge this one-character op into the run before it.
            let top = undoStack.removeLast()
            var previous = undoStack.removeLast()

            if previous.removed.isEmpty, previous.end == top.start {
                previous.inserted += top.inserted
                previous.cursorAfter = top.cursorAfter
                undoStack.append(previous)
            } else {
                undoStack.append(previous)
                undoStack.append(top)
            }
        }

        coalescing = isTyping
        return impact
    }

    /// Deletes the selection, or the character before the cursor (joining
    /// lines at column 0).
    ///
    /// - Returns: What changed, for cache invalidation.
    @discardableResult
    public func deleteBackward() -> EditImpact {
        if let (start, end) = selectedRange {
            return delete(from: start, to: end)
        }

        if cursor.x > 0 {
            return delete(from: Point(x: cursor.x - 1, y: cursor.y), to: cursor)
        }

        if cursor.y > 0 {
            return delete(from: Point(x: lines[cursor.y - 1].count, y: cursor.y - 1), to: cursor)
        }

        return .none
    }

    /// Deletes the selection, or the character after the cursor (joining
    /// lines at the end of a line).
    ///
    /// - Returns: What changed, for cache invalidation.
    @discardableResult
    public func deleteForward() -> EditImpact {
        if let (start, end) = selectedRange {
            return delete(from: start, to: end)
        }

        if cursor.x < lines[cursor.y].count {
            return delete(from: cursor, to: Point(x: cursor.x + 1, y: cursor.y))
        }

        if cursor.y < lines.count - 1 {
            return delete(from: cursor, to: Point(x: 0, y: cursor.y + 1))
        }

        return .none
    }

    // MARK: - Undo / Redo

    /// Whether an operation can be undone.
    public var canUndo: Bool {
        !undoStack.isEmpty
    }

    /// Whether an undone operation can be reapplied.
    public var canRedo: Bool {
        !redoStack.isEmpty
    }

    /// Undoes the most recent operation (typing runs undo as one step).
    ///
    /// - Returns: What changed, for cache invalidation.
    @discardableResult
    public func undo() -> EditImpact {
        guard let operation = undoStack.popLast() else {
            return .none
        }

        redoStack.append(operation)
        coalescing = false

        let impact = replace(from: operation.start, to: operation.end, with: operation.removed)
        cursor = operation.cursorBefore
        selectionAnchor = operation.anchorBefore
        return impact
    }

    /// Reapplies the most recently undone operation.
    ///
    /// - Returns: What changed, for cache invalidation.
    @discardableResult
    public func redo() -> EditImpact {
        guard let operation = redoStack.popLast() else {
            return .none
        }

        undoStack.append(operation)
        coalescing = false

        let impact = replace(from: operation.start, to: operation.removedEnd, with: operation.inserted)
        cursor = operation.cursorAfter
        selectionAnchor = nil
        return impact
    }

    /// Ends the current typing run: the next insert starts a new undo step.
    public func breakUndoCoalescing() {
        coalescing = false
    }

    // MARK: - Find

    /// All non-overlapping matches of a query, top to bottom.
    ///
    /// - Parameters:
    ///   - query: Text to find; empty finds nothing.
    ///   - caseSensitive: Whether case must match. Defaults to false.
    /// - Returns: Matches in document order.
    public func matches(of query: String, caseSensitive: Bool = false) -> [Match] {
        guard !query.isEmpty else {
            return []
        }

        let needle = caseSensitive ? query : query.lowercased()
        var result: [Match] = []

        for (index, line) in lines.enumerated() {
            let haystack = caseSensitive ? line : line.lowercased()
            let characters = Array(haystack)
            let pattern = Array(needle)
            var column = 0

            while column + pattern.count <= characters.count {
                if Array(characters[column..<(column + pattern.count)]) == pattern {
                    result.append(Match(line: index, range: column..<(column + pattern.count)))
                    column += pattern.count
                } else {
                    column += 1
                }
            }
        }

        return result
    }

    /// Replaces every match of a query in one undoable step per match.
    ///
    /// - Parameters:
    ///   - query: Text to find.
    ///   - replacement: Text to substitute.
    ///   - caseSensitive: Whether case must match. Defaults to false.
    /// - Returns: How many replacements were made.
    @discardableResult
    public func replaceAll(
        of query: String,
        with replacement: String,
        caseSensitive: Bool = false
    ) -> Int {
        // Bottom-up so earlier match positions stay valid.
        let found = matches(of: query, caseSensitive: caseSensitive).reversed()

        for match in found {
            selectionAnchor = Point(x: match.range.lowerBound, y: match.line)
            cursor = Point(x: match.range.upperBound, y: match.line)
            insert(replacement)
        }

        clearSelection()
        return found.count
    }

    /// Selects a match (the "find next lands here" operation).
    ///
    /// - Parameter match: Match to select.
    public func select(_ match: Match) {
        selectionAnchor = Point(x: match.range.lowerBound, y: match.line)
        cursor = Point(x: match.range.upperBound, y: match.line)
        coalescing = false
    }

    // MARK: - Core replace (the one primitive every edit routes through)

    // One recorded, invertible edit: `removed` was replaced by `inserted`
    // starting at `start`.
    private struct EditOperation {
        let start: Point
        var removed: String
        var inserted: String
        let cursorBefore: Point
        let anchorBefore: Point?
        var cursorAfter = Point.zero

        // End of the *inserted* text (for undo's reverse replace).
        var end: Point {
            TextEditBuffer.end(of: inserted, from: start)
        }

        // End of the *removed* text (for redo's forward replace).
        var removedEnd: Point {
            TextEditBuffer.end(of: removed, from: start)
        }
    }

    // Applies a fresh operation: replaces its range, records it for undo.
    private func perform(_ operation: EditOperation) -> EditImpact {
        var applied = operation
        let impact = replace(from: operation.start, to: operation.removedEnd, with: operation.inserted)

        cursor = applied.end
        applied.cursorAfter = cursor
        selectionAnchor = nil

        undoStack.append(applied)
        redoStack = []
        return impact
    }

    // Selection-or-range delete as a recorded operation.
    private func delete(from start: Point, to end: Point) -> EditImpact {
        let impact = perform(EditOperation(
            start: start,
            removed: textIn(from: start, to: end),
            inserted: "",
            cursorBefore: cursor,
            anchorBefore: selectionAnchor
        ))

        coalescing = false
        return impact
    }

    // Splices replacement text over a range. Positions must be ordered and
    // in bounds (callers clamp). Does not touch cursor/selection/undo.
    private func replace(from start: Point, to end: Point, with replacement: String) -> EditImpact {
        let head = String(Array(lines[start.y]).prefix(start.x))
        let tail = String(Array(lines[end.y]).dropFirst(end.x))
        var newLines = Self.split(replacement)

        newLines[0] = head + newLines[0]
        newLines[newLines.count - 1] += tail

        let structural = end.y != start.y || newLines.count != 1
        lines.replaceSubrange(start.y...end.y, with: newLines)

        return structural ? .from(start.y) : .line(start.y)
    }

    // MARK: - Position helpers

    // Text between two ordered positions, newline-joined.
    private func textIn(from start: Point, to end: Point) -> String {
        guard start != end else {
            return ""
        }

        if start.y == end.y {
            let characters = Array(lines[start.y])
            return String(characters[start.x..<end.x])
        }

        var parts = [String(Array(lines[start.y]).dropFirst(start.x))]

        for line in (start.y + 1)..<end.y {
            parts.append(lines[line])
        }

        parts.append(String(Array(lines[end.y]).prefix(end.x)))
        return parts.joined(separator: "\n")
    }

    // Where `text` ends when placed at `start`. Pure (nonisolated: the
    // nested EditOperation struct computes its endpoints outside the actor).
    private nonisolated static func end(of text: String, from start: Point) -> Point {
        let parts = split(text)

        if parts.count == 1 {
            return Point(x: start.x + parts[0].count, y: start.y)
        }

        return Point(x: parts[parts.count - 1].count, y: start.y + parts.count - 1)
    }

    private var endOfDocument: Point {
        Point(x: lines[lines.count - 1].count, y: lines.count - 1)
    }

    private func clamp(_ position: Point) -> Point {
        let line = min(max(0, position.y), lines.count - 1)
        let column = min(max(0, position.x), lines[line].count)
        return Point(x: column, y: line)
    }

    private func isOrdered(_ a: Point, _ b: Point) -> Bool {
        a.y < b.y || (a.y == b.y && a.x <= b.x)
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }

    private nonisolated static func split(_ text: String) -> [String] {
        let parts = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        return parts.isEmpty ? [""] : parts
    }
}
