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
    private let search = SearchField(placeholder: "Filter")
    private let follow = Checkbox("Follow", isChecked: true)
    private let clearButton = Button("Clear")
    private let copyButton = Button("Copy")
    private let list = LogListView()
    private let status = Label("")

    private var filterControls: [TUIView] {
        [levelPicker, search, follow, clearButton, copyButton]
    }

    /// Creates a log view.
    public init(store: LogStore = .shared) {
        self.store = store
        super.init(frame: .zero)

        levelPicker.onSelectionChanged = { [weak self] index in
            guard let self, index < levelChoices.count else { return }
            level = levelChoices[index]
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
            let pickerWidth = min(levelPicker.intrinsicContentSize?.width ?? 12, max(8, width / 4))
            let followWidth = follow.intrinsicContentSize?.width ?? 10
            let clearWidth = clearButton.intrinsicContentSize?.width ?? 7
            let copyWidth = copyButton.intrinsicContentSize?.width ?? 6
            let fixed = pickerWidth + followWidth + clearWidth + copyWidth + 4
            let searchWidth = max(6, width - fixed)
            var x = 0

            levelPicker.frame = Rect(x: x, y: 0, width: pickerWidth, height: 1)
            x += pickerWidth + 1
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
/// colored by level, selectable, with the shared scrollbar in the last
/// column when the entries overflow.
@MainActor
final class LogListView: TUIView {
    /// What to show, oldest first. The parent assigns the filtered slice.
    var entries: [LogEntry] = [] {
        didSet {
            navigation.count = entries.count

            if let selected = navigation.selectedIndex, selected >= entries.count {
                _ = navigation.select(entries.isEmpty ? nil : entries.count - 1)
            }

            setNeedsDisplay()
        }
    }

    /// Called when the selection changes, with the entry.
    var onSelect: ((LogEntry?) -> Void)?

    /// Called when the user scrolls or steps away from the tail.
    var onUserScrolledBack: (() -> Void)?

    private var navigation = RowNavigationState()
    private var scrollbarGrab: Int?

    // Whether the view keeps itself scrolled to the newest entry. A flag
    // resolved at DRAW time rather than an offset computed now, because the
    // tail's position depends on the height, and entries usually arrive
    // before layout has run. Cleared by any user scroll or selection.
    private var pinsToEnd = false

    /// The selected entry, when any.
    var selectedEntry: LogEntry? {
        navigation.selectedIndex.flatMap { $0 < entries.count ? entries[$0] : nil }
    }

    override var acceptsFirstResponder: Bool { true }

    override func didBecomeFirstResponder() { setNeedsDisplay() }
    override func didResignFirstResponder() { setNeedsDisplay() }

    /// Jumps to the newest entry and stays there until the user looks away.
    func scrollToEnd() {
        pinsToEnd = true
        setNeedsDisplay()
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

        if pinsToEnd {
            navigation.scrollOffset = max(0, entries.count - height)
        }

        let showsScrollbar = entries.count > height && width > 1
        let rowWidth = showsScrollbar ? width - 1 : width

        // Narrow views drop the quieter columns before they crowd out the
        // message — the same judgement a status bar makes.
        let showsTime = rowWidth >= 40
        let showsCategory = rowWidth >= 64
        let showsOrigin = rowWidth >= 84

        for row in 0..<height {
            let index = navigation.scrollOffset + row

            guard index < entries.count else { break }

            let entry = entries[index]
            let isSelected = index == navigation.selectedIndex

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
            painter.write(String(repeating: " ", count: rowWidth), at: Point(x: 0, y: row), style: message)

            var x = 0

            if showsTime {
                painter.write(Self.time.string(from: entry.date), at: Point(x: x, y: row), style: secondary)
                x += 13
            }

            painter.write(LogLineFormatter.fit(entry.level.name, 7), at: Point(x: x, y: row), style: ink)
            x += 8

            if showsCategory {
                let category = "[" + LogLineFormatter.fit(entry.category.rawValue, 10) + "]"
                painter.write(category, at: Point(x: x, y: row), style: secondary)
                x += 13
            }

            let originWidth = showsOrigin ? min(24, DisplayWidth.of(entry.origin)) + 2 : 0
            let messageWidth = max(0, rowWidth - x - originWidth)
            let summary = entry.summary + (entry.isMultiline ? " ⋯" : "")
            painter.write(Label.truncated(summary, width: messageWidth), at: Point(x: x, y: row), style: message)

            if showsOrigin {
                let origin = LogLineFormatter.fit(entry.origin, originWidth - 2)
                painter.write(origin, at: Point(x: rowWidth - originWidth + 2, y: row), style: secondary)
            }
        }

        if showsScrollbar {
            let (track, thumb) = ScrollView.indicatorStyles(for: effectiveTheme, focused: isFirstResponder)
            scrollbarRun(height: height).draw(in: painter, vertical: true, at: width - 1, track: track, thumb: thumb)
        }
    }

    private func scrollbarRun(height: Int) -> ScrollbarRun {
        ScrollbarRun(
            start: 0,
            length: height,
            span: ScrollSpan(offset: navigation.scrollOffset, viewport: height, content: max(1, entries.count))
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
            _ = navigation.select(0)
            navigation.ensureSelectionVisible(height: height)
            onUserScrolledBack?()
            notifySelection()
            return true

        case .end:
            guard !entries.isEmpty else { return true }
            _ = navigation.select(entries.count - 1)
            navigation.ensureSelectionVisible(height: height)
            notifySelection()
            return true

        default:
            return false
        }
    }

    private func moveSelection(by offset: Int) {
        guard navigation.move(by: offset) else { return }

        navigation.ensureSelectionVisible(height: max(1, bounds.size.height))
        notifySelection()
    }

    private func notifySelection() {
        pinsToEnd = false
        setNeedsDisplay()
        onSelect?(selectedEntry)
    }

    // MARK: - Mouse

    override func mouseEvent(_ mouse: MouseInput) -> Bool {
        let height = bounds.size.height
        let overflow = entries.count > height && bounds.size.width > 1

        switch mouse.action {
        case .press where mouse.button == .left:
            if overflow, mouse.position.x == bounds.size.width - 1 {
                pinsToEnd = false
                let run = scrollbarRun(height: height)
                navigation.scrollOffset = clampOffset(run.offset(forPress: mouse.position.y, grab: &scrollbarGrab))
                onUserScrolledBack?()
                setNeedsDisplay()
                return true
            }

            owningWindow?.makeFirstResponder(self)

            let index = navigation.scrollOffset + mouse.position.y

            guard index < entries.count else { return true }

            _ = navigation.select(index)
            notifySelection()
            return true

        case .drag where scrollbarGrab != nil:
            let run = scrollbarRun(height: height)
            navigation.scrollOffset = clampOffset(run.offset(forThumbStart: mouse.position.y - (scrollbarGrab ?? 0)))
            setNeedsDisplay()
            return true

        case .release where scrollbarGrab != nil:
            scrollbarGrab = nil
            return true

        case .scrollUp:
            pinsToEnd = false
            navigation.scroll(by: -1, height: height)
            onUserScrolledBack?()
            setNeedsDisplay()
            return true

        case .scrollDown:
            navigation.scroll(by: 1, height: height)
            setNeedsDisplay()
            return true

        default:
            return false
        }
    }

    private func clampOffset(_ offset: Int) -> Int {
        min(max(0, offset), max(0, entries.count - bounds.size.height))
    }
}
