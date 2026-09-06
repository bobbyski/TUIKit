import Foundation

/// The log, on screen.
///
/// ```swift
/// let view = LogView()                     // watches LogStore.shared
/// TUILogger.shared.add(LogStore.shared)
/// ```
///
/// **A control, not a window.** Put it in a tab, a slide-out, a debug panel
/// or a window of its own — an app knows where its diagnostics belong and a
/// framework does not. (The terminal-native `AUILogView`.)
///
/// Top to bottom: a filter row (level, search, Follow, Clear, Copy), the
/// entries — only the visible rows are composed, so a two-thousand-entry
/// store costs a screenful per frame — and a status line. Each line is
/// time, level in its color, category, the message's first line, and
/// `File.swift:42` on the right when there is room.
@MainActor
public final class LogView: TUIView {
    /// Where the entries come from.
    public var store: LogStore {
        didSet {
            oldValue.removeHandler(watch)
            startWatching()
        }
    }

    /// The lowest level shown. Independent of what the logger *records* —
    /// this filters what has already been kept, so turning it down and back
    /// up shows the older entries again rather than losing them.
    public var level: LogLevel = .trace { didSet { refilter() } }

    /// Only show these categories, or nil for all of them.
    public var categories: Set<LogCategory>? { didSet { refilter() } }

    /// Only show entries whose message, category or origin contains this.
    public var searchText: String = "" { didSet { refilter() } }

    /// Whether the view scrolls to the newest entry as entries arrive.
    ///
    /// **On by default, and off the moment you scroll up or select.** A log
    /// that yanks itself back to the bottom while you are reading something
    /// is the reason people copy logs into a text editor.
    public var followsTail = true {
        didSet {
            follow.setChecked(followsTail)
            if followsTail { list.scrollToEnd() }
        }
    }

    /// Whether the filter row shows.
    public var showsFilterBar = true {
        didSet {
            filterControls.forEach { $0.isHidden = !showsFilterBar }
            setNeedsLayout()
            setNeedsDisplay()
        }
    }

    /// How many lines of a message a row may show, or nil for all of them.
    ///
    /// **One by default, because a log is a list.** A stack trace in every
    /// row makes the list unreadable, so the default is the first line and
    /// the rest is a double-click away. Turned up, the extra lines land in
    /// the MESSAGE column — which starts after the time, the level and the
    /// category — so a continued message hangs under the line it continues
    /// rather than starting back at the left edge with the timestamps.
    ///
    /// This is a cap on *displayed* lines, so a long single line wrapping to
    /// three counts as three. That is the question being answered: how tall
    /// may a row get.
    public var maximumLines: Int? = 1 {
        didSet {
            guard maximumLines != oldValue else { return }

            if let index = Self.lineChoices.firstIndex(of: maximumLines) {
                linesPicker.select(index)
            }

            list.maximumLines = maximumLines

            if followsTail { list.scrollToEnd() }
        }
    }

    /// The line counts the picker offers, `nil` being "no max".
    public static let lineChoices: [Int?] = [1, 2, 3, 4, 5, 10, 25, 100, nil]

    /// What a line-count choice is called in the picker.
    nonisolated static func lineChoiceName(_ lines: Int?) -> String {
        lines.map(String.init) ?? "No max"
    }

    /// The entries the user has opened with a double-click, by id.
    ///
    /// **Kept by id, not by row.** Rows move: entries arrive, the filter
    /// changes, the store drops its oldest. An index would open a different
    /// entry a second later. Ids that fall out of the store are forgotten
    /// with them, so the set cannot grow forever in a view left running.
    public internal(set) var expandedEntries: Set<UInt64> = [] {
        didSet {
            if expandedEntries != oldValue {
                list.expanded = expandedEntries
            }
        }
    }

    /// Called when a row is selected, with the entry.
    public var onSelect: ((LogEntry?) -> Void)?

    /// What is on screen, after filtering.
    public private(set) var visible: [LogEntry] = []

    /// The levels the picker offers: the standard ladder, plus any custom
    /// level that has turned up in the store, in severity order.
    public private(set) var levelChoices: [LogLevel] = LogLevel.standard

    /// How copied lines are laid out. The same formatter the console and a
    /// file use, so a line pasted into a bug report matches the one in the
    /// terminal.
    public var textFormatter: LogLineFormatter = .file

    private var all: [LogEntry] = []
    private var watch = LogDestinationToken(id: 0)

    private let levelPicker = PopUpButton(items: LogLevel.standard.map(\.name), selectedIndex: 0)
    private let linesPicker = PopUpButton(items: LogView.lineChoices.map(LogView.lineChoiceName), selectedIndex: 0)
    private let search = SearchField(placeholder: "Filter")
    private let follow = Checkbox("Follow", isChecked: true)
    private let clearButton = Button("Clear")
    private let copyButton = Button("Copy")
    private let list = LogListView()
    private let status = Label("")

    private var filterControls: [TUIView] {
        [levelPicker, linesPicker, search, follow, clearButton, copyButton]
    }

    /// Creates a log view.
    public init(store: LogStore = .shared) {
        self.store = store
        super.init(frame: .zero)

        levelPicker.onSelectionChanged = { [weak self] index in
            guard let self, index < levelChoices.count else { return }
            level = levelChoices[index]
        }

        linesPicker.onSelectionChanged = { [weak self] index in
            guard let self, Self.lineChoices.indices.contains(index) else { return }
            maximumLines = Self.lineChoices[index]
        }

        search.onSearch = { [weak self] text in self?.searchText = text }

        follow.onChange = { [weak self] isOn in self?.followsTail = isOn }

        clearButton.onActivate = { [weak self] in self?.store.clear() }
        copyButton.onActivate = { [weak self] in self?.copyToPasteboard() }

        list.onSelect = { [weak self] entry in
            guard let self else { return }

            // Selecting something means you are reading it, and a view that
            // scrolls away from what you just clicked is unusable.
            if entry != nil, followsTail {
                followsTail = false
            }

            onSelect?(entry)
        }

        list.onUserScrolledBack = { [weak self] in
            if self?.followsTail == true {
                self?.followsTail = false
            }
        }

        list.onToggleExpand = { [weak self] entry in
            self?.toggleExpanded(entry)
        }

        var secondary = CellStyle()
        secondary.flags.insert(.dim)
        status.style = secondary

        filterControls.forEach(addSubview)
        addSubview(list)
        addSubview(status)

        startWatching()
        reload()
    }

    deinit {
        // Without this the store keeps calling a handler that draws into a
        // view nobody can see — one leaked registration per appearance.
        store.removeHandler(watch)
    }

    /// A sensible debug-panel size; it stretches to whatever it is given.
    public override var intrinsicContentSize: Size? {
        Size(width: 60, height: 12)
    }

    // MARK: - Layout

    /// Filter row on top, status line at the bottom, entries between.
    public override func layoutSubviews() {
        super.layoutSubviews()

        let width = bounds.size.width
        let height = bounds.size.height
        var top = 0

        if showsFilterBar, height > 2, width > 0 {
            // Fixed-size controls keep their natural widths; the search
            // field takes what is left between the picker and the buttons.
            let pickerWidth = min(levelPicker.intrinsicContentSize?.width ?? 12, max(8, width / 5))
            let linesWidth = min(linesPicker.intrinsicContentSize?.width ?? 10, max(6, width / 6))
            let followWidth = follow.intrinsicContentSize?.width ?? 10
            let clearWidth = clearButton.intrinsicContentSize?.width ?? 7
            let copyWidth = copyButton.intrinsicContentSize?.width ?? 6
            let fixed = pickerWidth + linesWidth + followWidth + clearWidth + copyWidth + 5
            let searchWidth = max(6, width - fixed)
            var x = 0

            levelPicker.frame = Rect(x: x, y: 0, width: pickerWidth, height: 1)
            x += pickerWidth + 1
            linesPicker.frame = Rect(x: x, y: 0, width: linesWidth, height: 1)
            x += linesWidth + 1
            search.frame = Rect(x: x, y: 0, width: min(searchWidth, max(0, width - x)), height: 1)
            x += searchWidth + 1
            follow.frame = Rect(x: min(x, width), y: 0, width: followWidth, height: 1)
            x += followWidth + 1
            clearButton.frame = Rect(x: min(x, width), y: 0, width: clearWidth, height: 1)
            x += clearWidth + 1
            copyButton.frame = Rect(x: min(x, width), y: 0, width: copyWidth, height: 1)

            top = 1
        }

        let statusRows = height > 3 ? 1 : 0
        list.frame = Rect(x: 0, y: top, width: width, height: max(0, height - top - statusRows))
        status.frame = Rect(x: 0, y: height - 1, width: width, height: statusRows)
        status.isHidden = statusRows == 0
    }

    // MARK: - Wiring

    private func startWatching() {
        watch = store.onChange { [weak self] entries in
            guard let self else { return }
            all = entries
            refilter()
        }
        all = store.entries
        refilter()
    }

    // MARK: - Filtering

    /// Re-applies the filters and redraws.
    public func reload() {
        all = store.entries
        refilter()
    }

    private func refilter() {
        refreshLevelChoices()

        let needle = searchText.lowercased()

        visible = all.filter { entry in
            guard entry.level >= level else { return false }

            if let categories, !categories.contains(entry.category) { return false }

            guard !needle.isEmpty else { return true }

            return entry.message.lowercased().contains(needle)
                || entry.category.rawValue.lowercased().contains(needle)
                || entry.origin.lowercased().contains(needle)
        }

        // An entry that has been dropped from the ring cannot be opened, and
        // its id must not sit in the set waiting to be handed to a new entry.
        if !expandedEntries.isEmpty {
            expandedEntries.formIntersection(all.lazy.map(\.id))
        }

        list.entries = visible
        updateStatus()

        if followsTail { list.scrollToEnd() }

        setNeedsDisplay()
    }

    /// Keeps the picker's list in step with what has actually been logged.
    ///
    /// Levels are open — an app can invent `COMMAND` — so the picker cannot
    /// be a fixed list. It cannot be rebuilt on every entry either, hence the
    /// comparison before touching it.
    private func refreshLevelChoices() {
        var found = Set(LogLevel.standard)

        for entry in all { found.insert(entry.level) }

        let sorted = found.sorted()

        guard sorted != levelChoices else { return }

        levelChoices = sorted
        levelPicker.items = sorted.map(\.name)
        levelPicker.select(sorted.firstIndex(of: level) ?? 0)
    }

    private func updateStatus() {
        var text = "\(visible.count) of \(all.count)"

        if store.hasDropped { text += " · \(store.totalWritten) logged" }

        let isFiltered = !searchText.isEmpty || level != LogLevel.trace || categories != nil

        if isFiltered { text += " · filtered" }

        status.text = text
    }

    // MARK: - Opening entries

    /// Opens a message, or shuts it again.
    ///
    /// **The whole message, in place.** Not a dialog: a log is read by
    /// comparing an entry with the ones around it, and a panel over the top
    /// of them is the wrong shape for that. An opened entry ignores
    /// ``maximumLines``; double-click (or toggle) again to shut it. An app
    /// that wants a window of its own has ``onSelect`` and can build one.
    public func toggleExpanded(_ entry: LogEntry) {
        if expandedEntries.remove(entry.id) == nil {
            expandedEntries.insert(entry.id)
        }
    }

    /// Shuts every open message.
    public func collapseAll() {
        expandedEntries.removeAll()
    }

    // MARK: - Copy

    /// Puts what is on screen on the pasteboard.
    ///
    /// **What is on screen, not the whole store.** Someone who has filtered
    /// to the six lines around a failure wants those six lines in the bug
    /// report, not two thousand.
    public func copyToPasteboard() {
        (pasteboard ?? owningWindow?.app?.pasteboard)?.copy(textFormatter.string(for: visible))
    }

    /// The clipboard, when a test injects one.
    public var pasteboard: Pasteboard?
}

/// The rows themselves: virtual (only what is on screen is composed),
/// colored by level, selectable, and as tall as ``LogView/maximumLines`` and
/// the opened entries allow. The shared scrollbar rides the last column when
/// the rows overflow.
///
/// Selection is by ENTRY; scrolling is by visual row — an opened stack trace
/// scrolls line by line, but arrows step entry by entry and the whole entry
/// highlights.
@MainActor
final class LogListView: TUIView {
    /// What to show, oldest first. The parent assigns the filtered slice.
    var entries: [LogEntry] = [] {
        didSet {
            cache = nil

            if let selected = selectedIndex, selected >= entries.count {
                selectedIndex = entries.isEmpty ? nil : entries.count - 1
            }

            setNeedsDisplay()
        }
    }

    /// The display-line cap, mirrored from the parent (nil = no max).
    var maximumLines: Int? = 1 {
        didSet {
            if maximumLines != oldValue {
                cache = nil
                setNeedsDisplay()
            }
        }
    }

    /// Which entry ids are opened to their full message.
    var expanded: Set<UInt64> = [] {
        didSet {
            if expanded != oldValue {
                cache = nil
                setNeedsDisplay()
            }
        }
    }

    /// Called when the selection changes, with the entry.
    var onSelect: ((LogEntry?) -> Void)?

    /// Called on a double-click, with the entry to open or shut.
    var onToggleExpand: ((LogEntry) -> Void)?

    /// Called when the user scrolls or steps away from the tail.
    var onUserScrolledBack: (() -> Void)?

    private var selectedIndex: Int?
    private var scrollOffset = 0        // in visual rows
    private var scrollbarGrab: Int?

    // Whether the view keeps itself scrolled to the newest entry. A flag
    // resolved at DRAW time rather than an offset computed now, because the
    // tail's position depends on the height and the wrap width, and entries
    // usually arrive before layout has run. Cleared by any user scroll or
    // selection.
    private var pinsToEnd = false

    /// The selected entry, when any.
    var selectedEntry: LogEntry? {
        selectedIndex.flatMap { $0 < entries.count ? entries[$0] : nil }
    }

    override var acceptsFirstResponder: Bool { true }

    override func didBecomeFirstResponder() { setNeedsDisplay() }
    override func didResignFirstResponder() { setNeedsDisplay() }

    /// Jumps to the newest entry and stays there until the user looks away.
    func scrollToEnd() {
        pinsToEnd = true
        setNeedsDisplay()
    }

    // MARK: - Visual rows

    // One screen row: an entry, and which of its displayed message lines
    // this is (0 carries the time, the level, the category and the origin).
    private struct VisualRow {
        var entry: Int
        var line: Int
        var text: Substring
    }

    // The wrapped rows plus the geometry they were wrapped for. Rebuilt when
    // the entries, the cap, the opened set, or the size change — and NOT per
    // draw, because wrapping two thousand messages is real work.
    private struct RowLayout {
        var rows: [VisualRow]
        var firstRow: [Int]         // entry index → its first visual row
        var rowWidth: Int
        var showsTime: Bool
        var showsCategory: Bool
        var showsOrigin: Bool
        var messageX: Int
        var messageWidth: Int
    }

    private var cache: RowLayout?
    private var cachedSize = Size(width: -1, height: -1)

    // The fixed origin gutter: two blanks and a 24-column, right-identified
    // slot, so origins line up down the page the way the other columns do.
    private static let originGutter = 26

    private func currentLayout() -> RowLayout {
        if let cache, cachedSize == bounds.size {
            return cache
        }

        let height = max(1, bounds.size.height)
        let width = max(1, bounds.size.width)

        // The scrollbar column narrows the wrap width, which can only add
        // rows — so try full width first and re-lay narrower on overflow,
        // the way TextView wraps.
        var layout = makeLayout(rowWidth: entries.count > height ? width - 1 : width)

        if layout.rows.count > height, layout.rowWidth == width, width > 1 {
            layout = makeLayout(rowWidth: width - 1)
        }

        cache = layout
        cachedSize = bounds.size
        return layout
    }

    private func makeLayout(rowWidth: Int) -> RowLayout {
        // Narrow views drop the quieter columns before they crowd out the
        // message — the same judgement a status bar makes.
        let showsTime = rowWidth >= 40
        let showsCategory = rowWidth >= 64
        let showsOrigin = rowWidth >= 84
        let messageX = (showsTime ? 13 : 0) + 8 + (showsCategory ? 13 : 0)
        let messageWidth = max(1, rowWidth - messageX - (showsOrigin ? Self.originGutter : 0))

        var rows: [VisualRow] = []
        var firstRow: [Int] = []
        firstRow.reserveCapacity(entries.count)

        for (index, entry) in entries.enumerated() {
            firstRow.append(rows.count)

            let limit = expanded.contains(entry.id) ? nil : maximumLines

            if limit == 1 {
                // The fast path, and the default: one row, first line only,
                // no wrapping walked at all.
                rows.append(VisualRow(entry: index, line: 0, text: Substring(entry.summary)))
                continue
            }

            var produced = 0

            for own in entry.message.split(separator: "\n", omittingEmptySubsequences: false) {
                var remainder = own

                repeat {
                    if let limit, produced >= limit { break }

                    let piece = DisplayWidth.prefix(of: remainder, fitting: messageWidth)
                    let cut = piece.text.isEmpty
                        ? remainder.index(after: remainder.startIndex)   // one giant cluster still advances
                        : remainder.index(remainder.startIndex, offsetBy: piece.text.count)
                    rows.append(VisualRow(entry: index, line: produced, text: remainder[..<cut]))
                    produced += 1
                    remainder = remainder[cut...]
                } while !remainder.isEmpty

                if let limit, produced >= limit { break }
            }

            if produced == 0 {
                rows.append(VisualRow(entry: index, line: 0, text: Substring("")))
            }
        }

        return RowLayout(rows: rows, firstRow: firstRow, rowWidth: rowWidth,
                         showsTime: showsTime, showsCategory: showsCategory,
                         showsOrigin: showsOrigin, messageX: messageX, messageWidth: messageWidth)
    }

    // MARK: - Drawing

    /// `HH:mm:ss.SSS` — the date belongs in the export, not on every row.
    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    override func draw(_ painter: Painter) {
        let height = bounds.size.height
        let width = bounds.size.width

        guard height > 0, width > 0 else { return }

        let layout = currentLayout()

        if pinsToEnd {
            scrollOffset = max(0, layout.rows.count - height)
        }

        scrollOffset = min(scrollOffset, max(0, layout.rows.count - height))

        let showsScrollbar = layout.rows.count > height && width > 1

        for row in 0..<height {
            let index = scrollOffset + row

            guard index < layout.rows.count else { break }

            let visual = layout.rows[index]
            let entry = entries[visual.entry]
            let isSelected = visual.entry == selectedIndex

            var secondary = CellStyle()
            secondary.flags.insert(.dim)
            var ink = CellStyle()
            ink.foreground = entry.level.color
            var message = CellStyle()

            if entry.level >= .warning {
                message.foreground = entry.level.color
            }

            if entry.level >= .fault {
                message.flags.insert(.bold)
            }

            if isSelected {
                var selection = effectiveTheme.selection

                if isFirstResponder { selection.flags.insert(.bold) }

                secondary = selection
                ink = selection
                message = selection
            }

            // Background first, so the selection reads as a full bar.
            painter.write(String(repeating: " ", count: layout.rowWidth), at: Point(x: 0, y: row), style: message)

            // A continuation line is only its text, hanging in the message
            // column — the time and the category belong beside the FIRST
            // line, not floating halfway down a stack trace.
            guard visual.line == 0 else {
                painter.write(String(visual.text), at: Point(x: layout.messageX, y: row), style: message)
                continue
            }

            var x = 0

            if layout.showsTime {
                painter.write(Self.time.string(from: entry.date), at: Point(x: x, y: row), style: secondary)
                x += 13
            }

            painter.write(LogLineFormatter.fit(entry.level.name, 7), at: Point(x: x, y: row), style: ink)
            x += 8

            if layout.showsCategory {
                let category = "[" + LogLineFormatter.fit(entry.category.rawValue, 10) + "]"
                painter.write(category, at: Point(x: x, y: row), style: secondary)
                x += 13
            }

            // The ⋯ marks a message with more to say. It counts the
            // message's own lines, not the wrapped ones — honest about a
            // stack trace, silent about a long sentence that needed two
            // lines, and unchanged when the view resizes.
            let limit = expanded.contains(entry.id) ? nil : maximumLines
            let hasMore = limit.map { entry.lineCount > $0 } ?? false

            if layout.showsOrigin {
                painter.write(Label.truncated(String(visual.text), width: layout.messageWidth),
                              at: Point(x: x, y: row), style: message)
                let origin = LogLineFormatter.fit(hasMore ? entry.origin + " ⋯" : entry.origin, Self.originGutter - 2)
                painter.write(origin, at: Point(x: layout.rowWidth - Self.originGutter + 2, y: row), style: secondary)
            } else {
                let text = String(visual.text) + (hasMore ? " ⋯" : "")
                painter.write(Label.truncated(text, width: layout.messageWidth), at: Point(x: x, y: row), style: message)
            }
        }

        if showsScrollbar {
            let (track, thumb) = ScrollView.indicatorStyles(for: effectiveTheme, focused: isFirstResponder)
            scrollbarRun(layout: layout, height: height).draw(in: painter, vertical: true, at: width - 1, track: track, thumb: thumb)
        }
    }

    private func scrollbarRun(layout: RowLayout, height: Int) -> ScrollbarRun {
        ScrollbarRun(
            start: 0,
            length: height,
            span: ScrollSpan(offset: scrollOffset, viewport: height, content: max(1, layout.rows.count))
        )
    }

    // MARK: - Keyboard

    override func keyDown(_ key: KeyInput) -> Bool {
        guard key.modifiers.isEmpty else { return false }

        let height = max(1, bounds.size.height)

        switch key.key {
        case .up:
            pinsToEnd = false
            moveSelection(by: -1)
            onUserScrolledBack?()
            return true

        case .down:
            moveSelection(by: 1)
            return true

        case .pageUp:
            pinsToEnd = false
            moveSelection(by: -max(1, height - 1))
            onUserScrolledBack?()
            return true

        case .pageDown:
            moveSelection(by: max(1, height - 1))
            return true

        case .home:
            guard !entries.isEmpty else { return true }
            selectedIndex = 0
            ensureSelectionVisible()
            onUserScrolledBack?()
            notifySelection()
            return true

        case .end:
            guard !entries.isEmpty else { return true }
            selectedIndex = entries.count - 1
            ensureSelectionVisible()
            notifySelection()
            return true

        case .enter:
            // Enter is the keyboard's double-click: open or shut the
            // selected message.
            guard let entry = selectedEntry else { return false }
            onToggleExpand?(entry)
            return true

        default:
            return false
        }
    }

    private func moveSelection(by delta: Int) {
        guard !entries.isEmpty else { return }

        let current = selectedIndex ?? (delta > 0 ? -1 : entries.count)
        let target = min(max(0, current + delta), entries.count - 1)

        guard target != selectedIndex else { return }

        selectedIndex = target
        ensureSelectionVisible()
        notifySelection()
    }

    // Scrolls so the selected entry's first row shows (and as much of the
    // rest as fits).
    private func ensureSelectionVisible() {
        guard let selected = selectedIndex else { return }

        let layout = currentLayout()
        let height = max(1, bounds.size.height)

        guard layout.firstRow.indices.contains(selected) else { return }

        let first = layout.firstRow[selected]
        let last = selected + 1 < layout.firstRow.count ? layout.firstRow[selected + 1] - 1 : layout.rows.count - 1

        if first < scrollOffset {
            scrollOffset = first
        } else if last > scrollOffset + height - 1 {
            scrollOffset = min(first, last - height + 1)
        }
    }

    private func notifySelection() {
        pinsToEnd = false
        setNeedsDisplay()
        onSelect?(selectedEntry)
    }

    // MARK: - Mouse

    override func mouseEvent(_ mouse: MouseInput) -> Bool {
        let height = bounds.size.height
        let layout = currentLayout()
        let overflow = layout.rows.count > height && bounds.size.width > 1

        switch mouse.action {
        case .press where mouse.button == .left:
            // Only the scrollbar acts on the raw press; a row's select and
            // the double-click's open both wait for the settled `.click`.
            if overflow, mouse.position.x == bounds.size.width - 1 {
                pinsToEnd = false
                let run = scrollbarRun(layout: layout, height: height)
                scrollOffset = clampOffset(run.offset(forPress: mouse.position.y, grab: &scrollbarGrab), layout: layout)
                onUserScrolledBack?()
                setNeedsDisplay()
                return true
            }

            owningWindow?.makeFirstResponder(self)
            return true

        case .click:
            if overflow, mouse.position.x == bounds.size.width - 1 {
                return false
            }

            let index = scrollOffset + mouse.position.y

            guard index < layout.rows.count else { return true }

            let entry = layout.rows[index].entry
            pinsToEnd = false

            if selectedIndex != entry {
                selectedIndex = entry
                notifySelection()
            }

            if mouse.clickCount >= 2 {
                onToggleExpand?(entries[entry])
            }

            return true

        case .drag where scrollbarGrab != nil:
            let run = scrollbarRun(layout: layout, height: height)
            scrollOffset = clampOffset(run.offset(forThumbStart: mouse.position.y - (scrollbarGrab ?? 0)), layout: layout)
            setNeedsDisplay()
            return true

        case .release where scrollbarGrab != nil:
            scrollbarGrab = nil
            return true

        case .scrollUp:
            pinsToEnd = false
            scrollOffset = clampOffset(scrollOffset - 1, layout: layout)
            onUserScrolledBack?()
            setNeedsDisplay()
            return true

        case .scrollDown:
            scrollOffset = clampOffset(scrollOffset + 1, layout: layout)
            setNeedsDisplay()
            return true

        default:
            return false
        }
    }

    private func clampOffset(_ offset: Int, layout: RowLayout) -> Int {
        min(max(0, offset), max(0, layout.rows.count - bounds.size.height))
    }
}
