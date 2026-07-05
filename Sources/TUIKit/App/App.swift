/// The TUIKit application: window stack, input loop, and frame presentation.
///
/// `App` connects a `TerminalDriver` to a stack of `Window`s:
///
/// ```text
///   driver.inputStream() ──> key window.route(_:) ──> views
///                                   │
///        SceneRenderer.renderIfNeeded ──> driver.present ──> terminal
/// ```
///
/// The run loop is pure suspension — `for await` on the driver's input
/// stream — so it satisfies the never-block requirement by construction.
/// `stop()` ends the loop gracefully and `run(_:)` returns to its caller
/// with the terminal restored; there is no `exit()` anywhere.
///
/// The window stack gives modal behavior for free: input routes only to the
/// top window, while all windows render in stack order (later windows
/// overdraw earlier ones).
@MainActor
public final class App {
    private let driver: any TerminalDriver
    private let timerSource: TimerSource

    /// Screen-sized root and background; windows are its subviews, so
    /// z-order and compositing reuse the ordinary view system. Style it
    /// directly (`app.desktop.theme`, `app.desktop.fillCharacter`) — its
    /// theme is also the inherited default for every window.
    public let desktop = Desktop()

    private let renderer: SceneRenderer

    /// Whether the run loop is active.
    public private(set) var isRunning = false

    /// Whether Control+C stops the application.
    ///
    /// Enabled by default so every TUIKit app is quittable before it wires
    /// its own commands. Disable for apps that handle it themselves.
    public var stopsOnControlC = true

    /// How long a completed click waits for a follow-up before its `.click`
    /// event is delivered. A second click within this window makes it a double
    /// (then a triple), so a single click's semantic event never fires ahead of
    /// a double. ~280 ms by default, matching desktop conventions.
    public var multiClickInterval: Duration = .milliseconds(280)

    /// Presented windows, bottom to top. The last window is key.
    public private(set) var windows: [Window] = []

    /// The window currently receiving input, when any.
    public var keyWindow: Window? {
        windows.last
    }

    /// Creates an application on a driver.
    ///
    /// - Parameters:
    ///   - driver: Terminal driver to run against.
    ///   - timerSource: Source of ticks for `addTimer(every:_:)`. Defaults
    ///     to the real clock; pass a `ManualTimerSource` in tests.
    public init(driver: any TerminalDriver, timerSource: TimerSource = ClockTimerSource()) {
        self.driver = driver
        self.timerSource = timerSource
        self.renderer = SceneRenderer(root: desktop)
    }

    // MARK: - Timers

    // Registered repeating timers.
    private var timers: [AppTimer] = []

    // The run loop's event sink while running (input + ticks merge here).
    private var eventContinuation: AsyncStream<LoopEvent>.Continuation?

    // MARK: - Multi-click tracking

    // Screen position of the current unreleased left press, for telling a click
    // (press + release at the same cell) from a drag.
    private var leftPressScreen: Point?

    // The click waiting out its guard interval: where it landed, which window
    // owns it, and how many clicks have stacked up (capped at 3).
    private var pendingClick: (window: Window, screen: Point, count: Int)?

    // The one-shot timer that delivers `pendingClick` once the guard elapses.
    private var clickGuardTimer: AppTimer?

    // Presses/releases beyond this many cells apart are a drag, not a click,
    // and clicks farther apart than this start a fresh count rather than
    // stacking into a double.
    private let clickSlop = 1

    // Nobody double-clicks past three (Apple's counter is unbounded, but real
    // UIs stop here: double = open, triple = select-all).
    private let maxClickCount = 3

    /// Registers a repeating timer that fires on the main thread inside the
    /// run loop, driving a frame present each tick.
    ///
    /// The timer starts immediately when the app is already running, or when
    /// `run(_:)` next starts. It never blocks — ticks arrive by suspension.
    ///
    /// - Parameters:
    ///   - interval: Time between ticks.
    ///   - repeats: Whether it keeps firing. A one-shot (`false`) cancels
    ///     itself after the first fire; prefer `schedule(after:_:)` for that.
    ///   - body: Called on each tick, on the `MainActor`.
    /// - Returns: The timer; call `cancel()` to stop it.
    @discardableResult
    public func addTimer(
        every interval: Duration,
        repeats: Bool = true,
        _ body: @escaping @MainActor () -> Void
    ) -> AppTimer {
        let timer = AppTimer(interval: interval, repeats: repeats, body: body)
        timer.onCancel = { [weak self] timer in
            self?.timers.removeAll { $0 === timer }
        }

        timers.append(timer)

        if let eventContinuation {
            startTimerTask(timer, into: eventContinuation)
        }

        return timer
    }

    /// Registers a one-shot timer that fires once after a delay, then cancels
    /// itself. A delayed action that never blocks the main thread.
    ///
    /// - Parameters:
    ///   - delay: How long to wait before firing.
    ///   - body: Called once, on the `MainActor`, inside the run loop.
    /// - Returns: The timer; call `cancel()` to fire nothing (e.g. if the
    ///   triggering condition passed before the delay elapsed).
    @discardableResult
    public func schedule(after delay: Duration, _ body: @escaping @MainActor () -> Void) -> AppTimer {
        addTimer(every: delay, repeats: false, body)
    }

    // Spawns the forwarding task that pumps a timer's ticks into the loop.
    private func startTimerTask(_ timer: AppTimer, into continuation: AsyncStream<LoopEvent>.Continuation) {
        let source = timerSource
        let interval = timer.interval

        timer.task = Task { [weak timer] in
            for await _ in source.ticks(every: interval) {
                guard let timer else {
                    break
                }

                continuation.yield(.tick(timer))
            }
        }
    }

    // MARK: - Window Stack

    /// Pushes a window onto the stack, making it key.
    ///
    /// A window presented with a zero frame fills the screen and follows
    /// resizes.
    ///
    /// - Parameter window: Window to present.
    public func present(_ window: Window) {
        if window.frame == .zero {
            window.fillsScreen = true
        }

        if window.fillsScreen {
            window.frame = desktop.bounds
        }

        windows.append(window)
        desktop.addSubview(window)
    }

    /// Removes a window from the stack.
    ///
    /// The window below it, if any, becomes key.
    ///
    /// - Parameter window: Window to dismiss.
    public func dismiss(_ window: Window) {
        windows.removeAll { $0 === window }
        window.removeFromSuperview()
    }

    /// Raises a presented window to the top of the stack, making it key.
    ///
    /// Clicking a non-modal stack does this automatically; call it directly
    /// for keyboard-driven window cycling.
    ///
    /// - Parameter window: Window to raise.
    public func activate(_ window: Window) {
        guard windows.contains(where: { $0 === window }), keyWindow !== window else {
            return
        }

        windows.removeAll { $0 === window }
        windows.append(window)
        desktop.addSubview(window)   // re-adding moves it to the front
    }

    // MARK: - Theme

    /// Themes the whole app in one call: the desktop background and every
    /// presented window.
    ///
    /// Themes cascade, so the desktop becomes the single app-wide anchor —
    /// every window's own override is cleared to `nil` so it inherits, and any
    /// window presented later inherits automatically too. Per-view overrides
    /// remain fully available: set `view.theme = …` (on a window *after* this
    /// call, or on any control) for a deliberate exception to the app theme.
    ///
    /// ```swift
    /// app.applyTheme(.homebrew)          // green-on-black, everywhere
    /// inspector.theme = .manPage         // …except this one pane
    /// ```
    ///
    /// - Parameter theme: Theme to apply across the app.
    public func applyTheme(_ theme: Theme) {
        desktop.theme = theme

        for window in windows {
            window.theme = nil
        }
    }

    // MARK: - Run Loop

    /// Requests a graceful stop.
    ///
    /// The loop exits when the current event finishes processing; `run(_:)`
    /// then restores the terminal and returns to its caller.
    public func stop() {
        isRunning = false
    }

    /// Runs the application until stopped.
    ///
    /// - Parameter window: Initial window to present.
    /// - Throws: Any driver startup error.
    public func run(_ window: Window) async throws {
        try await driver.begin()
        isRunning = true

        desktop.frame = Rect(origin: .zero, size: await driver.size)
        present(window)
        await presentFrameIfNeeded()

        // Merge driver input and timer ticks into one event stream so the
        // loop wakes on either and presents a frame after each — a tick
        // animates just like a keypress redraws.
        let (events, continuation) = AsyncStream<LoopEvent>.makeStream()
        eventContinuation = continuation

        let inputs = await driver.inputStream()
        let inputTask = Task {
            for await input in inputs {
                continuation.yield(.input(input))
            }
        }

        for timer in timers {
            startTimerTask(timer, into: continuation)
        }

        for await event in events {
            switch event {
            case .input(let input):
                handle(input)

            case .tick(let timer):
                if !timer.isCancelled {
                    timer.body()

                    if !timer.repeats {
                        timer.cancel()
                    }
                }
            }

            await presentFrameIfNeeded()

            if !isRunning {
                break
            }
        }

        inputTask.cancel()

        for timer in timers {
            timer.task?.cancel()
            timer.task = nil
        }

        eventContinuation = nil
        isRunning = false
        await driver.end()
    }

    // One thing the run loop can wake on.
    private enum LoopEvent {
        case input(TerminalInput)
        case tick(AppTimer)
    }

    // Routes one event.
    private func handle(_ input: TerminalInput) {
        switch input {
        case .resize(let size):
            applyScreenSize(size)

        case .key(let key):
            if stopsOnControlC,
               key.key == .character("c"),
               key.modifiers == .control {
                stop()
                return
            }

            keyWindow?.route(input)

        case .mouse(var mouse):
            guard let key = keyWindow else {
                return
            }

            // The untranslated screen position, kept for click tracking below.
            let screen = mouse.position

            // A press outside an open menu / pop-up / context menu dismisses it
            // first — even when the press lands on the desktop or another window
            // (the overlay's own window would never see that press otherwise).
            // The press then routes normally, so it still lands where it points.
            if mouse.action == .press, mouse.button == .left {
                key.dismissOverlayIfPressOutside(mouse.position - key.frame.origin)
            }

            var window = key

            // Click-to-activate: in a non-modal stack, pressing a window
            // that isn't key raises it and makes it key — the press then
            // routes to it (activate-and-forward). A modal key window
            // swallows outside clicks instead (the classic dialog rule).
            //
            // Targeting is by hit test, not frame, so windows that claim
            // only part of their frame (a menu-bar strip window, say) are
            // click-through everywhere else.
            if mouse.action == .press,
               mouse.button == .left,
               !key.isModal,
               let target = windows.last(where: { window in
                   window.hitTest(mouse.position - window.frame.origin) != nil
               }),
               target !== key {
                activate(target)
                window = target
            }

            // Translate screen coordinates into the window's space; outside
            // clicks that activated nothing are simply rejected by the hit
            // test.
            mouse.position = mouse.position - window.frame.origin
            window.route(.mouse(mouse))

            // Fold this press/release into the multi-click count. Runs after
            // routing, so selection (on press) stays instant; only the debounced
            // `.click` waits out the guard.
            trackClick(action: mouse.action, button: mouse.button, screen: screen, window: window)
        }
    }

    // Turns a stream of left presses/releases into debounced `.click` events.
    // A press remembers where it landed; a release at the same cell completes a
    // click, which either extends the pending sequence (a nearby click still
    // inside the guard window → double, then triple) or starts a new one. Each
    // completed click (re)arms the guard timer; when it fires, the click is
    // delivered with its final count. A drag (release far from the press)
    // breaks the sequence.
    private func trackClick(action: MouseInput.Action, button: MouseInput.Button, screen: Point, window: Window) {
        guard button == .left else {
            return
        }

        switch action {
        case .press:
            leftPressScreen = screen

        case .release:
            guard let pressed = leftPressScreen else {
                return
            }
            leftPressScreen = nil

            guard manhattan(pressed, screen) <= clickSlop else {
                // A drag, not a click — abandon any pending sequence.
                clickGuardTimer?.cancel()
                clickGuardTimer = nil
                pendingClick = nil
                return
            }

            var count = 1
            if let pending = pendingClick, manhattan(pending.screen, screen) <= clickSlop {
                count = min(maxClickCount, pending.count + 1)
            }

            clickGuardTimer?.cancel()
            pendingClick = (window: window, screen: screen, count: count)
            clickGuardTimer = schedule(after: multiClickInterval) { [weak self] in
                self?.deliverPendingClick()
            }

        default:
            break
        }
    }

    // Routes the settled click to the window it landed on, with its final count.
    private func deliverPendingClick() {
        clickGuardTimer = nil

        guard let pending = pendingClick else {
            return
        }
        pendingClick = nil

        // The window may have been dismissed during the guard interval.
        guard windows.contains(where: { $0 === pending.window }) else {
            return
        }

        let local = pending.screen - pending.window.frame.origin
        let click = MouseInput(position: local, action: .click, button: .left, clickCount: pending.count)
        pending.window.route(.mouse(click))
    }

    private func manhattan(_ a: Point, _ b: Point) -> Int {
        abs(a.x - b.x) + abs(a.y - b.y)
    }

    private func applyScreenSize(_ size: Size) {
        desktop.frame = Rect(origin: .zero, size: size)

        for window in windows where window.fillsScreen {
            window.frame = desktop.bounds
        }

        // Maximized floating windows track the new desktop size too.
        for window in windows {
            (window as? FloatingWindow)?.reflowMaximizeIfNeeded()
        }
    }

    // Renders and presents a frame when anything changed.
    private func presentFrameIfNeeded() async {
        let size = desktop.frame.size

        guard let frame = renderer.renderIfNeeded(size: size) else {
            return
        }

        await driver.present(frame)
    }
}
