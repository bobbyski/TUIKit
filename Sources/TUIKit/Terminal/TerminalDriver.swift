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
}
