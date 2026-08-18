/// Cursor state a driver should reflect on the terminal.
public struct TerminalCursor: Hashable, Sendable {
    /// Cursor position in cell coordinates.
    public var position: Point

    /// Whether the cursor is visible.
    public var isVisible: Bool

    /// A hidden cursor at the origin.
    public static let hidden = TerminalCursor(position: .zero, isVisible: false)

    /// Creates a cursor state.
    ///
    /// - Parameters:
    ///   - position: Cursor position in cell coordinates.
    ///   - isVisible: Whether the cursor is visible.
    public init(position: Point, isVisible: Bool = true) {
        self.position = position
        self.isVisible = isVisible
    }
}

/// The boundary between TUIKit and an actual terminal.
///
/// Everything terminal-specific — raw mode, escape sequences, size probing,
/// input decoding — lives behind this protocol. Everything above it deals in
/// `CellBuffer` out and `TerminalInput` in, which is what makes the rest of
/// the framework deterministic and testable.
///
/// Two implementations are planned for v1: `ANSIDriver` for real terminals
/// on macOS and Linux, and `HeadlessDriver` for tests and automation.
public protocol TerminalDriver: Sendable {
    /// Current terminal size in cells.
    var size: Size { get async }

    /// Prepares the terminal for full-screen cell rendering.
    ///
    /// For real terminals this enters raw mode, switches to the alternate
    /// screen, and hides the cursor. Calling `begin()` twice is an error.
    ///
    /// - Throws: Any error that prevents terminal setup.
    func begin() async throws

    /// Restores the terminal to its previous state.
    ///
    /// Always safe to call; drivers must tolerate `end()` without a
    /// successful `begin()` so cleanup paths can be unconditional.
    func end() async

    /// Presents a fully composed buffer on the terminal.
    ///
    /// The driver owns diffing: it may redraw everything or only what
    /// changed since the last presentation, but the visible result must
    /// equal the buffer.
    ///
    /// - Parameter buffer: Composed cells to display.
    func present(_ buffer: CellBuffer) async

    /// Updates the terminal cursor.
    ///
    /// - Parameter cursor: Cursor position and visibility.
    func setCursor(_ cursor: TerminalCursor) async

    /// The stream of decoded input events.
    ///
    /// The stream finishes when the driver ends or the terminal goes away.
    ///
    /// - Returns: Stream of decoded terminal input.
    func inputStream() async -> AsyncStream<TerminalInput>

    /// Hands text to the terminal's clipboard, when the terminal supports it.
    ///
    /// `ANSIDriver` emits OSC 52, which modern terminals (Terminal.app,
    /// iTerm2, kitty, …) apply to the system clipboard — including over ssh.
    /// The default implementation does nothing, so drivers without a
    /// clipboard story remain valid; the in-process `Pasteboard` keeps
    /// working either way.
    ///
    /// - Parameter text: Text to place on the clipboard.
    func setClipboard(_ text: String) async

    /// Whether the terminal can draw vector chrome (Phase 10).
    ///
    /// Meaningful only after `begin()` — `ANSIDriver` probes VectorTerminal
    /// Graphics capabilities during setup. `false` (the default) means the
    /// app renders cells exactly as it always has; chrome is purely additive
    /// and no driver is required to support it.
    var supportsGraphicsChrome: Bool { get async }

    /// What the graphics plane can do, when there is one.
    ///
    /// `nil` on a driver with no graphics plane, matching
    /// `supportsGraphicsChrome == false`. Defaulted, so a driver written
    /// before this existed keeps compiling and answers the honest "I have not
    /// been asked" — which for a driver with a plane is the baseline set
    /// rather than nothing.
    var graphicsCapabilities: GraphicsCapabilities? { get async }

    /// Presents one frame of vector chrome alongside the cell buffer.
    ///
    /// Called after `present(_:)` with the frame's full command list; the
    /// driver owns retained-scene reconciliation (updating shapes in place,
    /// deleting shapes that vanished). The default implementation does
    /// nothing, matching `supportsGraphicsChrome == false`.
    ///
    /// - Parameter commands: The frame's chrome, in draw order.
    func presentChrome(_ commands: [ChromeCommand]) async

    /// Temporarily gives the terminal back, so another program can own it.
    ///
    /// This is `end()` without the finality: raw mode, the alternate screen,
    /// and mouse reporting are undone and input handling stops, but the input
    /// stream stays OPEN and the run loop stays alive — so a later
    /// ``resume()`` picks up where this left off. Ending the input stream
    /// here (as `end()` does) would tear down the loop that is waiting to
    /// come back.
    ///
    /// Lets an app hand its real TTY to a child process — a shell, an editor,
    /// another full-screen program — and take it back when the child exits.
    /// See `App.suspended(_:)`, which sequences this correctly.
    ///
    /// The default implementation does nothing, which is right for drivers
    /// that never owned a terminal (`HeadlessDriver`).
    func suspend() async

    /// Retakes the terminal after ``suspend()``.
    ///
    /// Re-enters raw mode and the alternate screen, re-measures the window
    /// (the user may have resized it while away), and restarts input.
    /// Callers must redraw: the child scribbled over the screen.
    func resume() async
}

extension TerminalDriver {
    /// Default: the baseline set when there IS a graphics plane, and nil when
    /// there is not.
    ///
    /// A driver written before this existed therefore keeps working and says
    /// something true: it draws images, and nothing optional has been
    /// established. Nobody has to update a driver to keep compiling.
    public var graphicsCapabilities: GraphicsCapabilities? {
        get async {
            await supportsGraphicsChrome ? .baseline : nil
        }
    }

    /// Default: nothing to give back.
    public func suspend() async {}

    /// Default: nothing to retake.
    public func resume() async {}
}

extension TerminalDriver {
    /// Default: no system clipboard; the in-process pasteboard still works.
    public func setClipboard(_ text: String) async {}

    /// Default: no vector chrome; cells are the whole presentation.
    public var supportsGraphicsChrome: Bool { false }

    /// Default: chrome commands are ignored.
    public func presentChrome(_ commands: [ChromeCommand]) async {}
}
