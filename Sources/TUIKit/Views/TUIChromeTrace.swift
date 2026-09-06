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

    static func record(_ view: TUIView, painter: Painter) {
        guard let path = ProcessInfo.processInfo.environment["TUIKIT_VTG_LOG"] else { return }
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
