import Foundation
#if canImport(OSLog)
import OSLog
#endif

/// Somewhere log entries go.
///
/// **Several at once, deliberately.** A ``LogStore`` for ``LogView``, a file
/// for the bug report, `os.Logger` for Console.app, the console for a CLI
/// tool. Each is a few lines, and an app picks the set it wants rather than
/// being handed one transport and told to like it.
///
/// `receive` is called on the logger's own queue, never on the caller's
/// thread. A destination may take its time; it will not hold up the code that
/// logged.
public protocol LogDestination: AnyObject, Sendable {
    /// Handles one entry.
    func receive(_ entry: LogEntry)

    /// Finishes any pending work. Called by ``TUILogger/flush()``.
    func flush()
}

/// A destination that has nothing to finish need not say so.
public extension LogDestination {
    func flush() {}
}

/// A registration, so a destination can be taken away again.
///
/// Without one, a log view that appeared and disappeared would leave a
/// destination behind every time — and every entry after that would be
/// delivered to a window nobody could see.
public struct LogDestinationToken: Hashable, Sendable {
    let id: UInt64
}

/// Writes to standard output.
///
/// **For a program whose stdout is text** — a CLI tool, tests, an inline-mode
/// utility after it exits. While a full-screen `ANSIDriver` owns the terminal,
/// stdout IS the interface, and a line printed into it lands in the middle of
/// the UI: use a ``LogStore`` + ``LogView``, or a file, there instead.
///
/// The formatting is ``LogLineFormatter``'s, so what you see in the terminal
/// is character-for-character what lands in a file or on the pasteboard.
public final class ConsoleLogDestination: LogDestination, @unchecked Sendable {
    private let lock = NSLock()
    private var format: LogLineFormatter
    private var color: Bool

    /// How lines are laid out.
    public var formatter: LogLineFormatter {
        get { lock.withLock { format } }
        set { lock.withLock { format = newValue } }
    }

    /// Whether ANSI color is used.
    public var usesColor: Bool {
        get { lock.withLock { color } }
        set { lock.withLock { color = newValue } }
    }

    /// Creates a console destination.
    public init(usesColor: Bool = false, formatter: LogLineFormatter = .standard) {
        format = formatter
        color = usesColor
    }

    /// Prints one entry, coloring the message only — a colored timestamp is
    /// noise, and the escape codes would land in a file if anybody piped this.
    public func receive(_ entry: LogEntry) {
        let (format, color) = lock.withLock { (self.format, self.color) }

        guard color else {
            print(format.string(for: entry))
            return
        }

        // The level's ink through the same SGR encoder the driver uses.
        var style = CellStyle()
        style.foreground = entry.level.color
        let on = ANSIEncoder.sequence(for: style)
        let off = ANSIEncoder.reset
        let head = format.head(for: entry)
        let lines = entry.message.split(separator: "\n", omittingEmptySubsequences: false)

        print(head + on + (lines.first.map(String.init) ?? "") + off)

        for line in lines.dropFirst() {
            print(format.indent + on + line + off)
        }
    }
}

#if canImport(OSLog)
/// Sends entries to the unified log, where Console.app and `sysdiagnose` can
/// see them.
///
/// **A back end, not the transport.** `os.Logger` is the right place for a
/// shipped build — the system decides what to keep, it costs almost nothing
/// when nobody is listening, and a support engineer can pull it off a
/// customer machine. What it cannot do is hand anything back, so an in-app
/// viewer needs ``LogStore`` as well. That is the whole reason destinations
/// are a list.
///
/// **Messages are logged as public.** The unified log redacts interpolated
/// values by default, which is right for a payment field and wrong for a
/// diagnostic — a log full of `<private>` is not a log. Keep secrets out of
/// log messages rather than relying on redaction to hide them.
public final class OSLogDestination: LogDestination, @unchecked Sendable {
    private let subsystem: String
    private let lock = NSLock()
    private var loggers: [LogCategory: os.Logger] = [:]

    /// Creates a destination writing under `subsystem`.
    ///
    /// One `os.Logger` per category, made once and kept, so Console.app's
    /// category filter is the same filter ``LogView`` offers and the two
    /// views of one log agree.
    public init(subsystem: String = Bundle.main.bundleIdentifier ?? "TUIKit") {
        self.subsystem = subsystem
    }

    /// Hands one entry to the `os.Logger` for its category.
    public func receive(_ entry: LogEntry) {
        logger(for: entry.category).log(
            level: Self.osLevel(entry.level),
            "\(entry.origin, privacy: .public) \(entry.message, privacy: .public)")
    }

    private func logger(for category: LogCategory) -> os.Logger {
        lock.withLock {
            if let existing = loggers[category] { return existing }
            let made = os.Logger(subsystem: subsystem, category: category.rawValue)
            loggers[category] = made
            return made
        }
    }

    /// **`fault` and `error` are not the same to the system.** A fault is
    /// kept longer and shows up in crash triage; mapping both to `.error`
    /// throws that away. Compared by severity, not by name, so a custom level
    /// lands in the right bucket without this having to know about it.
    static func osLevel(_ level: LogLevel) -> OSLogType {
        switch level.severity {
        case ..<LogLevel.info.severity: .debug
        case ..<LogLevel.notice.severity: .info
        case ..<LogLevel.error.severity: .default
        case ..<LogLevel.fault.severity: .error
        default: .fault
        }
    }
}
#endif

/// Appends to a file.
///
/// **Where a log usually ends up.** The console is the UI while a TUI runs,
/// and the unified log needs a Mac and a cable; a file is what somebody
/// attaches to a bug report. Written through ``LogLineFormatter``, so it
/// reads exactly like the terminal did.
///
/// Writing happens on the logger's queue, so a slow disk cannot hold up the
/// code that logged — the handle is kept open and only flushed on
/// ``TUILogger/flush()`` or when the destination goes away.
public final class FileLogDestination: LogDestination, @unchecked Sendable {
    /// Where it is being written.
    public let url: URL

    /// How lines are laid out.
    public let formatter: LogLineFormatter

    /// How big the file may get before it is rolled over, or nil for no limit.
    public let maximumBytes: Int?

    private let lock = NSLock()
    private var handle: FileHandle?
    private var written: Int = 0

    /// Opens a log file, creating it if it is not there.
    ///
    /// - Parameters:
    ///   - url: Where to write.
    ///   - formatter: How to lay lines out. `.file` by default, which drops
    ///     the emoji badge — it is decoration in a terminal and mojibake in
    ///     half the text editors a log gets opened in.
    ///   - maximumBytes: Roll the file over past this size, keeping one
    ///     previous copy alongside it. Nil never rolls, which is fine for a
    ///     session log and a bad idea for a daemon.
    ///   - truncating: Start the file empty rather than appending.
    public init?(url: URL, formatter: LogLineFormatter = .file,
                 maximumBytes: Int? = 5 * 1024 * 1024, truncating: Bool = false) {
        self.url = url
        self.formatter = formatter
        self.maximumBytes = maximumBytes

        let manager = FileManager.default
        try? manager.createDirectory(at: url.deletingLastPathComponent(),
                                     withIntermediateDirectories: true)

        if truncating || !manager.fileExists(atPath: url.path) {
            guard manager.createFile(atPath: url.path, contents: nil) else { return nil }
        }

        guard let opened = try? FileHandle(forWritingTo: url) else { return nil }

        handle = opened
        written = (try? opened.seekToEnd()).map(Int.init) ?? 0
    }

    deinit {
        try? handle?.close()
    }

    /// Appends one entry, rolling the file over if it has grown past its
    /// limit.
    public func receive(_ entry: LogEntry) {
        let line = formatter.string(for: entry) + "\n"

        guard let data = line.data(using: .utf8) else { return }

        lock.withLock {
            guard let handle else { return }
            try? handle.write(contentsOf: data)
            written += data.count
            if let maximumBytes, written >= maximumBytes { rollOver() }
        }
    }

    /// Flushes the file to disk. Called by ``TUILogger/flush()``.
    public func flush() {
        lock.withLock { try? handle?.synchronize() }
    }

    /// Moves the file aside and starts a new one.
    ///
    /// **One previous copy, not a numbered series.** A rolling series needs a
    /// policy for deleting the old ones, and a logger that fills somebody's
    /// disk is worse than one that forgets. Called with the lock held.
    private func rollOver() {
        try? handle?.close()
        handle = nil

        let previous = url.deletingPathExtension()
            .appendingPathExtension("previous")
            .appendingPathExtension(url.pathExtension)
        try? FileManager.default.removeItem(at: previous)
        try? FileManager.default.moveItem(at: url, to: previous)

        guard FileManager.default.createFile(atPath: url.path, contents: nil),
              let opened = try? FileHandle(forWritingTo: url) else { return }

        handle = opened
        written = 0
    }
}
