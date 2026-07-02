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

    // Screen-sized root; windows are its subviews, so z-order and
    // compositing reuse the ordinary view system.
    private let screenRoot = View()
    private let renderer: SceneRenderer

    /// Whether the run loop is active.
    public private(set) var isRunning = false

    /// Whether Control+C stops the application.
    ///
    /// Enabled by default so every TUIKit app is quittable before it wires
    /// its own commands. Disable for apps that handle it themselves.
    public var stopsOnControlC = true

    /// Presented windows, bottom to top. The last window is key.
    public private(set) var windows: [Window] = []

    /// The window currently receiving input, when any.
    public var keyWindow: Window? {
        windows.last
    }

    /// Creates an application on a driver.
    ///
    /// - Parameter driver: Terminal driver to run against.
    public init(driver: any TerminalDriver) {
        self.driver = driver
        self.renderer = SceneRenderer(root: screenRoot)
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
            window.frame = screenRoot.bounds
        }

        windows.append(window)
        screenRoot.addSubview(window)
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

        screenRoot.frame = Rect(origin: .zero, size: await driver.size)
        present(window)
        await presentFrameIfNeeded()

        for await input in await driver.inputStream() {
            handle(input)
            await presentFrameIfNeeded()

            if !isRunning {
                break
            }
        }

        isRunning = false
        await driver.end()
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
            guard let window = keyWindow else {
                return
            }

            // Translate screen coordinates into the key window's space; the
            // top window owns input even for outside clicks (modal rule),
            // which its hit test will simply reject.
            mouse.position = mouse.position - window.frame.origin
            window.route(.mouse(mouse))
        }
    }

    private func applyScreenSize(_ size: Size) {
        screenRoot.frame = Rect(origin: .zero, size: size)

        for window in windows where window.fillsScreen {
            window.frame = screenRoot.bounds
        }
    }

    // Renders and presents a frame when anything changed.
    private func presentFrameIfNeeded() async {
        let size = screenRoot.frame.size

        guard let frame = renderer.renderIfNeeded(size: size) else {
            return
        }

        await driver.present(frame)
    }
}
