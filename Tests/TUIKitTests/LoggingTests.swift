import Foundation
import Testing
@testable import TUIKit

// The logger tools, ported from ActiveUI's Logging/ suite: an open level
// ladder, a never-blocking logger, destinations, a fixed-column formatter,
// a ring-buffer store, and LogView on top.

private func entry(_ id: UInt64, _ level: LogLevel = .info, _ message: String = "m",
                   category: LogCategory = .app, file: String = "Sources/App/Thing.swift",
                   line: Int = 42) -> LogEntry {
    LogEntry(id: id, date: Date(timeIntervalSince1970: 1_756_800_000), level: level,
             category: category, message: message, file: file, line: line, function: "f()")
}

/// Collects entries synchronously, for asserting on what a logger emitted.
private final class CollectingDestination: LogDestination, @unchecked Sendable {
    private let lock = NSLock()
    private var collected: [LogEntry] = []

    var entries: [LogEntry] { lock.withLock { collected } }

    func receive(_ entry: LogEntry) {
        lock.withLock { collected.append(entry) }
    }
}

// MARK: - Levels

@Test func logLevelsCompareBySeverityAndAreIdentifiedByName() {
    #expect(LogLevel.trace < .debug && LogLevel.debug < .info && LogLevel.error < .fault)
    #expect(LogLevel("warning", severity: 999) == .warning, "a level IS its name")
    #expect(LogLevel(stringLiteral: "ERROR") == .error)
    #expect(LogLevel(stringLiteral: "unheard-of").severity == LogLevel.info.severity,
            "an unknown name must not vanish below trace")

    let command = LogLevel("Command", severity: 25)
    #expect(command.name == "COMMAND", "names are upper-cased so debug and DEBUG are one level")
    #expect(command > .info && command < .notice)
}

@Test func logLevelsRoundTripThroughCodable() throws {
    let encoded = try JSONEncoder().encode([LogLevel.warning, LogLevel("COMMAND", severity: 25)])
    let decoded = try JSONDecoder().decode([LogLevel].self, from: encoded)

    #expect(decoded[0] == .warning && decoded[0].severity == LogLevel.warning.severity)
    #expect(decoded[1].name == "COMMAND" && decoded[1].severity == 25,
            "a custom level comes back sorting where it did")
}

// MARK: - Logger

@Test func theLoggerFiltersByLevelAndCategoryOverride() {
    let logger = TUILogger(label: "test.filter")
    let sink = CollectingDestination()
    logger.add(sink)
    logger.level = .info
    logger.setLevel(.warning, for: .layout)

    logger.debug("quiet")                            // below the minimum
    logger.info("kept")
    logger.info("layout chatter", category: .layout) // below the override
    logger.warning("layout problem", category: .layout)
    logger.flush()

    #expect(sink.entries.map(\.message) == ["kept", "layout problem"])
    #expect(sink.entries.map(\.id) == sink.entries.map(\.id).sorted(),
            "one serial queue: order in is order out")
}

@Test func theMessageIsNotBuiltWhenTheLevelIsOff() {
    let logger = TUILogger(label: "test.lazy")
    logger.add(CollectingDestination())
    logger.level = .error

    var built = 0
    func expensive() -> String { built += 1; return "x" }

    logger.debug(expensive())
    #expect(built == 0, "the autoclosure never ran")
    #expect(!logger.isEnabled(.debug))
    #expect(logger.isEnabled(.fault))

    logger.isLogging = false
    logger.error(expensive())
    #expect(built == 0, "the shipping-build switch stops everything")
}

@Test func aRemovedDestinationHearsNothingMore() {
    let logger = TUILogger(label: "test.remove")
    let sink = CollectingDestination()
    let token = logger.add(sink)

    logger.info("one")
    logger.flush()
    logger.remove(token)
    logger.info("two")
    logger.flush()

    #expect(sink.entries.map(\.message) == ["one"])
    #expect(logger.destinationCount == 0)
}

// MARK: - Formatter

@Test func theFormatterKeepsFixedColumnsMeasuredInDisplayColumns() {
    let formatter = LogLineFormatter.file   // no badge

    let ascii = formatter.head(for: entry(1, .info, category: "app"))
    let cjk = formatter.head(for: entry(2, .error, category: "日本語補完"))

    #expect(DisplayWidth.of(ascii) == DisplayWidth.of(cjk),
            "a CJK category must not stagger the message column")
    #expect(DisplayWidth.of(ascii) == formatter.headWidth)

    #expect(LogLineFormatter.fit("abc", 5) == "abc  ")
    #expect(LogLineFormatter.fit("abcdef", 4) == "…def", "trimmed from the front — the tail identifies")
    #expect(DisplayWidth.of(LogLineFormatter.fit("日本語", 4)) == 4, "a wide character is dropped whole")
}

@Test func continuationLinesHangUnderTheMessage() {
    let formatter = LogLineFormatter.file
    let lines = formatter.string(for: entry(1, .info, "first\nsecond")).split(separator: "\n")

    #expect(lines.count == 2)
    #expect(lines[1].hasPrefix(formatter.indent))
    #expect(lines[1].hasSuffix("second"))
}

// MARK: - Store

@Test func theStoreIsARingThatKeepsTheNewest() {
    let store = LogStore(capacity: 3)

    for id in 1...5 {
        store.receive(entry(UInt64(id), .info, "m\(id)"))
    }

    #expect(store.entries.map(\.message) == ["m3", "m4", "m5"], "oldest first, oldest dropped")
    #expect(store.totalWritten == 5)
    #expect(store.hasDropped)

    store.clear()
    #expect(store.entries.isEmpty && store.totalWritten == 0)
}

@Test @MainActor func theStoreTellsItsWatchersOnTheMainActor() async throws {
    let store = LogStore(capacity: 8)
    var seen: [Int] = []
    let token = store.onChange { entries in seen.append(entries.count) }

    store.receive(entry(1))
    store.receive(entry(2))
    try await Task.sleep(for: .milliseconds(100))
    #expect(seen.last == 2, "delivered, on the main actor, in order")

    store.removeHandler(token)
    store.receive(entry(3))
    try await Task.sleep(for: .milliseconds(50))
    #expect(seen.last == 2, "a removed handler hears nothing more")
}

@Test func aFileDestinationWritesAndRollsOver() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("tuikit-log-tests-\(UInt64.random(in: 0...UInt64.max))")
    let url = directory.appendingPathComponent("app.log")
    defer { try? FileManager.default.removeItem(at: directory) }

    let destination = try #require(FileLogDestination(url: url, maximumBytes: 200))
    destination.receive(entry(1, .info, "hello"))
    destination.flush()

    let written = try String(contentsOf: url, encoding: .utf8)
    #expect(written.contains("hello") && written.contains("INFO"))

    for id in 2...10 {
        destination.receive(entry(UInt64(id), .info, String(repeating: "x", count: 40)))
    }
    destination.flush()

    let previous = url.deletingPathExtension().appendingPathExtension("previous").appendingPathExtension("log")
    #expect(FileManager.default.fileExists(atPath: previous.path), "one previous copy kept")
    let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? .max
    #expect(size < 200, "the live file restarted")
}

// MARK: - LogView

@MainActor
private func hostedLogView(_ store: LogStore, width: Int = 90, height: Int = 8) -> (LogView, Window) {
    let view = LogView(store: store)
    let window = Window(frame: Rect(x: 0, y: 0, width: width, height: height))
    view.frame = window.bounds
    window.addSubview(view)
    return (view, window)
}

@MainActor
private func lines(_ window: Window) -> [String] {
    SceneRenderer(root: window).render(size: window.frame.size).textLines()
}

@Test @MainActor func aLogViewShowsRowsWithTheirColumnsAndStatus() {
    let store = LogStore(capacity: 100)
    store.receive(entry(1, .info, "started", category: "lifecycle"))
    store.receive(entry(2, .error, "exploded", category: "app", file: "Boom.swift", line: 7))

    let (view, window) = hostedLogView(store)
    view.reload()
    let rows = lines(window)

    #expect(rows[1].contains("INFO") && rows[1].contains("started") && rows[1].contains("[lifecycle"))
    #expect(rows[2].contains("ERROR") && rows[2].contains("exploded") && rows[2].contains("Boom.swift:7"))
    #expect(rows[7].contains("2 of 2"), "the status line counts")
}

@Test @MainActor func aLogViewFiltersByLevelAndSearch() {
    let store = LogStore(capacity: 100)
    store.receive(entry(1, .debug, "chatter"))
    store.receive(entry(2, .warning, "watch out"))
    store.receive(entry(3, .error, "broken pipe"))

    let (view, window) = hostedLogView(store)
    view.reload()

    view.level = .warning
    #expect(view.visible.map(\.message) == ["watch out", "broken pipe"])
    #expect(lines(window)[7].contains("2 of 3 · filtered"))

    view.searchText = "pipe"
    #expect(view.visible.map(\.message) == ["broken pipe"])

    view.searchText = ""
    view.level = .trace
    view.categories = [.layout]
    #expect(view.visible.isEmpty, "category filter")
}

@Test @MainActor func aLogViewFollowsTheTailUntilYouLookAway() {
    let store = LogStore(capacity: 100)

    for id in 1...30 {
        store.receive(entry(UInt64(id), .info, "line \(id)"))
    }

    let (view, window) = hostedLogView(store, height: 8)
    view.reload()

    // Filter row + status row leave 6 rows of entries: the newest is visible.
    #expect(lines(window)[6].contains("line 30"), "following the tail")

    let list = view.subviews.compactMap { $0 as? LogListView }.first!
    _ = list.mouseEvent(MouseInput(position: Point(x: 0, y: 100), action: .scrollUp, button: .left))
    #expect(view.followsTail == false, "scrolling up means you are reading")

    store.receive(entry(31, .info, "line 31"))
    view.reload()
    #expect(!lines(window)[6].contains("line 31"), "no yanking back to the bottom")

    view.followsTail = true
    #expect(lines(window)[6].contains("line 31"))
}

@Test @MainActor func selectingARowReportsItAndStopsFollowing() {
    let store = LogStore(capacity: 100)
    store.receive(entry(1, .info, "one"))
    store.receive(entry(2, .warning, "two"))

    let (view, window) = hostedLogView(store)
    view.reload()
    _ = lines(window)   // lays the rows out before the click

    var selected: LogEntry?
    view.onSelect = { selected = $0 }

    let list = view.subviews.compactMap { $0 as? LogListView }.first!
    _ = list.mouseEvent(MouseInput(position: Point(x: 3, y: 1), action: .press, button: .left))

    #expect(selected?.message == "two")
    #expect(view.followsTail == false)
}

@Test @MainActor func copyPutsTheVisibleLinesOnThePasteboard() {
    let store = LogStore(capacity: 100)
    store.receive(entry(1, .info, "kept"))
    store.receive(entry(2, .debug, "filtered away"))

    let (view, _) = hostedLogView(store)
    view.reload()
    view.pasteboard = Pasteboard()
    view.level = .info
    view.copyToPasteboard()

    let copied = view.pasteboard?.string ?? ""
    #expect(copied.contains("kept") && !copied.contains("filtered away"),
            "what is on screen, not the whole store")
}

@Test @MainActor func aCustomLevelTurnsUpInTheLevelPicker() {
    let store = LogStore(capacity: 100)
    store.receive(LogEntry(id: 1, date: Date(), level: LogLevel("COMMAND", severity: 25),
                           category: .app, message: "git status", file: "a.swift", line: 1, function: "f"))

    let (view, _) = hostedLogView(store)
    view.reload()

    #expect(view.levelChoices.contains { $0.name == "COMMAND" })
    #expect(view.levelChoices == view.levelChoices.sorted(), "severity order")
}
