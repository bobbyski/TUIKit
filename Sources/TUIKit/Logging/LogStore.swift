import Foundation

/// Keeps the last so many entries in memory, for ``LogView`` to draw.
///
/// **A ring, not an array that is trimmed.** Appending and then calling
/// `removeFirst()` in a loop shuffles every remaining element down one on
/// each call — invisible at a cap of a few hundred, and at a few thousand it
/// is the log slowing the program down.
///
/// **Written on the logger's queue, read from the main actor.** Everything
/// here is behind a lock for that reason, and ``onChange(_:)`` is delivered
/// on the main actor so a view can act on it without hopping itself.
public final class LogStore: LogDestination, @unchecked Sendable {
    /// The store ``LogView`` uses when it is not given one.
    public static let shared = LogStore()

    private let lock = NSLock()
    private var ring: [LogEntry?]
    private var nextSlot = 0
    private var written = 0
    private var changeHandlers: [(UInt64, @MainActor @Sendable ([LogEntry]) -> Void)] = []
    private var nextHandlerID: UInt64 = 0

    /// How many entries are kept. Older ones fall off the back.
    public let capacity: Int

    /// Creates a store.
    public init(capacity: Int = 2000) {
        self.capacity = max(1, capacity)
        ring = Array(repeating: nil, count: max(1, capacity))
    }

    /// Every entry held, oldest first.
    public var entries: [LogEntry] {
        lock.withLock { unlockedEntries() }
    }

    /// How many entries have ever been written, including those dropped.
    ///
    /// A view can show "2000 of 41233" rather than pretending the oldest
    /// thing it holds is the beginning.
    public var totalWritten: Int { lock.withLock { written } }

    /// Whether anything has been dropped off the back.
    public var hasDropped: Bool { lock.withLock { written > capacity } }

    /// Keeps one entry, dropping the oldest when the ring is full, and tells
    /// the change handlers on the main actor.
    public func receive(_ entry: LogEntry) {
        let snapshot: [LogEntry]
        let handlers: [@MainActor @Sendable ([LogEntry]) -> Void]
        (snapshot, handlers) = lock.withLock {
            ring[nextSlot] = entry
            nextSlot = (nextSlot + 1) % capacity
            written += 1
            return (unlockedEntries(), changeHandlers.map(\.1))
        }

        guard !handlers.isEmpty else { return }

        // On the main actor, because the only thing that watches a log store
        // is a view, and a view that had to hop for itself would be one hop
        // behind on every entry.
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                for handler in handlers { handler(snapshot) }
            }
        }
    }

    /// Throws everything away.
    public func clear() {
        let handlers: [@MainActor @Sendable ([LogEntry]) -> Void] = lock.withLock {
            ring = Array(repeating: nil, count: capacity)
            nextSlot = 0
            written = 0
            return changeHandlers.map(\.1)
        }

        guard !handlers.isEmpty else { return }

        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                for handler in handlers { handler([]) }
            }
        }
    }

    /// Calls `handler` on the main actor whenever the store changes, and
    /// hands back the token that stops it.
    @discardableResult
    public func onChange(_ handler: @escaping @MainActor @Sendable ([LogEntry]) -> Void) -> LogDestinationToken {
        lock.withLock {
            nextHandlerID += 1
            changeHandlers.append((nextHandlerID, handler))
            return LogDestinationToken(id: nextHandlerID)
        }
    }

    /// Stops a change handler.
    public func removeHandler(_ token: LogDestinationToken) {
        lock.withLock { changeHandlers.removeAll { $0.0 == token.id } }
    }

    /// The whole log as text, for a bug report or a file.
    ///
    /// Through ``LogLineFormatter``, so the file reads exactly like the
    /// terminal did — fixed columns, and continuation lines hanging under the
    /// message rather than starting at column zero where they read as
    /// separate entries.
    public func exported(using formatter: LogLineFormatter = .file) -> String {
        formatter.string(for: entries)
    }

    /// Oldest first. Called with the lock already held.
    private func unlockedEntries() -> [LogEntry] {
        guard written > 0 else { return [] }

        if written < capacity { return ring[0..<nextSlot].compactMap { $0 } }

        // Wrapped: the oldest entry is the one about to be overwritten.
        return (ring[nextSlot...] + ring[..<nextSlot]).compactMap { $0 }
    }
}
