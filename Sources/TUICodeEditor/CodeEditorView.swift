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

    /// Numbers down the RIGHT edge, keyed by document line.
    ///
    /// For a SIDE-BY-SIDE diff, where the two halves each need their own
    /// numbering and putting them on opposite edges is what makes the pair
    /// readable. A unified diff needs only the gutter: each row comes from
    /// one file, and the gutter shows that file's number
    /// (``LineNumberBand/numberProvider``).
    ///
    /// Empty by default and then it costs nothing: no column is reserved, and
    /// an ordinary editor is exactly as wide as it was.
    public var trailingNumbers: [Int: Int] = [:] {
        didSet {
            if trailingNumbers != oldValue {
                setNeedsDisplay()
            }
        }
    }

    /// A stretch of one line on its own ground.
    public struct ColumnTint: Equatable, Sendable {
        /// Columns covered, in document columns.
        public var columns: Range<Int>

        /// The ground under them.
        public var color: TerminalColor

        /// Creates a tint.
        public init(columns: Range<Int>, color: TerminalColor) {
            self.columns = columns
            self.color = color
        }
    }

    /// Tints for PARTS of a line, keyed by document line.
    ///
    /// What makes a side-by-side diff possible in a text editor: a changed
    /// row holds both versions — old text, a gap, new text — and the halves
    /// need different grounds. Whole-line ``lineTints`` cannot say that, and
    /// two editors side by side cannot scroll as one without a synchroniser
    /// that drifts.
    ///
    /// Applied over ``lineTints``, so a line can have a ground and then have
    /// parts of it overruled.
    public var columnTints: [Int: [ColumnTint]] = [:] {
        didSet {
            if columnTints != oldValue {
                setNeedsDisplay()
            }
        }
    }

    /// Horizontal scrolling handled by someone else.
    ///
    /// A side-by-side diff composes each row to FIT the width — two columns
    /// and a gap — so scrolling the row sideways would slide the right column
    /// across the divider and out of its own gutter. What has to scroll is
    /// the text INSIDE each column, which only the thing that composed the
    /// row can do. Setting this hands the horizontal axis over: the view
    /// reports this span, and offsets go to
    /// ``onSubstituteHorizontalScroll`` instead of moving the text.
    public var substituteHorizontalSpan: ScrollSpan? {
        didSet {
            setNeedsDisplay()
        }
    }

    /// Receives horizontal offsets while ``substituteHorizontalSpan`` is set.
    public var onSubstituteHorizontalScroll: (Int) -> Void = { _ in }

    /// Background tint per document line — the inline diff's colouring.
    ///
    /// The editor keeps drawing everything it always draws (syntax, the
    /// gutter, folds, the caret); a tinted line just gets a different ground
    /// under all of it. That is what lets a diff be shown in the editor the
    /// file is already open in rather than in a window of its own: unchanged
    /// code stays exactly as it looked, and the changed stretches read as
    /// bands because their background changed, not their text.
    public var lineTints: [Int: TerminalColor] = [:] {
        didSet {
            if lineTints != oldValue {
                setNeedsDisplay()
            }
        }
    }

    /// Called after every change, with the full text.
    public var onChanged: (String) -> Void = { _ in }

    /// Called when the caret moves.
    public var onCursorMoved: (TextPosition) -> Void = { _ in }

    /// The clipboard cut/copy/paste use.
    ///
    /// **Defaults to the app's**, found through the window, rather than
    /// staying nil until a host remembers to wire it. It stayed nil in
    /// OmegaCLIDE for the editor's whole life, which is why ^C/^X/^V there did
    /// nothing at all: the keys were bound, the methods were written and
    /// tested, and every one of them returned early on a nil pasteboard. An
    /// opt-in that nobody opts into is a feature that does not exist.
    ///
    /// Assign to override — a host wanting a private clipboard for one view
    /// still can.
    public var pasteboard: Pasteboard?

    // The injected one, or the app's — the same shape `SyntaxTextView` has
    // had all along. This editor simply never adopted it.
    private var resolvedPasteboard: Pasteboard? {
        pasteboard ?? owningWindow?.app?.pasteboard
    }

    /// Whether the view draws its own scrollbars (off when a window border
    /// hosts them).
    // In-flight thumb drags: the pointer's offset within the thumb at
    // the grab, so the thumb does not jump under the cursor.
    var verticalBarGrab: Int?
    var horizontalBarGrab: Int?

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

        resolvedPasteboard?.copy(selected)
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
        guard let text = resolvedPasteboard?.string, !text.isEmpty else {
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

    /// The lines the selection touches, whole.
    ///
    /// A selection that ends at column 0 does NOT include that last line: a
    /// drag from one line to the start of the next has selected one line, and
    /// treating it as two would comment out a line nobody highlighted.
    public var selectedLineRange: Range<Int> {
        let selection = engine.selection
        let start = min(selection.start.line, selection.end.line)
        var end = max(selection.start.line, selection.end.line)

        if end > start, selection.end.column == 0, selection.end.line == end {
            end -= 1
        }

        return start..<(end + 1)
    }

    /// Selects a range of text.
    ///
    /// - Parameters:
    ///   - anchor: Where the selection started.
    ///   - head: Where it ended.
    public func select(from anchor: TextPosition, to head: TextPosition) {
        perform(.select(TextSelection(anchor: anchor, head: head)))
    }

    /// Replaces whole lines, as one undoable edit.
    ///
    /// One edit rather than a loop of them, so a single undo puts the file
    /// back — and so the caret does not travel while it happens. The
    /// selection is restored over the same lines afterwards, because the next
    /// thing anybody does after commenting a block is comment it back.
    ///
    /// - Parameters:
    ///   - range: Lines to replace.
    ///   - lines: What to put there.
    public func replaceLines(_ range: Range<Int>, with lines: [String]) {
        let clamped = range.clamped(to: 0..<engine.document.lineCount)

        guard !clamped.isEmpty, !lines.isEmpty else {
            return
        }

        let last = clamped.upperBound - 1

        perform(.select(TextSelection(
            anchor: TextPosition(line: clamped.lowerBound, column: 0),
            head: TextPosition(line: last, column: engineDocument.line(at: last).count)
        )))
        perform(.insertText(lines.joined(separator: "\n")))

        // Back over the same lines, END TO END rather than at the column the
        // caret happened to be in. A selection dragged to the start of a line
        // excludes that line — correctly — and restoring a column-0 head
        // would make the NEXT whole-line command exclude one more, so a
        // repeated command ate a line each time.
        let newLast = clamped.lowerBound + lines.count - 1
        perform(.select(TextSelection(
            anchor: TextPosition(line: clamped.lowerBound, column: 0),
            head: TextPosition(line: newLast, column: engineDocument.line(at: newLast).count)
        )))
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
    ///
    /// Public because anything composing text to FIT the editor — a
    /// side-by-side diff working out its column width — has to know how much
    /// of the width the gutter already took.
    public var gutterWidth: Int {
        gutterColumns
    }

    /// Total gutter width including the separator column.
    var gutterColumns: Int {
        gutterBands.reduce(0) { $0 + $1.width } + 1   // +1 for the separator
    }

    /// Columns reserved on the right for ``trailingNumbers`` (0 when unused).
    var trailingColumns: Int {
        guard let widest = trailingNumbers.values.max() else {
            return 0
        }

        // A separator, a space, the digits, a space — the mirror of the left
        // gutter, so the column reads as a gutter rather than as text that
        // drifted to the edge.
        return String(widest).count + 3
    }

    private var visibleLineCount: Int {
        max(1, bounds.size.height - (showsOwnScrollbars && drawsHorizontalBar ? 1 : 0))
    }

    /// Columns actually available for text.
    ///
    /// Everything the gutters and the scrollbars have taken, already
    /// subtracted. Public because anything composing text to FIT the editor —
    /// a side-by-side diff working out its column width — has to compose to
    /// THIS, and assembling it from the parts is how a caller ends up a few
    /// columns wide and clipping its own content off the right-hand edge with
    /// no way to scroll to it: the row is too wide, and scrolling inside a
    /// column cannot reveal what the row itself cut.
    public var textAreaWidth: Int {
        textWidth
    }

    private var textWidth: Int {
        max(1, bounds.size.width - gutterColumns - trailingColumns - (showsOwnScrollbars && drawsVerticalBar ? 1 : 0))
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

        // A substituted axis decides for itself. Asking the TEXT how wide it
        // is gets the wrong answer for content composed to FIT the width — a
        // side-by-side diff's rows are exactly as wide as the editor by
        // construction, so the bar would never appear no matter how long the
        // lines inside its columns are.
        if let substitute = substituteHorizontalSpan {
            return substitute.content > substitute.viewport
        }

        return longestVisibleLine > max(1, bounds.size.width - gutterColumns - trailingColumns)
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
        // Bars first: a press on the last column is a scrollbar press, not a
        // click at the end of that line.
        if showsOwnScrollbars, pressOwnScrollbar(mouse) {
            return true
        }

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

            // Stashed before the caret collapses it: the press of a
            // double-click arrives first and clears the selection, so the
            // ladder would forget which rung it was on and re-select the word
            // for ever. This is the one thing worth remembering — and it is
            // refreshed by every press, so it cannot go stale.
            selectionBeforeClick = engine.selection
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
                escalateSelection(at: position)

            case 3:
                perform(.select(lineSelection(at: position.line)))

            default:
                return false   // the press already placed the caret
            }

            return true

        default:
            return false
        }
    }

    // MARK: - Selection

    // What was selected when this click sequence began.
    private var selectionBeforeClick: TextSelection?

    /// The whole of one line, as a selection.
    private func lineSelection(at line: Int) -> TextSelection {
        TextSelection(
            anchor: TextPosition(line: line, column: 0),
            head: TextPosition(line: line, column: engine.document.line(at: line).count)
        )
    }

    /// Everything, as a selection.
    private var everything: TextSelection {
        let last = max(0, engine.document.lineCount - 1)

        return TextSelection(
            anchor: TextPosition(line: 0, column: 0),
            head: TextPosition(line: last, column: engine.document.line(at: last).count)
        )
    }

    // Word, then line, then everything, then nothing — the Mac ladder.
    private func escalateSelection(at position: TextPosition) {
        let word = WordBoundaries.word(around: position, in: engine.document)
        let line = lineSelection(at: position.line)
        let all = everything
        let current = selectionBeforeClick ?? engine.selection

        // Compared by START and END rather than by anchor and head: a
        // selection dragged right to left holds the same text as one dragged
        // left to right, and the ladder is about what is selected.
        func covers(_ other: TextSelection) -> Bool {
            current.start == other.start && current.end == other.end
        }

        switch SelectionEscalation.nextScope(
            isWord: covers(word),
            isLine: covers(line),
            isAll: covers(all)
        ) {
        case .word:
            perform(.select(word))

        case .line:
            perform(.select(line))

        case .all:
            perform(.select(all))

        case .none:
            perform(.select(TextSelection(caret: position)))
        }
    }

    // MARK: - BorderScrollable

    /// Vertical scroll state for a border-embedded bar.
    public var verticalScrollSpan: ScrollSpan? {
        ScrollSpan(offset: topLine, viewport: bounds.size.height, content: max(1, engine.document.lineCount))
    }

    /// Horizontal scroll state for a border-embedded bar.
    public var horizontalScrollSpan: ScrollSpan? {
        if let substitute = substituteHorizontalSpan {
            return substitute
        }

        return ScrollSpan(
            offset: leftColumn,
            viewport: max(1, bounds.size.width - gutterColumns - trailingColumns),
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
        guard substituteHorizontalSpan == nil else {
            onSubstituteHorizontalScroll(max(0, offset))
            return
        }

        leftColumn = max(0, offset)
        setNeedsDisplay()
    }
}

// MARK: - Own scrollbars

extension CodeEditorView {
    /// The vertical run for this view's OWN bar, when it draws one.
    ///
    /// Same `ScrollbarRun` the border-embedded bars use, so the interior pair
    /// gets arrows, paging and thumb drags for free. They had none of the
    /// three: the two implementations had drifted, and nobody noticed while
    /// the border always carried the bars — a slide-out handing them back is
    /// what surfaced it.
    func ownVerticalRun() -> ScrollbarRun? {
        guard let span = verticalScrollSpan, bounds.size.height > 0 else {
            return nil
        }

        // Stop above the horizontal bar: the corner cell belongs to one of
        // them, and a `▾` sitting in the other bar's track reads as a glitch.
        let height = max(0, bounds.size.height - (drawsHorizontalBar ? 1 : 0))

        return ScrollbarRun(start: 0, length: height, span: span)
    }

    /// The horizontal run for this view's own bar.
    ///
    /// Spans the WHOLE view, not from the gutter rightward. Bobby: *"the
    /// bottom bar is well inside the editor — it is limiting its size to the
    /// gutter, not the view."* The gutter does not scroll horizontally, which
    /// is what made insetting look defensible, but the bar is chrome for the
    /// view and every other bar in the app runs its full edge.
    func ownHorizontalRun() -> ScrollbarRun? {
        guard let span = horizontalScrollSpan, bounds.size.width > 0 else {
            return nil
        }

        let width = max(0, bounds.size.width - (drawsVerticalBar ? 1 : 0))

        return ScrollbarRun(start: 0, length: width, span: span)
    }

    /// Handles a press or drag on this view's own bars.
    ///
    /// - Returns: Whether the event belonged to a bar.
    func pressOwnScrollbar(_ mouse: MouseInput) -> Bool {
        switch mouse.action {
        case .press where mouse.button == .left:
            if drawsVerticalBar, mouse.position.x == bounds.size.width - 1, let run = ownVerticalRun() {
                setScrollOffset(vertical: run.offset(forPress: mouse.position.y, grab: &verticalBarGrab))
                return true
            }

            if drawsHorizontalBar, mouse.position.y == bounds.size.height - 1, let run = ownHorizontalRun() {
                setScrollOffset(horizontal: run.offset(forPress: mouse.position.x, grab: &horizontalBarGrab))
                return true
            }

            return false

        case .drag:
            // The grab offset is what stops the thumb jumping to centre
            // itself under the pointer on the first drag event.
            if let grab = verticalBarGrab, let run = ownVerticalRun() {
                setScrollOffset(vertical: run.offset(forThumbStart: mouse.position.y - grab))
                return true
            }

            if let grab = horizontalBarGrab, let run = ownHorizontalRun() {
                setScrollOffset(horizontal: run.offset(forThumbStart: mouse.position.x - grab))
                return true
            }

            return false

        case .release:
            let wasDragging = verticalBarGrab != nil || horizontalBarGrab != nil
            verticalBarGrab = nil
            horizontalBarGrab = nil
            return wasDragging

        default:
            return false
        }
    }
}

extension CodeEditorView: ClipboardEditing {
    public func clipboardCopy() {
        _ = copySelection()
    }

    public func clipboardCut() {
        cutSelection()
    }

    public func clipboardPaste() {
        paste()
    }
}
