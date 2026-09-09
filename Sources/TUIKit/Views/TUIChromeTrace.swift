import Foundation

/// Reports, once per view, whether it drew with vector chrome — and when it
/// did not, which of the reasons applied.
///
/// Enabled by `TUIKIT_VTG_LOG`, the same file `ANSIDriver`'s probe writes to,
/// so one log reads top to bottom as: what the terminal answered, then what
/// each view did about it.
///
/// The probe's outcome is a process-wide boolean and says nothing about an
/// individual view. A chart drawing cells on a VTG terminal is either a
/// subtree that opted out (`suppressesVectorChrome`) or a frame with no room
/// to draw in, and on screen those look the same — a chart full of glyphs.
@MainActor
enum TUIChromeTrace {
    private static var seen: Set<ObjectIdentifier> = []

    /// Where to log, read once.
    ///
    /// **Once, not once per view per frame.** This is called from
    /// `renderTree` for every view in the tree on every frame, and it used to
    /// ask `ProcessInfo` each time — a dictionary build and lookup per view
    /// per frame, to answer a question whose answer cannot change while the
    /// process runs. A diagnostic that is off should cost a nil check.
    private static let logPath = ProcessInfo.processInfo.environment["TUIKIT_VTG_LOG"]

    /// Whether the trace is on at all, so the caller can skip the call.
    static var isEnabled: Bool { logPath != nil }

    static func record(_ view: TUIView, painter: Painter) {
        guard let path = logPath else { return }
        let identity = ObjectIdentifier(view)
        guard seen.insert(identity).inserted else { return }

        let kind = String(describing: type(of: view))
        let frame = view.frame
        let size = "\(frame.size.width)x\(frame.size.height)"
        let verdict: String
        if painter.chrome != nil {
            verdict = "chrome"
        } else if view.suppressesVectorChrome {
            verdict = "cells — suppressesVectorChrome is set on this subtree"
        } else if frame.size.width <= 0 || frame.size.height <= 0 {
            verdict = "cells — the frame is empty, so there is nowhere to draw"
        } else {
            verdict = "cells — the terminal reported no vector chrome (see the probe lines above)"
        }

        let line = Data("vtg view: \(kind) \(size) → \(verdict)\n".utf8)
        if let handle = FileHandle(forWritingAtPath: path) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: URL(fileURLWithPath: path))
        }
    }
}
