import Foundation

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

    /// Whether the app has handed the terminal to another program.
    ///
    /// True only for the duration of ``suspended(_:)``. The run loop is still
    /// alive; it just has the screen taken away from it.
    public private(set) var isSuspended = false

    /// Whether the terminal draws vector chrome this run (Phase 10).
    ///
    /// Set once per `run(_:)` from the driver's begin-time probe. On, views
    /// decorate themselves through `painter.chrome` and themes' `vector`
    /// styling applies; off, rendering is the classic cell pipeline. Apps
    /// cannot opt in — the terminal either supports it or it doesn't.
    public private(set) var isVectorChromeActive = false

    /// Whether Control+C stops the application.
    ///
    /// Enabled by default so every TUIKit app is quittable before it wires
    /// its own commands. Disable for apps that handle it themselves.
    public var stopsOnControlC = true

    /// How long a completed click waits for a follow-up before its `.click`
    /// event is delivered. A second click within this window makes it a double
    /// (then a triple), so a single click's semantic event never fires ahead of
    /// a double.
    ///
    /// 420 ms — half again longer than the 280 ms desktop convention, and the
    /// difference is the terminal. A window manager sees the second press the
    /// moment it happens; here it has to travel as bytes through a tty, be
    /// read by whatever is polling, and be decoded, and the slack in that
    /// path is enough that a real double-click regularly arrived as two
    /// singles. The cost of the longer window is that a genuine single click
    /// acts 140 ms later; the cost of the shorter one was that double-click
    /// mostly did not work.
    public var multiClickInterval: Duration = .milliseconds(420)

    /// ``multiClickInterval`` in milliseconds, for hosts that would rather
    /// think in numbers than in `Duration`s.
    public var multiClickIntervalMilliseconds: Int {
        get {
            let components = multiClickInterval.components
            return Int(components.seconds * 1_000 + components.attoseconds / 1_000_000_000_000_000)
        }
        set {
            multiClickInterval = .milliseconds(max(0, newValue))
        }
    }

    /// How long a left press must hold still before it becomes a
    /// `.longPress`. 600 ms — long enough that a slow click (which the
    /// 420 ms multi-click window already accommodates) does not trip it,
    /// short enough to feel like a gesture rather than a wait.
    public var longPressInterval: Duration = .milliseconds(600)

    /// ``longPressInterval`` in milliseconds, for hosts that would rather
    /// think in numbers than in `Duration`s.
    public var longPressIntervalMilliseconds: Int {
        get {
            let components = longPressInterval.components
            return Int(components.seconds * 1_000 + components.attoseconds / 1_000_000_000_000_000)
        }
        set {
            longPressInterval = .milliseconds(max(0, newValue))
        }
    }

    /// The application clipboard. Cut/copy/paste in editing controls flow
    /// through here; copies are forwarded to the terminal's system clipboard
    /// when the driver supports it (OSC 52 on `ANSIDriver`).
    public let pasteboard = Pasteboard()

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

        // Copies flow to the terminal's clipboard, best-effort, off-loop.
        pasteboard.systemSink = { text in
            Task {
                await driver.setClipboard(text)
            }
        }
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

    // MARK: - Long-press tracking

    // The one-shot timer armed by a left press; firing delivers `.longPress`.
    private var longPressTimer: AppTimer?

    // Whether the current press already became a long-press, so its release
    // must not also become a click.
    private var longPressDelivered = false

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

        window.app = self
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
        StopTrace.log("App.stop() — isRunning was \(isRunning)")
        isRunning = false

        // Wake the loop. It checks `isRunning` only after handling an event,
        // so a stop from OUTSIDE event processing — a timer body, a task
        // finishing, a child process exiting — would otherwise leave it
        // parked on `for await` forever with nothing left to deliver.
        eventContinuation?.finish()
    }

    /// Hands the terminal to another program, then takes it back.
    ///
    /// The app's UI disappears, `body` runs owning the real TTY — so a child
    /// process spawned with inherited stdio behaves exactly as it would from
    /// a shell, full-screen programs included — and afterwards the app
    /// redraws over whatever the child left on screen.
    ///
    /// ```swift
    /// await app.suspended {
    ///     try? await shellOut("vim", "notes.txt")
    /// }
    /// ```
    ///
    /// The run loop stays alive throughout; input events simply stop arriving
    /// while suspended. Re-entrant calls are ignored (the terminal can only
    /// be handed over once). With a driver that owns no terminal
    /// (`HeadlessDriver`), this is just `body` — which is what makes the
    /// behavior testable.
    ///
    /// - Parameter body: Runs while the app is off the screen, on the
    ///   `MainActor` — like the timer callbacks, and so callers can touch
    ///   their UI state around the handover without hopping actors.
    public func suspended(_ body: @MainActor () async -> Void) async {
        guard !isSuspended else {
            await body()
            return
        }

        isSuspended = true
        await driver.suspend()
        await body()
        await driver.resume()

        // The child owned the screen, and the window may have been resized
        // while it did: re-measure, then repaint everything rather than
        // trusting what the renderer last believed was on screen.
        desktop.frame = Rect(origin: .zero, size: await driver.size)
        desktop.setNeedsLayout()
        desktop.refresh()   // every descendant, not just what changed
        isSuspended = false

        await presentFrameIfNeeded()
    }

    /// Runs the application until stopped.
    ///
    /// - Parameter window: Initial window to present.
    /// - Throws: Any driver startup error.
    public func run(_ window: Window) async throws {
        try await driver.begin()
        isRunning = true

        // The driver probed for VectorTerminal Graphics during begin();
        // chrome-enabled rendering follows its answer for the whole run.
        isVectorChromeActive = await driver.supportsGraphicsChrome
        renderer.chromeEnabled = isVectorChromeActive

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

            case .wake:
                wakePending = false
            }

            await presentFrameIfNeeded()

            if !isRunning {
                break
            }
        }

        StopTrace.log("run loop exited")
        inputTask.cancel()

        for timer in timers {
            timer.task?.cancel()
            timer.task = nil
        }

        eventContinuation = nil
        isRunning = false
        StopTrace.log("teardown: awaiting driver.end()")
        await driver.end()
        StopTrace.log("teardown: driver.end() returned — run(_:) returning")
    }

    // One thing the run loop can wake on.
    private enum LoopEvent {
        case input(TerminalInput)
        case tick(AppTimer)

        /// Nothing happened *to* the app — something changed inside it. Carries
        /// no payload; its only job is to wake the loop so the frame after it
        /// gets presented.
        case wake
    }

    // Whether a wake is already queued. Without this every `setNeedsDisplay`
    // in a busy layout pass would push its own event, and a page finishing
    // would queue thousands of them to present one frame.
    private var wakePending = false

    /// Asks for a frame to be presented, from outside the event loop.
    ///
    /// The loop presents after each event it handles, so work that finishes on
    /// its own — a page load, a subprocess, a task — marks its views dirty and
    /// then waits for a keystroke that may never come. Views call this through
    /// `setNeedsDisplay`; call it directly after changing something the loop
    /// cannot see.
    public func requestFrame() {
        // The continuation is required, not optional-chained: it does not exist
        // until `run` builds the event stream, and a request before then would
        // otherwise set the flag and yield into nothing — latching it true for
        // the life of the app and swallowing every wake that mattered.
        guard isRunning, !wakePending, let continuation = eventContinuation else {
            return
        }

        wakePending = true
        continuation.yield(.wake)
    }

    // Routes one event.
    private func handle(_ input: TerminalInput) {
        switch input {
        case .resize(let size):
            applyScreenSize(size)

        case .key(let key):
            // With tracing on, every decoded key is a breadcrumb: a quit
            // report whose trace shows the key arriving is a stop/teardown
            // problem; one whose trace shows nothing is a deaf-input one.
            StopTrace.log("key decoded: \(key.key) modifiers \(key.modifiers.rawValue)")

            if stopsOnControlC,
               key.key == .character("c"),
               key.modifiers == .control {
                stop()
                return
            }

            if keyWindow?.route(input) == true {
                return
            }

            // Unconsumed by the focused window. Keyboard input routes only to
            // the key window, but a menu bar usually lives somewhere else — on
            // the chrome window under the floating ones — so its accelerators
            // would stop working the moment any window took focus. Offer the
            // key to the other windows' accelerators, nearest first, so the
            // bar that declares a command still fires it.
            //
            // Accelerators only (`routeHotKey`), never the full chain: a
            // background window must not receive keystrokes meant for the
            // focused one.
            for window in windows.reversed() where window !== keyWindow {
                if window.routeHotKey(key) {
                    return
                }
            }

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

            // Hold the guard while the button is DOWN. Without this the timer
            // could fire mid-sequence — armed by the previous release, expiring
            // while the next click was still being held — and deliver the click
            // early with the lower count. The rest of the sequence then started
            // over, so a triple click arrived as a double and a double as two
            // singles, exactly as if the window were too short. It was not: a
            // slow press was simply escaping it.
            //
            // `pendingClick` is deliberately kept: the sequence is continuing,
            // and the release below will extend it.
            clickGuardTimer?.cancel()
            clickGuardTimer = nil

            // Arm the long-press clock: a press that holds still past the
            // interval becomes a `.longPress` while the button is down.
            //
            // FRESH presses only. A press continuing a same-spot click
            // sequence (a slow double- or triple-click) must never become a
            // long-press mid-sequence — the guard's whole promise is that a
            // click still under the finger is not a gesture yet
            // (`aSlowClickCannotEscapeTheGuardMidSequence`). So a hold reads
            // as a long-press only once the previous click has settled.
            longPressDelivered = false
            longPressTimer?.cancel()
            longPressTimer = nil

            if pendingClick == nil || manhattan(pendingClick!.screen, screen) > clickSlop {
                longPressTimer = schedule(after: longPressInterval) { [weak self, weak window] in
                    guard let window else {
                        return
                    }

                    self?.deliverLongPress(screen: screen, window: window)
                }
            }

        case .drag:
            // Movement past the slop is a drag, and a drag is not a hold.
            if longPressTimer != nil, let pressed = leftPressScreen,
               manhattan(pressed, screen) > clickSlop {
                longPressTimer?.cancel()
                longPressTimer = nil
            }

        case .release:
            // Whatever else the release means, the hold is over.
            longPressTimer?.cancel()
            longPressTimer = nil

            guard let pressed = leftPressScreen else {
                return
            }
            leftPressScreen = nil

            // A long-press already consumed this gesture: its release must
            // not also become a click (that would run the tap action right
            // after the long-press one).
            if longPressDelivered {
                longPressDelivered = false
                return
            }

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

    // The press held still past the interval: deliver `.longPress` to the
    // window it landed on. The window gives the pressed view first refusal,
    // then falls back to the nearest context menu — and cancels the mouse
    // grab either way, so the eventual release cannot activate anything.
    private func deliverLongPress(screen: Point, window: Window) {
        longPressTimer = nil

        // The window may have been dismissed while the press was held.
        guard windows.contains(where: { $0 === window }) else {
            return
        }

        let local = screen - window.frame.origin
        let consumed = window.route(.mouse(MouseInput(position: local, action: .longPress, button: .left)))

        // Only a CONSUMED long-press ends the gesture (and breaks any
        // multi-click sequence — nobody click-click-HOLDS for a double).
        // Unconsumed, nothing anywhere reacted, and the hold must stay what
        // it always was: a slow click, delivered in full on release.
        if consumed {
            longPressDelivered = true
            pendingClick = nil
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

        // Chrome rides every cell frame; the driver skips identical frames.
        if isVectorChromeActive {
            await driver.presentChrome(renderer.chromeCommands)
        }
    }
}

/// Shutdown breadcrumbs for diagnosing "quit didn't quit" reports from
/// terminals we cannot reproduce locally (set `TUIKIT_STOP_TRACE=/path`).
///
/// The first question such a report needs answered is WHICH half failed:
/// no lines at all when the quit key was pressed means the key never
/// decoded (the app is deaf — an input/decoder problem); `App.stop()`
/// logged but `driver.end() returned` missing means the teardown hung
/// (a driver problem). A no-op — not even a getenv per call is avoided,
/// but zero I/O — unless the variable is set.
enum StopTrace {
    nonisolated static func log(_ message: String) {
        guard let path = ProcessInfo.processInfo.environment["TUIKIT_STOP_TRACE"] else {
            return
        }

        let line = "[\(Date())] \(message)\n"

        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? line.write(toFile: path, atomically: false, encoding: .utf8)
        }
    }
}
