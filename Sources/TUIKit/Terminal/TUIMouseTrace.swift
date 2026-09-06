import Foundation

/// Records every mouse event the terminal sends, as it was decoded.
///
/// Enabled by `TUIKIT_VTG_LOG`, alongside the graphics probe and the
/// per-view chrome verdicts, so one file answers the whole question in
/// order: what the terminal can do, what each view did about it, and what
/// the pointer actually reported.
///
/// A press that never appears here never reached the program — the terminal
/// did not send it, or sent it in an encoding this decoder does not read. A
/// press that appears and changes nothing on screen arrived and was routed
/// somewhere that did not want it. Those need opposite fixes, and without
/// this line they look identical.
enum TUIMouseTrace {
    private static let lock = NSLock()

    static func record(code: Int, event: MouseInput) {
        guard let path = ProcessInfo.processInfo.environment["TUIKIT_VTG_LOG"] else { return }

        // Motion with no button held is most of what a terminal sends and
        // none of what a click question needs.
        if event.action == .move { return }

        let line = Data("""
            vtg mouse: \(event.action) \(event.button) at \
            \(event.position.x),\(event.position.y) (SGR code \(code))

            """.replacingOccurrences(of: "\n            ", with: "").utf8)

        lock.lock()
        defer { lock.unlock() }
        if let handle = FileHandle(forWritingAtPath: path) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: URL(fileURLWithPath: path))
        }
    }
}
