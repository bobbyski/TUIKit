/// In-memory terminal driver for tests and automation.
///
/// The headless driver is a first-class citizen, not a mock: it implements
/// the full `TerminalDriver` contract against an in-memory buffer, accepts
/// scripted input through `send(_:)`, and exposes what was presented through
/// `presentedBuffer` / `snapshotText()`. Every view, control, and app in
/// TUIKit is expected to run — and be asserted on — through this driver in
/// CI, with no TTY anywhere.
///
/// ```swift
/// let driver = HeadlessDriver(size: Size(width: 80, height: 24))
/// // ... run something that presents ...
/// await driver.send(.key(KeyInput(key: .enter)))
/// #expect(await driver.snapshotText().first?.contains("Title") == true)
/// ```
public actor HeadlessDriver: TerminalDriver {
    /// Errors produced by the headless driver.
    public enum DriverError: Error, Equatable, Sendable {
        /// `begin()` was called while the driver was already active.
        case alreadyBegan
    }

    private var currentSize: Size
    private var isActive = false
    private var lastPresented: CellBuffer?
    private var lastCursor: TerminalCursor = .hidden
    private var presentationCount = 0
    private var inputContinuations: [Int: AsyncStream<TerminalInput>.Continuation] = [:]
    private var nextContinuationID = 0
    private let graphicsChrome: Bool
    private var lastChrome: [ChromeCommand] = []
    private var chromePresentationCount = 0

    /// Creates a headless driver.
    ///
    /// - Parameters:
    ///   - size: Simulated terminal size.
    ///   - supportsGraphicsChrome: Whether to simulate a VTG terminal
    ///     (Phase 10). On, presented chrome commands are recorded for
    ///     assertion; off (the default), the app renders cells only —
    ///     exactly the plain-terminal fallback.
    public init(
        size: Size = Size(width: 80, height: 24),
        supportsGraphicsChrome: Bool = false,
        graphicsCapabilities: GraphicsCapabilities? = nil
    ) {
        self.pinnedCapabilities = graphicsCapabilities
        self.currentSize = size
        self.graphicsChrome = supportsGraphicsChrome
    }

    // MARK: - TerminalDriver

    /// Current simulated terminal size.
    public var size: Size {
        currentSize
    }

    /// Marks the driver active.
    ///
    /// - Throws: `DriverError.alreadyBegan` when already active.
    public func begin() throws {
        guard !isActive else {
            throw DriverError.alreadyBegan
        }

        isActive = true
    }

    /// Marks the driver inactive and finishes all input streams.
    public func end() {
        isActive = false

        for continuation in inputContinuations.values {
            continuation.finish()
        }

        inputContinuations.removeAll()
    }

    /// Records a presented buffer.
    ///
    /// - Parameter buffer: Composed cells to record.
    public func present(_ buffer: CellBuffer) {
        lastPresented = buffer
        presentationCount += 1
    }

    /// Records the cursor state.
    ///
    /// - Parameter cursor: Cursor position and visibility.
    public func setCursor(_ cursor: TerminalCursor) {
        lastCursor = cursor
    }

    /// Creates a stream of scripted input events.
    ///
    /// Multiple streams may exist; every stream receives every event sent
    /// after its creation. Streams finish when the driver ends.
    ///
    /// - Returns: Stream of scripted terminal input.
    public func inputStream() -> AsyncStream<TerminalInput> {
        AsyncStream { continuation in
            let id = nextContinuationID
            nextContinuationID += 1
            inputContinuations[id] = continuation

            continuation.onTermination = { _ in
                Task { [weak self] in
                    await self?.removeContinuation(id)
                }
            }
        }
    }

    /// Records clipboard text so tests can assert on system-copy behavior.
    ///
    /// - Parameter text: Text "copied to the system clipboard".
    public func setClipboard(_ text: String) {
        lastClipboard = text
    }

    /// Whether this driver simulates a VTG terminal (set at creation).
    /// The capability set tests pinned, or the baseline when a graphics
    /// plane was simulated without one being named.
    public var graphicsCapabilities: GraphicsCapabilities? {
        get async {
            guard graphicsChrome else {
                return nil
            }

            return pinnedCapabilities ?? .baseline
        }
    }

    // What a test said the terminal can do.
    private let pinnedCapabilities: GraphicsCapabilities?

    public var supportsGraphicsChrome: Bool {
        graphicsChrome
    }

    /// Records a presented chrome frame, when simulating a VTG terminal.
    ///
    /// - Parameter commands: The frame's chrome, in draw order.
    public func presentChrome(_ commands: [ChromeCommand]) {
        guard graphicsChrome else {
            return
        }

        lastChrome = commands
        chromePresentationCount += 1
    }

    // Most recent setClipboard payload.
    private var lastClipboard: String?

    // MARK: - Test Controls

    /// The most recent text handed to `setClipboard(_:)`, when any.
    public var clipboard: String? {
        lastClipboard
    }

    /// Injects one input event into all active input streams.
    ///
    /// - Parameter input: Event to inject.
    public func send(_ input: TerminalInput) {
        for continuation in inputContinuations.values {
            continuation.yield(input)
        }
    }

    /// Changes the simulated terminal size and reports it as input.
    ///
    /// - Parameter size: New simulated size.
    public func resize(to size: Size) {
        currentSize = size
        send(.resize(size))
    }

    /// The most recently presented buffer, when any.
    public var presentedBuffer: CellBuffer? {
        lastPresented
    }

    /// The most recently presented chrome frame (empty before the first, or
    /// when the driver is not simulating a VTG terminal).
    public var presentedChrome: [ChromeCommand] {
        lastChrome
    }

    /// Number of times `presentChrome(_:)` recorded a frame.
    public var chromePresentCount: Int {
        chromePresentationCount
    }

    /// Number of times `present(_:)` has been called.
    public var presentCount: Int {
        presentationCount
    }

    /// The most recently set cursor state.
    public var cursor: TerminalCursor {
        lastCursor
    }

    /// Whether the driver is between `begin()` and `end()`.
    public var isRunning: Bool {
        isActive
    }

    /// The most recently presented buffer, cells and all.
    ///
    /// `snapshotText()` throws styling away, which hides anything drawn as a
    /// coloured space — scrollbars, selection on blank lines, gutter bands.
    /// Tests that care about those need the cells.
    ///
    /// - Returns: The buffer, or nil before the first presentation.
    public func snapshotBuffer() -> CellBuffer? {
        lastPresented
    }

    /// Plain-text projection of the most recently presented buffer.
    ///
    /// - Returns: One string per row, or an empty array before the first
    ///   presentation.
    public func snapshotText() -> [String] {
        lastPresented?.textLines() ?? []
    }

    private func removeContinuation(_ id: Int) {
        inputContinuations[id] = nil
    }
}
