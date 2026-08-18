import Dispatch
import Foundation
import VectorTerminalSDK

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

    // Whether the VTG probe found a VectorTerminal (Phase 10). The canvas
    // itself lives in `vtgState`, confined to the output queue.
    private var graphicsDetected = false

    // VTG canvas, glyph mapper, and last chrome frame. The class is only
    // ever touched on `outputQueue`, which is what makes the @unchecked
    // Sendable sound — the actor never reads it directly.
    private let vtgState = VTGState()

    private final class VTGState: @unchecked Sendable {
        var canvas: VectorTerminalCanvas?
        var mapper: CellPixelMapper?
        var previous: [ChromeCommand] = []
        var capabilities: GraphicsCapabilities?
        var uploadedAssets: Set<String> = []
    }

    // VTGOutput writing straight to the terminal descriptor, waiting out
    // EAGAIN like the driver's own writes (stdin's O_NONBLOCK is shared).
    private final class FDSink: VTGOutput {
        private let descriptor: Int32

        init(descriptor: Int32) {
            self.descriptor = descriptor
        }

        func write(_ data: Data) {
            let bytes = [UInt8](data)
            var offset = 0

            while offset < bytes.count {
                let written = bytes[offset...].withUnsafeBytes { pointer -> Int in
                    #if canImport(Darwin)
                    Darwin.write(descriptor, pointer.baseAddress, pointer.count)
                    #else
                    Glibc.write(descriptor, pointer.baseAddress, pointer.count)
                    #endif
                }

                if written > 0 {
                    offset += written
                    continue
                }

                if written == -1, errno == EAGAIN || errno == EWOULDBLOCK {
                    var descriptorSet = pollfd(fd: descriptor, events: Int16(POLLOUT), revents: 0)
                    _ = poll(&descriptorSet, 1, 100)
                    continue
                }

                break
            }
        }
    }

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

        // Probe for VectorTerminal Graphics BEFORE the read source starts —
        // the probe reads its own APC responses from stdin, and a running
        // read source would consume them (Phase 10.1).
        graphicsDetected = await probeGraphics()

        startReadSource()
        startResizeSource()
    }

    /// Hands the terminal back to the shell without ending the session.
    ///
    /// Unlike ``end()``, the input-stream continuations are left OPEN, so the
    /// app's run loop survives and ``resume()`` can pick it up again.
    public func suspend() async {
        guard isActive else {
            return
        }

        readSource?.cancel()
        readSource = nil
        resizeSource?.cancel()
        resizeSource = nil

        // Disable mouse, show cursor, leave the alternate screen — the
        // child program gets a normal terminal in its normal state.
        await write("\u{1B}[?1006l\u{1B}[?1002l\u{1B}[?25h\u{1B}[?1049l")

        // Blocking stdin again: the child does its own reads, and a
        // non-blocking descriptor it did not ask for would break it.
        let flags = fcntl(inputDescriptor, F_GETFL)
        _ = fcntl(inputDescriptor, F_SETFL, flags & ~O_NONBLOCK)

        if var original = originalTermios {
            tcsetattr(inputDescriptor, TCSANOW, &original)
        }

        isActive = false
    }

    /// Retakes the terminal after ``suspend()``.
    ///
    /// The window may have been resized while the child owned the screen, so
    /// the size is re-probed; callers redraw from scratch.
    public func resume() async {
        guard !isActive, originalTermios != nil else {
            return   // never began, or never suspended
        }

        var raw = termios()
        tcgetattr(inputDescriptor, &raw)
        cfmakeraw(&raw)
        tcsetattr(inputDescriptor, TCSANOW, &raw)

        let flags = fcntl(inputDescriptor, F_GETFL)
        _ = fcntl(inputDescriptor, F_SETFL, flags | O_NONBLOCK)

        isActive = true

        await write("\u{1B}[?1049h\u{1B}[?25l\u{1B}[?1002h\u{1B}[?1006h\u{1B}[2J\u{1B}[H")
        currentSize = Self.probeSize(descriptor: outputDescriptor) ?? currentSize

        // A half-typed escape sequence from before the handover would now be
        // decoded against unrelated bytes.
        decoder = ANSIInputDecoder()

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

        // Remove any retained vector chrome before leaving the screen.
        if graphicsDetected {
            let state = vtgState

            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                outputQueue.async {
                    state.canvas?.clear()
                    state.canvas = nil
                    state.mapper = nil
                    state.previous = []
                    continuation.resume()
                }
            }

            graphicsDetected = false
        }

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

    /// Places text on the system clipboard via OSC 52.
    ///
    /// Modern terminals (Terminal.app, iTerm2, kitty, …) apply OSC 52 to the
    /// real clipboard, including across ssh. Terminals without support
    /// ignore the sequence harmlessly.
    ///
    /// - Parameter text: Text to place on the clipboard.
    public func setClipboard(_ text: String) async {
        let encoded = Data(text.utf8).base64EncodedString()
        await write("\u{1B}]52;c;\(encoded)\u{07}")
    }

    // MARK: - VTG Chrome (Phase 10)

    /// Whether the begin-time probe found a VectorTerminal.
    public var supportsGraphicsChrome: Bool {
        graphicsDetected
    }

    /// What that VectorTerminal said it can do.
    ///
    /// Asked once during the probe, inside a budget already being spent on
    /// two round trips — and treated as optional: a terminal that draws
    /// images but will not answer the question reports the baseline rather
    /// than nothing, because "it draws images, we do not know what else" is
    /// the true statement and refusing to draw anything would be a worse one.
    public var graphicsCapabilities: GraphicsCapabilities? {
        graphicsDetected ? (vtgState.capabilities ?? .baseline) : nil
    }

    // Detects VTG support and glyph metrics on the output queue, where the
    // probe's blocking poll-with-deadline reads cannot park a cooperative
    // thread. Runs before the read source exists, so the APC responses on
    // stdin are the probe's to consume. `TUIKIT_VTG=0` opts out entirely.
    private func probeGraphics() async -> Bool {
        guard ProcessInfo.processInfo.environment["TUIKIT_VTG"] != "0" else {
            return false
        }

        let state = vtgState
        let descriptor = outputDescriptor

        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            outputQueue.async {
                let sink = FDSink(descriptor: descriptor)

                // Not a VectorTerminal → no VTG bytes beyond this one probe.
                guard let canvas = try? VectorTerminalCanvas(
                    input: .standardInput,
                    output: sink,
                    timeoutMilliseconds: 400
                ) else {
                    continuation.resume(returning: false)
                    return
                }

                // Chrome must sit exactly behind text; without real glyph
                // metrics, alignment would be a guess — treat as unsupported.
                guard let glyph = canvas.queryTerminalWSize(timeoutMilliseconds: 400),
                      glyph.width > 0, glyph.height > 0 else {
                    continuation.resume(returning: false)
                    return
                }

                // One more round trip, before the read source exists and
                // while the APC responses on stdin are still the probe's to
                // consume. A terminal that does not answer leaves this nil
                // and the baseline stands.
                let reported = canvas.queryCapabilityInfo(timeoutMilliseconds: 400)

                canvas.clear()
                state.canvas = canvas
                state.mapper = CellPixelMapper(glyphWidth: glyph.width, glyphHeight: glyph.height)
                state.previous = []
                state.capabilities = reported.map(GraphicsCapabilities.init(reported:))
                continuation.resume(returning: true)
            }
        }
    }

    /// Presents one frame of vector chrome, following the reconciler's
    /// plan: identical frames write nothing; same-structure frames update
    /// only the changed shapes in place; reordered frames rebuild (delete
    /// all, redraw) so retained stacking matches cell compositing. Each
    /// write batch rides a VTG frame for tear-free updates.
    ///
    /// - Parameter commands: The frame's chrome, in draw order.
    public func presentChrome(_ commands: [ChromeCommand]) async {
        guard graphicsDetected else {
            return
        }

        let state = vtgState

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            outputQueue.async {
                defer {
                    continuation.resume()
                }

                guard let canvas = state.canvas, let mapper = state.mapper else {
                    return
                }

                let deletions: [String]
                let draws: [ChromeCommand]

                switch ChromeSceneReconciler.plan(previous: state.previous, current: commands) {
                case .unchanged:
                    return

                case .update(let changed):
                    deletions = []
                    draws = changed

                case .rebuild(let stale):
                    deletions = stale
                    draws = commands
                }

                canvas.startFrame(id: "tuikit-chrome")

                for id in deletions {
                    canvas.delete(id: id)
                }

                // Assets already sent, so a scroll moves twenty bytes rather
                // than re-sending the picture. Kept on the driver, because
                // "has this terminal seen these pixels" is a fact about the
                // terminal and about nothing above it.
                var uploaded = state.uploadedAssets

                for command in draws {
                    Self.draw(
                        command,
                        on: canvas,
                        mapper: mapper,
                        uploaded: &uploaded,
                        supportsSprites: state.capabilities?.supportsSprites ?? false
                    )
                }

                state.uploadedAssets = uploaded

                canvas.endFrame(id: "tuikit-chrome")
                state.previous = commands
            }
        }
    }

    // One chrome command as SDK calls, in canvas pixels.
    private static func draw(
        _ command: ChromeCommand,
        on canvas: VectorTerminalCanvas,
        mapper: CellPixelMapper,
        uploaded: inout Set<String>,
        supportsSprites: Bool
    ) {
        let layer = command.layer == .underText ? VTGLayer.underText : VTGLayer.defaultOverlay

        switch command.shape {
        case .sprite(let rect, let asset):
            let pixels = mapper.rect(rect)

            // A terminal without sprite support draws the picture the plain
            // way, from the same bytes. An asset must never be the reason
            // something does not appear — that is the blank-region failure
            // capabilities exist to prevent.
            guard supportsSprites else {
                draw(
                    ChromeCommand(
                        id: command.id,
                        layer: command.layer,
                        shape: .image(rect, source: nil, data: asset.data, format: asset.format)
                    ),
                    on: canvas,
                    mapper: mapper,
                    uploaded: &uploaded,
                    supportsSprites: false
                )
                return
            }

            // Uploaded once, keyed by the asset's own id: every later frame
            // that places it sends the placement and not the payload.
            if uploaded.insert(asset.id).inserted {
                switch asset.format {
                case .png:
                    canvas.uploadSprite(
                        id: asset.id,
                        width: asset.pixelWidth > 0 ? asset.pixelWidth : pixels.width,
                        height: asset.pixelHeight > 0 ? asset.pixelHeight : pixels.height,
                        pngData: asset.data
                    )

                case .jpeg:
                    canvas.uploadSprite(
                        id: asset.id,
                        width: asset.pixelWidth > 0 ? asset.pixelWidth : pixels.width,
                        height: asset.pixelHeight > 0 ? asset.pixelHeight : pixels.height,
                        jpegData: asset.data
                    )
                }
            }

            canvas.sprite(
                id: command.id,
                imageID: asset.id,
                x: pixels.x,
                y: pixels.y,
                anchorX: 0,
                anchorY: 0,
                layer: layer
            )

        case .image(let rect, let source, let data, let format):
            let pixels = mapper.rect(rect)

            // NOT YET HONOURED, and deliberately not faked: VTG's `image`
            // command takes an id, a format, a rect and a filter — there is
            // no source rectangle in the protocol, so a terminal cannot be
            // asked to crop. A partly-scrolled image is therefore still
            // scaled into what survives clipping, which is the squash R3
            // describes.
            //
            // The rect is carried anyway because the geometry is the hard
            // part and it is right: the day VTG grows a source parameter,
            // this switch is the only place that changes. Until then a
            // consumer can read it and decide for itself — which is what
            // TUIWebBrowser does, drawing a placeholder for anything not
            // wholly visible.
            _ = source

            switch format {
            case .png:
                canvas.image(
                    id: command.id,
                    x: pixels.x,
                    y: pixels.y,
                    width: pixels.width,
                    height: pixels.height,
                    pngData: data,
                    layer: layer
                )

            case .jpeg:
                canvas.image(
                    id: command.id,
                    x: pixels.x,
                    y: pixels.y,
                    width: pixels.width,
                    height: pixels.height,
                    jpegData: data,
                    layer: layer
                )
            }

        case .rect(let rect, let fill, let stroke, let lineWidth, let radius, let corners):
            let pixels = mapper.rect(rect)

            canvas.rect(
                id: command.id,
                x: pixels.x,
                y: pixels.y,
                width: pixels.width,
                height: pixels.height,
                stroke: stroke.map(vtgColor),
                fill: fill.map(vtgColor),
                lineWidth: max(1, mapper.scalar(lineWidth)),
                radius: corners.isEmpty ? 0 : mapper.scalar(radius),
                corners: cornersString(corners),
                layer: layer
            )

        case .circle(let center, let radius, let fill, let stroke, let lineWidth):
            let pixels = mapper.point(center)

            canvas.circle(
                id: command.id,
                cx: pixels.x,
                cy: pixels.y,
                radius: mapper.scalar(radius),
                stroke: stroke.map(vtgColor),
                fill: fill.map(vtgColor),
                lineWidth: max(1, mapper.scalar(lineWidth)),
                layer: layer
            )

        case .line(let from, let to, let color, let width):
            let a = mapper.point(from)
            let b = mapper.point(to)

            canvas.line(
                id: command.id,
                x1: a.x,
                y1: a.y,
                x2: b.x,
                y2: b.y,
                stroke: vtgColor(color),
                width: max(1, mapper.scalar(width)),
                layer: layer
            )
        }
    }

    private static func vtgColor(_ color: ChromeColor) -> VTGColor {
        VTGColor(color.hexString)
    }

    // VTG's corner digits: 1 top-left, 2 top-right, 3 bottom-right,
    // 4 bottom-left; nil rounds all four.
    private static func cornersString(_ corners: ChromeCorners) -> String? {
        guard corners != .all else {
            return nil
        }

        var digits = ""
        if corners.contains(.topLeft) { digits += "1" }
        if corners.contains(.topRight) { digits += "2" }
        if corners.contains(.bottomRight) { digits += "3" }
        if corners.contains(.bottomLeft) { digits += "4" }
        return digits
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

                    if written > 0 {
                        offset += written
                        continue
                    }

                    // On a terminal, stdin/stdout share one file description,
                    // so the O_NONBLOCK set for input reads also applies here:
                    // a large frame can return EAGAIN when the terminal's
                    // write buffer is full. Wait for writability and retry
                    // rather than dropping the rest of the frame (which would
                    // truncate the display). This waits on the dedicated
                    // output queue, never a cooperative thread.
                    if written == -1, errno == EAGAIN || errno == EWOULDBLOCK {
                        var descriptorSet = pollfd(fd: descriptor, events: Int16(POLLOUT), revents: 0)
                        _ = poll(&descriptorSet, 1, 100)
                        continue
                    }

                    // A genuine error; stop.
                    break
                }

                continuation.resume()
            }
        }
    }
}
