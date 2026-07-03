import RichSwift

/// Editable multi-line code view with syntax highlighting.
///
/// ```text
///    1 │ func greet() {
///    2 │     print("hi")      ← RichSwift Syntax colors keywords,
///    3 │ }                      strings, numbers, and comments
/// ```
///
/// Editing is line-oriented: arrows/Home/End/PageUp/PageDown move the
/// cursor, Return splits a line, Backspace/Delete edit and join lines, Tab
/// inserts spaces (Shift+Tab still moves focus away), and printable
/// characters insert at the cursor. The viewport follows the cursor on both
/// axes; the wheel scrolls vertically. Clicking places the cursor.
///
/// Highlighting is per line through RichSwift `Syntax` (see the RichSwift
/// integration section in PLAN.md) with a per-line cache, so editing one
/// line re-highlights only that line.
///
/// ```swift
/// let editor = SyntaxTextView(text: source, language: "swift")
/// editor.onChanged = { source in store(source) }
/// ```
@MainActor
public final class SyntaxTextView: View {
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

    /// Called after every edit with the full text.
    public var onChanged: (String) -> Void = { _ in }

    // Line storage; always at least one line.
    private var lines: [String]

    // Cursor as (column, line). Column is in characters.
    private var cursor = Point.zero

    // First visible (column, line).
    private var offset = Point.zero

    // Highlighted runs by line index.
    private var highlightCache: [Int: [StyledRun]] = [:]

    /// Creates an editor.
    ///
    /// - Parameters:
    ///   - text: Initial contents.
    ///   - language: Language identifier for highlighting.
    public init(text: String = "", language: String = "swift") {
        self.lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        self.language = language

        if lines.isEmpty {
            lines = [""]
        }

        super.init(frame: .zero)
    }

    /// Full text (lines joined with newlines).
    public var text: String {
        lines.joined(separator: "\n")
    }

    /// Number of lines.
    public var lineCount: Int {
        lines.count
    }

    /// Cursor position as (column, line).
    public var cursorPosition: Point {
        cursor
    }

    /// Replaces the text programmatically (silent; cursor moves to the top).
    ///
    /// - Parameter newText: New contents.
    public func setText(_ newText: String) {
        lines = newText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        if lines.isEmpty {
            lines = [""]
        }

        cursor = .zero
        offset = .zero
        highlightCache.removeAll()
        setNeedsDisplay()
    }

    /// Editors take keyboard focus.
    public override var acceptsFirstResponder: Bool {
        true
    }

    /// Draws the gutter and the visible, highlighted slice of lines.
    public override func draw(_ painter: Painter) {
        let height = bounds.size.height
        let width = bounds.size.width

        guard height > 0, width > 0 else {
            return
        }

        let gutter = gutterWidth
        let contentWidth = max(0, width - gutter)

        for viewportRow in 0..<height {
            let lineIndex = offset.y + viewportRow

            guard lineIndex < lines.count else {
                break
            }

            if gutter > 0 {
                let number = String(lineIndex + 1)
                let padded = String(repeating: " ", count: max(0, gutter - 2 - number.count)) + number + " │"
                painter.write(padded, at: Point(x: 0, y: viewportRow), style: CellStyle(flags: .dim))
            }

            // Highlighted runs, sliced by the horizontal offset.
            var column = -offset.x

            for run in highlightedRuns(for: lineIndex) {
                for character in run.text {
                    if column >= 0, column < contentWidth {
                        painter.set(
                            TerminalCell(character: character, style: run.style),
                            at: Point(x: gutter + column, y: viewportRow)
                        )
                    }

                    column += 1
                }
            }
        }

        // Cursor cell inverts while focused.
        if isFirstResponder,
           cursor.y >= offset.y, cursor.y < offset.y + height,
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

    /// Movement and editing keys.
    public override func keyDown(_ key: KeyInput) -> Bool {
        guard key.modifiers.isEmpty else {
            return false
        }

        switch key.key {
        case .up:
            moveCursor(line: cursor.y - 1, column: cursor.x)
            return true

        case .down:
            moveCursor(line: cursor.y + 1, column: cursor.x)
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
            moveCursor(line: cursor.y - max(1, bounds.size.height - 1), column: cursor.x)
            return true

        case .pageDown:
            moveCursor(line: cursor.y + max(1, bounds.size.height - 1), column: cursor.x)
            return true

        case .enter:
            splitLine()
            return true

        case .backspace:
            deleteBackward()
            return true

        case .delete:
            deleteForward()
            return true

        case .tab:
            insert(String(repeating: " ", count: max(1, tabWidth)))
            return true

        case .character(let character):
            insert(String(character))
            return true

        default:
            return false
        }
    }

    /// Click places the cursor; the wheel scrolls.
    public override func mouseEvent(_ mouse: MouseInput) -> Bool {
        switch mouse.action {
        case .press where mouse.button == .left:
            let line = min(max(0, offset.y + mouse.position.y), lines.count - 1)
            let column = max(0, offset.x + mouse.position.x - gutterWidth)
            moveCursor(line: line, column: column)
            return true

        case .scrollUp:
            offset.y = max(0, offset.y - 1)
            setNeedsDisplay()
            return true

        case .scrollDown:
            offset.y = min(max(0, lines.count - bounds.size.height), offset.y + 1)
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
        replaceLine(cursor.y, with: line)
        cursor.x += string.count
        contentsChanged()
    }

    private func splitLine() {
        let line = lines[cursor.y]
        let split = line.index(line.startIndex, offsetBy: cursor.x)

        replaceLine(cursor.y, with: String(line[..<split]))
        lines.insert(String(line[split...]), at: cursor.y + 1)
        invalidateHighlights(from: cursor.y)

        cursor = Point(x: 0, y: cursor.y + 1)
        contentsChanged()
    }

    private func deleteBackward() {
        if cursor.x > 0 {
            var line = lines[cursor.y]
            let index = line.index(line.startIndex, offsetBy: cursor.x - 1)
            line.remove(at: index)
            replaceLine(cursor.y, with: line)
            cursor.x -= 1
            contentsChanged()
        } else if cursor.y > 0 {
            let removed = lines.remove(at: cursor.y)
            cursor = Point(x: lines[cursor.y - 1].count, y: cursor.y - 1)
            replaceLine(cursor.y, with: lines[cursor.y] + removed)
            invalidateHighlights(from: cursor.y)
            contentsChanged()
        }
    }

    private func deleteForward() {
        let line = lines[cursor.y]

        if cursor.x < line.count {
            var edited = line
            edited.remove(at: edited.index(edited.startIndex, offsetBy: cursor.x))
            replaceLine(cursor.y, with: edited)
            contentsChanged()
        } else if cursor.y < lines.count - 1 {
            let next = lines.remove(at: cursor.y + 1)
            replaceLine(cursor.y, with: line + next)
            invalidateHighlights(from: cursor.y)
            contentsChanged()
        }
    }

    private func replaceLine(_ index: Int, with newLine: String) {
        lines[index] = newLine
        highlightCache[index] = nil
    }

    // Line insertion/removal shifts every later cached line.
    private func invalidateHighlights(from index: Int) {
        highlightCache = highlightCache.filter { $0.key < index }
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

    private func ensureCursorVisible() {
        let height = bounds.size.height
        let contentWidth = max(1, bounds.size.width - gutterWidth)

        if height > 0 {
            if cursor.y < offset.y {
                offset.y = cursor.y
            }

            if cursor.y > offset.y + height - 1 {
                offset.y = cursor.y - height + 1
            }
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
