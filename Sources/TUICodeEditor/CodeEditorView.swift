import CodeEditorCore
import TUIKit

/// A source-code editor: stateful syntax colouring, a banded gutter, and the
/// editing behaviours people expect from a real editor.
///
/// ```text
///  ● ▌  12 │ func draw(_ painter: Painter) {
///    ▌  13 │     // a comment that stays a comment
///  ⚠     14 │     let x = """
///       15 │         still a string
/// ```
///
/// Everything about *what* an edit means lives in `CodeEditorCore` — this
/// class turns keys and clicks into ``EditorCommand``s, and paints what the
/// engine reports. That split is why the behaviour is testable without a
/// terminal and why a GUI editor could reuse the same brain.
@MainActor
public final class CodeEditorView: TUIView, BorderScrollable {
    // MARK: - State

    private var engine: CodeEditorEngine
    private var tokens: TokenStore

    /// Scope colours. Swap for a different palette per theme.
    public var syntaxTheme: EditorTheme = .terminalDefault {
        didSet { setNeedsDisplay() }
    }

    /// The gutter's bands, left to right. Reassign to change the layout.
    public var gutterBands: [any GutterBand] = [] {
        didSet { setNeedsDisplay() }
    }

    /// Line numbers.
    public let lineNumbers = LineNumberBand()

    /// Git change ribbon; populate ``ChangeRibbonBand/changes``.
    public let changeRibbon = ChangeRibbonBand()

    /// Diagnostic glyphs.
    public let diagnosticsBand = DiagnosticBand()

    /// Breakpoint dots.
    public let breakpoints = BreakpointBand()

    /// Fold controls.
    public let foldBand = FoldBand()

    /// Whether typing is allowed.
    public var isEditable = true

    /// Called after every change, with the full text.
    public var onChanged: (String) -> Void = { _ in }

    /// Called when the caret moves.
    public var onCursorMoved: (TextPosition) -> Void = { _ in }

    /// System clipboard, when the host provides one.
    public var pasteboard: Pasteboard?

    /// Whether the view draws its own scrollbars (off when a window border
    /// hosts them).
    public var showsOwnScrollbars = true {
        didSet {
            if showsOwnScrollbars != oldValue {
                setNeedsDisplay()
            }
        }
    }

    // Viewport. Internal so the rendering extension can read them.
    var topLine = 0
    var leftColumn = 0

    /// The document, for the rendering extension.
    var engineDocument: TextDocument { engine.document }

    /// The selection, for the rendering extension.
    var engineSelection: TextSelection { engine.selection }

    /// The token cache, for the rendering extension.
    var tokenStore: TokenStore { tokens }

    /// Creates an editor.
    ///
    /// - Parameters:
    ///   - text: Initial contents.
    ///   - language: Syntax identifier (`"swift"`, `"python"`, …).
    public init(text: String = "", language: String = "text") {
        engine = CodeEditorEngine(text: text, language: language)
        tokens = TokenStore(language: language)
        super.init(frame: .zero)

        tokens.rebuildAll(document: engine.document)
        gutterBands = [breakpoints, changeRibbon, diagnosticsBand, foldBand, lineNumbers]
        foldBand.onToggle = { [weak self] line in
            self?.toggleFold(at: line)
        }
        refreshFolds()
        refreshGutterState()
    }

    // MARK: - Content

    /// The text being edited.
    public var text: String {
        engine.text
    }

    /// Replaces the text without recording undo — a file load.
    public func setText(_ newText: String) {
        engine.setText(newText)
        tokens.rebuildAll(document: engine.document)
        topLine = 0
        leftColumn = 0
        refreshGutterState()
        setNeedsDisplay()
    }

    /// The syntax language.
    public var language: String {
        get { engine.language }
        set {
            engine.language = newValue
            tokens.setLanguage(newValue, document: engine.document)
            setNeedsDisplay()
        }
    }

    /// Editing behaviours (auto-indent, pairs, tab-indent).
    public var behavior: EditorBehaviorPreferences {
        get { engine.behavior }
        set { engine.behavior = newValue }
    }

    /// Number of lines.
    public var lineCount: Int {
        engine.document.lineCount
    }

    /// The caret, as (column, line) — matching the old editor's shape so the
    /// IDE's status strip needs no changes.
    public var cursorPosition: Point {
        Point(x: engine.selection.head.column, y: engine.selection.head.line)
    }

    /// Whether anything is selected.
    public var hasSelection: Bool {
        !engine.selection.isEmpty
    }

    /// The selected text, if any.
    public var selectedText: String? {
        engine.selectedText
    }

    /// Whether undo/redo would do anything.
    public var canUndo: Bool { engine.canUndo }
    /// - SeeAlso: ``canUndo``
    public var canRedo: Bool { engine.canRedo }

    /// Diagnostics to show in the gutter and underline in the text.
    public var diagnostics: DiagnosticSet {
        get { diagnosticsBand.diagnostics }
        set {
            diagnosticsBand.diagnostics = newValue
            setNeedsDisplay()
        }
    }

    /// Per-line git change markers.
    public var lineChanges: [Int: EditorLineChangeKind] {
        get { changeRibbon.changes }
        set {
            changeRibbon.changes = newValue
            setNeedsDisplay()
        }
    }

    // MARK: - Commands

    /// Applies an editor command and refreshes everything that depends on it.
    public func perform(_ command: EditorCommand) {
        let before = engine.document
        let caretBefore = engine.selection.head

        engine.perform(command)

        if engine.document.revision != before.revision {
            let delta = engine.document.lineCount - before.lineCount
            tokens.update(
                document: engine.document,
                changedFrom: min(caretBefore.line, engine.selection.head.line),
                lineCountDelta: delta
            )
            onChanged(engine.text)
            refreshFolds()
        }

        finishInteraction()
    }

    /// Undoes the last edit.
    public func undo() {
        engine.undo()
        tokens.rebuildAll(document: engine.document)
        onChanged(engine.text)
        finishInteraction()
    }

    /// Redoes the last undone edit.
    public func redo() {
        engine.redo()
        tokens.rebuildAll(document: engine.document)
        onChanged(engine.text)
        finishInteraction()
    }

    /// Selects everything.
    public func selectAll() {
        perform(.selectAll)
    }

    /// Copies the selection to the clipboard.
    @discardableResult
    public func copySelection() -> Bool {
        guard let selected = engine.selectedText else {
            return false
        }

        pasteboard?.copy(selected)
        return true
    }

    /// Cuts the selection.
    public func cutSelection() {
        guard copySelection() else {
            return
        }

        perform(.deleteBackward)
    }

    /// Pastes the clipboard at the caret.
    public func paste() {
        guard let text = pasteboard?.string, !text.isEmpty else {
            return
        }

        perform(.insertText(text))
    }

    // MARK: - Find

    private var finder = FindEngine()

    /// How many matches the last search found.
    public var findMatchCount: Int {
        finder.matches.count
    }

    /// Ranges to highlight, for a host that wants to draw them.
    public var findMatches: [FindEngine.Match] {
        finder.matches
    }

    /// Searches the buffer and selects the first match.
    ///
    /// - Returns: How many matches there are.
    @discardableResult
    public func findMatches(of query: String, caseSensitive: Bool = false) -> Int {
        let count = finder.find(query, in: engine.document, caseSensitive: caseSensitive)

        if let match = finder.current {
            perform(.select(match.selection))
        }

        setNeedsDisplay()
        return count
    }

    /// Forgets the current search.
    public func clearFind() {
        finder.clear()
        setNeedsDisplay()
    }

    /// Selects the next match, wrapping.
    @discardableResult
    public func findNext() -> Bool {
        guard let match = finder.next() else {
            return false
        }

        perform(.select(match.selection))
        return true
    }

    /// Selects the previous match, wrapping.
    @discardableResult
    public func findPrevious() -> Bool {
        guard let match = finder.previous() else {
            return false
        }

        perform(.select(match.selection))
        return true
    }

    /// Replaces the current match and re-runs the search.
    @discardableResult
    public func replaceCurrentMatch(with replacement: String) -> Bool {
        guard let match = finder.current else {
            return false
        }

        perform(.select(match.selection))
        perform(.insertText(replacement))
        findMatches(of: finder.query, caseSensitive: finder.isCaseSensitive)
        return true
    }

    /// Replaces every match.
    ///
    /// - Returns: How many were replaced.
    @discardableResult
    public func replaceAllMatches(with replacement: String) -> Int {
        let operations = finder.replaceAllOperations(with: replacement)

        guard !operations.isEmpty else {
            return 0
        }

        // Back to front, so each replacement leaves the earlier ranges valid.
        for operation in operations {
            engine.apply(operation)
        }

        tokens.rebuildAll(document: engine.document)
        onChanged(engine.text)
        finder.clear()
        finishInteraction()
        return operations.count
    }

    /// Scrolls a line into view and puts the caret on it.
    public func scrollTo(line: Int, column: Int = 0) {
        perform(.select(TextSelection(caret: TextPosition(line: line, column: column))))
    }

    // MARK: - Interaction bookkeeping

    private func finishInteraction() {
        // An edit or a jump inside a collapsed region must open it, or the
        // user types into text they cannot see.
        _ = foldBand.map.reveal(line: engine.selection.head.line)
        refreshGutterState()
        scrollCaretIntoView()
        onCursorMoved(engine.selection.head)
        setNeedsDisplay()
    }

    /// Collapses or expands the region starting at a line.
    public func toggleFold(at line: Int) {
        guard foldBand.map.toggle(at: line) else {
            return
        }

        scrollCaretIntoView()
        setNeedsDisplay()
    }

    /// Collapses every foldable region.
    public func foldAll() {
        foldBand.map.foldAll()
        setNeedsDisplay()
    }

    /// Expands everything.
    public func unfoldAll() {
        foldBand.map.unfoldAll()
        setNeedsDisplay()
    }

    /// The document lines currently on screen, folds applied.
    var visibleDocumentLines: [Int] {
        foldBand.map.visibleLines(in: engine.document.lineCount)
    }

    // Re-detects regions after an edit, and reveals whatever the caret is
    // inside so typing never happens invisibly.
    private func refreshFolds() {
        foldBand.map.setRegions(FoldRegionDetector.regions(in: engine.document, tokens: tokens))
        _ = foldBand.map.reveal(line: engine.selection.head.line)
    }

    private func refreshGutterState() {
        lineNumbers.lineCount = engine.document.lineCount
        lineNumbers.caretLine = engine.selection.head.line
    }

    /// Total gutter width including the separator column.
    var gutterColumns: Int {
        gutterBands.reduce(0) { $0 + $1.width } + 1   // +1 for the separator
    }

    private var visibleLineCount: Int {
        max(1, bounds.size.height - (showsOwnScrollbars && drawsHorizontalBar ? 1 : 0))
    }

    private var textWidth: Int {
        max(1, bounds.size.width - gutterColumns - (showsOwnScrollbars && drawsVerticalBar ? 1 : 0))
    }

    /// Whether the view paints its own vertical bar.
    var drawsVerticalBar: Bool {
        showsOwnScrollbars && engine.document.lineCount > bounds.size.height
    }

    /// Whether the view paints its own horizontal bar.
    var drawsHorizontalBar: Bool {
        guard showsOwnScrollbars else {
            return false
        }

        return longestVisibleLine > max(1, bounds.size.width - gutterColumns)
    }

    /// Longest line currently on screen — the horizontal scroll extent.
    var longestVisibleLine: Int {
        let last = min(engine.document.lineCount, topLine + bounds.size.height)

        guard topLine < last else {
            return 0
        }

        return (topLine..<last).reduce(0) { max($0, engine.document.line(at: $1).count) }
    }

    private func scrollCaretIntoView() {
        let head = engine.selection.head
        let height = visibleLineCount

        if head.line < topLine {
            topLine = head.line
        } else if head.line >= topLine + height {
            topLine = head.line - height + 1
        }

        topLine = max(0, min(topLine, max(0, engine.document.lineCount - 1)))

        let width = textWidth

        if head.column < leftColumn {
            leftColumn = head.column
        } else if head.column >= leftColumn + width {
            leftColumn = head.column - width + 1
        }

        leftColumn = max(0, leftColumn)
    }

// MARK: - Drawing, input, scrolling
//
// These must live in the class body — Swift forbids overriding in an
// extension — but each one delegates to a helper next door, so the class
// stays a table of contents rather than a wall of painting code.

    /// Paints the gutter, the text, and any interior scrollbars.
    public override func draw(_ painter: Painter) {
        let theme = effectiveTheme
        painter.fill(bounds, with: TerminalCell(character: " ", style: theme.base))

        // Rows map to VISIBLE lines: a collapsed region's body simply is not
        // in the list, so folding needs no special case anywhere below.
        let visible = visibleDocumentLines
        let first = visible.firstIndex(where: { $0 >= topLine }) ?? visible.count

        for row in 0..<bounds.size.height {
            let index = first + row

            guard index < visible.count else {
                break
            }

            let line = visible[index]
            paintGutter(painter, line: line, row: row, theme: theme)
            paintLine(painter, line: line, row: row, theme: theme)
        }

        if showsOwnScrollbars {
            paintScrollbars(painter, theme: theme)
        }
    }

    /// The editor takes focus.
    public override var acceptsFirstResponder: Bool {
        true
    }

    /// Turns a key into an ``EditorCommand``.
    ///
    /// The entire keyboard model in one place, and the only part of editing
    /// that knows what a key is.
    public override func keyDown(_ key: KeyInput) -> Bool {
        let shift = key.modifiers.contains(.shift)
        let word = key.modifiers.contains(.alt)

        switch key.key {
        case .left:
            perform(.moveCaret(word ? .wordLeft : .characterLeft, extendingSelection: shift))
            return true

        case .right:
            perform(.moveCaret(word ? .wordRight : .characterRight, extendingSelection: shift))
            return true

        case .up:
            perform(.moveCaret(.lineUp, extendingSelection: shift))
            return true

        case .down:
            perform(.moveCaret(.lineDown, extendingSelection: shift))
            return true

        case .home:
            perform(.moveCaret(key.modifiers.contains(.control) ? .documentStart : .lineStart, extendingSelection: shift))
            return true

        case .end:
            perform(.moveCaret(key.modifiers.contains(.control) ? .documentEnd : .lineEnd, extendingSelection: shift))
            return true

        case .pageUp:
            perform(.moveCaret(.pageUp(bounds.size.height), extendingSelection: shift))
            return true

        case .pageDown:
            perform(.moveCaret(.pageDown(bounds.size.height), extendingSelection: shift))
            return true

        default:
            break
        }

        guard isEditable else {
            return false
        }

        switch key.key {
        case .enter:
            perform(.insertNewline)
            return true

        case .backspace:
            perform(word ? .deleteWordBackward : .deleteBackward)
            return true

        case .delete:
            perform(word ? .deleteWordForward : .deleteForward)
            return true

        case .tab:
            // Tab indents a selection and inserts a unit without one, which
            // is what makes it usable for both jobs.
            if behavior.indentsSelectionWithTab, hasSelection {
                perform(shift ? .outdentSelection : .indentSelection)
            } else if shift {
                perform(.outdentSelection)
            } else {
                perform(.insertText(behavior.indentUnit))
            }

            return true

        case .character(let character):
            if key.modifiers.contains(.control) {
                return handleControlChord(character)
            }

            guard key.modifiers.isEmpty || key.modifiers == .shift else {
                return false
            }

            perform(.insertText(String(character)))
            return true

        default:
            return false
        }
    }

    // ^C/^X/^V/^Z/^Y/^A — the chords the IDE does not claim first.
    private func handleControlChord(_ character: Character) -> Bool {
        switch character {
        case "c":
            return copySelection()

        case "x":
            cutSelection()
            return true

        case "v":
            paste()
            return true

        case "z":
            undo()
            return true

        case "y":
            redo()
            return true

        case "a":
            selectAll()
            return true

        default:
            return false
        }
    }

    /// Click to place the caret, drag to select, double/triple click to take
    /// a word or a line, wheel to scroll.
    public override func mouseEvent(_ mouse: MouseInput) -> Bool {
        switch mouse.action {
        case .scrollUp:
            setScrollOffset(vertical: topLine - 3)
            return true

        case .scrollDown:
            setScrollOffset(vertical: topLine + 3)
            return true

        case .press:
            owningWindow?.makeFirstResponder(self)

            if mouse.position.x < gutterColumns {
                return handleGutterClick(at: mouse.position)
            }

            perform(.select(TextSelection(caret: position(at: mouse.position))))
            return true

        case .drag:
            guard mouse.position.x >= gutterColumns else {
                return false
            }

            perform(.select(TextSelection(anchor: engine.selection.anchor, head: position(at: mouse.position))))
            return true

        case .click:
            guard mouse.position.x >= gutterColumns else {
                return false
            }

            let position = position(at: mouse.position)

            // The debounced click event is the only one that can tell a
            // double from a single, so word/line selection lives here.
            switch mouse.clickCount {
            case 2:
                perform(.select(WordBoundaries.word(around: position, in: engine.document)))

            case 3:
                let length = engine.document.line(at: position.line).count
                perform(.select(TextSelection(
                    anchor: TextPosition(line: position.line, column: 0),
                    head: TextPosition(line: position.line, column: length)
                )))

            default:
                return false   // the press already placed the caret
            }

            return true

        default:
            return false
        }
    }

    // MARK: - BorderScrollable

    /// Vertical scroll state for a border-embedded bar.
    public var verticalScrollSpan: ScrollSpan? {
        ScrollSpan(offset: topLine, viewport: bounds.size.height, content: max(1, engine.document.lineCount))
    }

    /// Horizontal scroll state for a border-embedded bar.
    public var horizontalScrollSpan: ScrollSpan? {
        ScrollSpan(
            offset: leftColumn,
            viewport: max(1, bounds.size.width - gutterColumns),
            content: max(1, longestVisibleLine)
        )
    }

    /// Scrolls to a first-visible line.
    public func setScrollOffset(vertical offset: Int) {
        topLine = max(0, min(offset, max(0, engine.document.lineCount - 1)))
        setNeedsDisplay()
    }

    /// Scrolls to a first-visible column.
    public func setScrollOffset(horizontal offset: Int) {
        leftColumn = max(0, offset)
        setNeedsDisplay()
    }
}
