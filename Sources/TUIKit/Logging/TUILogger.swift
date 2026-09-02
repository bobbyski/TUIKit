import Foundation

/// The log.
///
/// ```swift
/// TUILogger.shared.debug("laid out \(subviews.count) children", category: .layout)
/// TUILogger.shared.error("could not open \(path)")
/// ```
///
/// (`TUILogger`, not `Logger`: `os.Logger` and swift-log's `Logger` are both
/// one `import` away in any real app, and a name fight over the thing you
/// reach for while debugging is the last fight worth having.)
///
/// **The call never waits.** A logger that blocks is a logger people take out
/// of the hot path, and the hot path is where the diagnostics are. The level
/// check is a couple of integer comparisons under an uncontended lock; if it
/// passes, the entry is handed to a serial queue and the caller returns. A
/// destination writing to a file or the unified log does so on that queue,
/// and cannot hold up the code that logged — which in a TUI is the render
/// loop itself.
///
/// The order entries arrive in is the order they were logged: one serial
/// queue, not a concurrent one. A log whose lines can swap places is worse
/// than no log.
///
/// **The message is not built unless it will be used.** `message` is an
/// autoclosure, so `debug("state: \(expensiveDescription)")` costs nothing at
/// all when the level is off — which matters when a codebase has a thousand
/// debug calls in it.
public final class TUILogger: @unchecked Sendable {
    /// The log everything uses unless told otherwise.
    public static let shared = TUILogger()

    private let lock = NSLock()
    private let queue: DispatchQueue
    private var destinations: [(token: LogDestinationToken, destination: LogDestination)] = []
    private var minimum: LogLevel = .info
    private var overrides: [LogCategory: LogLevel] = [:]
    private var nextID: UInt64 = 0
    private var isEnabled = true

    /// Creates a logger with its own queue and destinations.
    ///
    /// Public so a test, or a subsystem that wants its own stream, need not
    /// fight over the shared one.
    public init(label: String = "com.tuikit.log") {
        queue = DispatchQueue(label: label, qos: .utility)
    }

    // MARK: - What gets through

    /// The lowest level that is logged, unless a category says otherwise.
    public var level: LogLevel {
        get { lock.withLock { minimum } }
        set { lock.withLock { minimum = newValue } }
    }

    /// Whether anything is logged at all. The switch a shipping build flips.
    public var isLogging: Bool {
        get { lock.withLock { isEnabled } }
        set { lock.withLock { isEnabled = newValue } }
    }

    /// Sets the lowest level for one category, or clears it with nil.
    ///
    /// **This is the knob that makes a log usable.** Turn `layout` down to
    /// `.warning` while leaving your own code at `.debug`, rather than the
    /// all-or-nothing choice that has everybody logging at error and learning
    /// nothing.
    public func setLevel(_ level: LogLevel?, for category: LogCategory) {
        lock.withLock { overrides[category] = level }
    }

    /// The level in force for a category.
    public func level(for category: LogCategory) -> LogLevel {
        lock.withLock { overrides[category] ?? minimum }
    }

    /// Whether an entry at this level and category would be logged.
    ///
    /// Worth asking before assembling something genuinely expensive that an
    /// autoclosure cannot defer — a hex dump of a megabyte, say.
    public func isEnabled(_ level: LogLevel, category: LogCategory = .app) -> Bool {
        lock.withLock { isEnabled && level >= (overrides[category] ?? minimum) }
    }

    // MARK: - Destinations

    /// Adds a destination and hands back the token that removes it.
    @discardableResult
    public func add(_ destination: LogDestination) -> LogDestinationToken {
        lock.withLock {
            nextID += 1
            let token = LogDestinationToken(id: nextID)
            destinations.append((token, destination))
            return token
        }
    }

    /// Removes a destination.
    public func remove(_ token: LogDestinationToken) {
        lock.withLock { destinations.removeAll { $0.token == token } }
    }

    /// Removes every destination.
    public func removeAllDestinations() {
        lock.withLock { destinations.removeAll() }
    }

    /// How many destinations are registered.
    public var destinationCount: Int { lock.withLock { destinations.count } }

    // MARK: - Logging

    /// Logs a message.
    public func log(_ level: LogLevel,
                    _ message: @autoclosure () -> String,
                    category: LogCategory = .app,
                    file: String = #fileID, line: Int = #line, function: String = #function) {
        // One lock, taken once, handing back everything the rest of the call
        // needs — the id AND the destinations. Claiming the id in a second
        // critical section would let another thread claim one in between and
        // take the first thread's number with it.
        let claim: (id: UInt64, destinations: [LogDestination])? = lock.withLock {
            guard isEnabled, level >= (overrides[category] ?? minimum),
                  !destinations.isEmpty else { return nil }
            nextID += 1
            return (nextID, destinations.map(\.destination))
        }

        guard let claim else { return }

        let entry = LogEntry(id: claim.id, date: Date(), level: level,
                             category: category, message: message(),
                             file: file, line: line, function: function)

        // And away — the caller is done. Serial, so the order entries arrive
        // in is the order they were logged.
        queue.async { for destination in claim.destinations { destination.receive(entry) } }
    }

    /// Waits for everything logged so far to reach its destinations.
    ///
    /// **The one place waiting is right.** A crash handler, a test, or a
    /// program about to exit needs the last lines actually written;
    /// everywhere else, waiting is the thing this logger exists not to do.
    public func flush() {
        queue.sync {}
        let current = lock.withLock { destinations.map(\.destination) }
        for destination in current { destination.flush() }
    }

    // MARK: - Shorthands

    /// Very fine detail.
    public func trace(_ message: @autoclosure () -> String, category: LogCategory = .app,
                      file: String = #fileID, line: Int = #line, function: String = #function) {
        log(.trace, message(), category: category, file: file, line: line, function: function)
    }

    /// What the code is doing.
    public func debug(_ message: @autoclosure () -> String, category: LogCategory = .app,
                      file: String = #fileID, line: Int = #line, function: String = #function) {
        log(.debug, message(), category: category, file: file, line: line, function: function)
    }

    /// Something worth knowing happened.
    public func info(_ message: @autoclosure () -> String, category: LogCategory = .app,
                     file: String = #fileID, line: Int = #line, function: String = #function) {
        log(.info, message(), category: category, file: file, line: line, function: function)
    }

    /// Worth knowing and worth keeping.
    public func notice(_ message: @autoclosure () -> String, category: LogCategory = .app,
                       file: String = #fileID, line: Int = #line, function: String = #function) {
        log(.notice, message(), category: category, file: file, line: line, function: function)
    }

    /// Something is off but the program carried on.
    public func warning(_ message: @autoclosure () -> String, category: LogCategory = .app,
                        file: String = #fileID, line: Int = #line, function: String = #function) {
        log(.warning, message(), category: category, file: file, line: line, function: function)
    }

    /// Something failed.
    public func error(_ message: @autoclosure () -> String, category: LogCategory = .app,
                      file: String = #fileID, line: Int = #line, function: String = #function) {
        log(.error, message(), category: category, file: file, line: line, function: function)
    }

    /// Something failed that should have been impossible.
    public func fault(_ message: @autoclosure () -> String, category: LogCategory = .app,
                      file: String = #fileID, line: Int = #line, function: String = #function) {
        log(.fault, message(), category: category, file: file, line: line, function: function)
    }

    /// Logs a thrown error.
    public func error(_ error: Error, category: LogCategory = .app,
                      file: String = #fileID, line: Int = #line, function: String = #function) {
        log(.error, "\(error)", category: category, file: file, line: line, function: function)
    }
}
