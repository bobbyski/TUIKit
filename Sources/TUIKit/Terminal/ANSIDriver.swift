import Dispatch
import Foundation

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Terminal driver for real ANSI/VT terminals on macOS and Linux.
///
/// The driver owns all terminal state: raw mode via termios, the alternate
/// screen, cursor visibility, SGR mouse reporting, size probing, and
/// SIGWINCH resize handling. Bytes are read through a non-blocking file
/// descriptor and a `DispatchSourceRead` — never a synchronous `read()` on a
/// calling thread — and decoded by the pure `ANSIInputDecoder`, honoring the
/// framework's never-block requirement. Output writes happen on a dedicated
/// dispatch queue behind `await`, so no cooperative thread ever blocks on
/// terminal I/O.
///
/// v1 presents with a full redraw per frame; damage-based diffing can land
/// later behind the same `present(_:)` contract.
public actor ANSIDriver: TerminalDriver {
    /// Errors produced by the ANSI driver.
    public enum DriverError: Error, Equatable, Sendable {
        /// `begin()` was called while the driver was already active.
        case alreadyBegan

        /// Standard input/output is not a terminal.
        case notATerminal
    }

    private let inputDescriptor: Int32 = STDIN_FILENO
    private let outputDescriptor: Int32 = STDOUT_FILENO
    private let outputQueue = DispatchQueue(label: "tuikit.ansidriver.output")
    private let inputQueue = DispatchQueue(label: "tuikit.ansidriver.input")

    private var originalTermios: termios?
    private var decoder = ANSIInputDecoder()
    private var readSource: (any DispatchSourceRead)?
    private var resizeSource: (any DispatchSourceSignal)?
    private var continuations: [Int: AsyncStream<TerminalInput>.Continuation] = [:]
    private var nextContinuationID = 0
    private var currentSize = Size(width: 80, height: 24)
    private var isActive = false
    private var escapeGeneration = 0

    /// Creates an ANSI driver bound to standard input and output.
    public init() {}

    // MARK: - TerminalDriver

    /// Current terminal size in cells.
    public var size: Size {
        currentSize
    }

    /// Enters raw mode, switches to the alternate screen, and starts the
    /// asynchronous input pipeline.
    ///
    /// - Throws: `DriverError.notATerminal` when stdin/stdout is not a TTY,
    ///   or `DriverError.alreadyBegan` when already active.
    public func begin() async throws {
        guard !isActive else {
            throw DriverError.alreadyBegan
        }

        guard isatty(inputDescriptor) == 1, isatty(outputDescriptor) == 1 else {
            throw DriverError.notATerminal
        }

        var raw = termios()
        tcgetattr(inputDescriptor, &raw)
        originalTermios = raw
        cfmakeraw(&raw)
        tcsetattr(inputDescriptor, TCSANOW, &raw)

        // Non-blocking reads: the dispatch source tells us when bytes exist,
        // and the read call itself can never park a thread.
        let flags = fcntl(inputDescriptor, F_GETFL)
        _ = fcntl(inputDescriptor, F_SETFL, flags | O_NONBLOCK)

        isActive = true

        // Alternate screen, hidden cursor, SGR mouse reporting.
        await write("\u{1B}[?1049h\u{1B}[?25l\u{1B}[?1002h\u{1B}[?1006h\u{1B}[2J\u{1B}[H")

        // Probe AFTER switching to the alternate screen: it reflects the full
        // window, whereas a probe on a normal screen with heavy scrollback can
        // report a reduced content area.
        currentSize = Self.probeSize(descriptor: outputDescriptor) ?? currentSize

        startReadSource()
        startResizeSource()
    }

    /// Restores the terminal and stops the input pipeline.
    ///
    /// Safe to call unconditionally, including after a failed `begin()`.
    public func end() async {
        readSource?.cancel()
        readSource = nil
        resizeSource?.cancel()
        resizeSource = nil

        if isActive {
            // Disable mouse, show cursor, leave the alternate screen.
            await write("\u{1B}[?1006l\u{1B}[?1002l\u{1B}[?25h\u{1B}[?1049l")
        }

        if var original = originalTermios {
            tcsetattr(inputDescriptor, TCSANOW, &original)
            originalTermios = nil
        }

        isActive = false

        for continuation in continuations.values {
            continuation.finish()
        }

        continuations.removeAll()
    }

    /// Presents a buffer with a full redraw.
    ///
    /// - Parameter buffer: Composed cells to display.
    public func present(_ buffer: CellBuffer) async {
        var frame = ""
        let lines = ANSIEncoder.encode(buffer)

        for (row, line) in lines.enumerated() {
            frame += "\u{1B}[\(row + 1);1H" + line
        }

        await write(frame)
    }

    /// Updates the terminal cursor.
    ///
    /// - Parameter cursor: Cursor position and visibility.
    public func setCursor(_ cursor: TerminalCursor) async {
        var sequence = "\u{1B}[\(cursor.position.y + 1);\(cursor.position.x + 1)H"
        sequence += cursor.isVisible ? "\u{1B}[?25h" : "\u{1B}[?25l"
        await write(sequence)
    }

    /// Creates a stream of decoded input events.
    ///
    /// Streams finish when the driver ends.
    ///
    /// - Returns: Stream of decoded terminal input.
    public func inputStream() -> AsyncStream<TerminalInput> {
        AsyncStream { continuation in
            let id = nextContinuationID
            nextContinuationID += 1
            continuations[id] = continuation

            continuation.onTermination = { _ in
                Task { [weak self] in
                    await self?.removeContinuation(id)
                }
            }
        }
    }

    // MARK: - Input Pipeline

    // Starts the dispatch source that feeds decoder input.
    private func startReadSource() {
        let source = DispatchSource.makeReadSource(
            fileDescriptor: inputDescriptor,
            queue: inputQueue
        )

        let descriptor = inputDescriptor

        source.setEventHandler { [weak self] in
            var bytes: [UInt8] = []
            var chunk = [UInt8](repeating: 0, count: 512)

            while true {
                let count = read(descriptor, &chunk, chunk.count)

                guard count > 0 else {
                    break
                }

                bytes.append(contentsOf: chunk[0..<count])
            }

            guard !bytes.isEmpty else {
                return
            }

            Task { [weak self] in
                await self?.consume(bytes)
            }
        }

        source.activate()
        readSource = source
    }

    // Decodes a chunk and publishes its events.
    private func consume(_ bytes: [UInt8]) {
        escapeGeneration += 1

        for event in decoder.feed(bytes) {
            publish(event)
        }

        // A trailing lone ESC is ambiguous; resolve it as the Escape key if
        // no more bytes arrive shortly. The wait is a suspension, not a
        // blocked thread.
        if decoder.hasPendingEscape {
            let generation = escapeGeneration

            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(25))
                await self?.flushPendingEscape(ifStillGeneration: generation)
            }
        }
    }

    // Flushes a pending ESC when no newer input has arrived.
    private func flushPendingEscape(ifStillGeneration generation: Int) {
        guard generation == escapeGeneration else {
            return
        }

        for event in decoder.flushPending() {
            publish(event)
        }
    }

    private func publish(_ event: TerminalInput) {
        for continuation in continuations.values {
            continuation.yield(event)
        }
    }

    private func removeContinuation(_ id: Int) {
        continuations[id] = nil
    }

    // MARK: - Resize

    // Starts SIGWINCH handling for terminal resizes.
    private func startResizeSource() {
        signal(SIGWINCH, SIG_IGN)

        let source = DispatchSource.makeSignalSource(signal: SIGWINCH, queue: inputQueue)

        source.setEventHandler { [weak self] in
            Task { [weak self] in
                await self?.handleResize()
            }
        }

        source.activate()
        resizeSource = source
    }

    private func handleResize() {
        guard let size = Self.probeSize(descriptor: outputDescriptor), size != currentSize else {
            return
        }

        currentSize = size
        publish(.resize(size))
    }

    // Reads the terminal size from the kernel.
    private static func probeSize(descriptor: Int32) -> Size? {
        var window = winsize()

        guard ioctl(descriptor, UInt(TIOCGWINSZ), &window) == 0,
              window.ws_col > 0,
              window.ws_row > 0 else {
            return nil
        }

        return Size(width: Int(window.ws_col), height: Int(window.ws_row))
    }

    // MARK: - Output

    // Writes to the terminal on the output queue so no cooperative thread
    // ever blocks on terminal I/O (never-block requirement).
    private func write(_ text: String) async {
        let descriptor = outputDescriptor
        let bytes = Array(text.utf8)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            outputQueue.async {
                var offset = 0

                while offset < bytes.count {
                    let written = bytes[offset...].withUnsafeBytes { pointer -> Int in
                        #if canImport(Darwin)
                        Darwin.write(descriptor, pointer.baseAddress, pointer.count)
                        #else
                        Glibc.write(descriptor, pointer.baseAddress, pointer.count)
                        #endif
                    }

                    guard written > 0 else {
                        break
                    }

                    offset += written
                }

                continuation.resume()
            }
        }
    }
}
