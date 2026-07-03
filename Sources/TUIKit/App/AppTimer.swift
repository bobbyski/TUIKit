import Foundation

/// A source of periodic ticks for `App` timers.
///
/// Abstracted so the real clock and a test-driven source are
/// interchangeable: production uses `ClockTimerSource` (suspends between
/// ticks, never blocks a thread), and tests use `ManualTimerSource` to fire
/// ticks by hand with no wall-clock time passing at all — the timer story is
/// headless-scriptable, exactly like input.
public protocol TimerSource: Sendable {
    /// A stream that yields roughly every `interval`.
    ///
    /// The stream is cancelled (and its underlying timing torn down) when
    /// its continuation terminates.
    ///
    /// - Parameter interval: Time between ticks.
    /// - Returns: An endless stream of ticks.
    func ticks(every interval: Duration) -> AsyncStream<Void>
}

/// The production `TimerSource`: `Task.sleep` between ticks.
///
/// Sleeping suspends the timer's task cooperatively — it never blocks a
/// thread — so it honors TUIKit's never-block rule by construction.
public struct ClockTimerSource: TimerSource {
    /// Creates a clock-backed timer source.
    public init() {}

    /// A stream that yields after each `interval` elapses.
    ///
    /// - Parameter interval: Time between ticks.
    /// - Returns: An endless stream of ticks until cancelled.
    public func ticks(every interval: Duration) -> AsyncStream<Void> {
        AsyncStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: interval)

                    if Task.isCancelled {
                        break
                    }

                    continuation.yield(())
                }

                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

/// A `TimerSource` whose ticks are fired by hand, for deterministic tests.
///
/// ```swift
/// let clock = ManualTimerSource()
/// let app = App(driver: driver, timerSource: clock)
/// // ... run, register a spinner timer ...
/// clock.fire()          // advance one tick with no real time elapsed
/// ```
public final class ManualTimerSource: TimerSource, @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [AsyncStream<Void>.Continuation] = []

    /// Creates a manual timer source with no ticks pending.
    public init() {}

    /// Registers a new tick stream (all streams receive every `fire()`).
    ///
    /// - Parameter interval: Ignored; ticks are manual.
    /// - Returns: A stream fed by `fire()`.
    public func ticks(every interval: Duration) -> AsyncStream<Void> {
        AsyncStream { continuation in
            lock.lock()
            continuations.append(continuation)
            lock.unlock()
        }
    }

    /// Number of tick streams registered so far.
    ///
    /// Tests await this reaching the expected count before `fire()`, so a
    /// tick is never dropped for a stream that has not registered yet.
    public var streamCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return continuations.count
    }

    /// Emits one tick to every stream this source has produced.
    public func fire() {
        lock.lock()
        let current = continuations
        lock.unlock()

        for continuation in current {
            continuation.yield(())
        }
    }
}

/// A timer registered with a running `App` — repeating or one-shot.
///
/// The timer suspends between ticks (never blocking) and delivers its
/// callback on the `MainActor` inside the run loop, so each fire naturally
/// drives a frame present — the same path input takes. Animating controls
/// (the `ProgressIndicator` spinner today) use a repeating one; delayed
/// actions (debounces, the Phase 11 tooltip delay) use a one-shot, which
/// cancels itself after firing once.
@MainActor
public final class AppTimer {
    /// Time between ticks (or the delay, for a one-shot).
    public let interval: Duration

    /// Whether the timer keeps firing. A one-shot (`false`) cancels itself
    /// after its first fire.
    public let repeats: Bool

    /// Whether the timer has been cancelled.
    public private(set) var isCancelled = false

    // Called on each tick, on the MainActor, inside the run loop.
    let body: @MainActor () -> Void

    // The task forwarding this timer's ticks into the run loop, when running.
    var task: Task<Void, Never>?

    // Called by cancel() so the App can forget the timer.
    var onCancel: (AppTimer) -> Void = { _ in }

    init(interval: Duration, repeats: Bool, body: @escaping @MainActor () -> Void) {
        self.interval = interval
        self.repeats = repeats
        self.body = body
    }

    /// Stops the timer; no further ticks fire.
    public func cancel() {
        guard !isCancelled else {
            return
        }

        isCancelled = true
        task?.cancel()
        task = nil
        onCancel(self)
    }
}
