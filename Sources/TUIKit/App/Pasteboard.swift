/// The application's clipboard.
///
/// One pasteboard per `App` (no global statics): cut and copy store text
/// here and paste reads it back, so clipboard flows work identically on
/// every driver. Copies are additionally forwarded to the terminal's system
/// clipboard when the driver supports it (`ANSIDriver` emits OSC 52) — the
/// forwarding hook is wired by `App`, never by application code.
///
/// ```text
///   editor.copySelection()
///        │
///        ▼
///   Pasteboard.copy ──── stores text ────▶ paste() reads it back
///        │
///        └─── systemSink ───▶ driver.setClipboard (OSC 52, best-effort)
/// ```
///
/// Reading the *system* clipboard is not part of v1 (that story is
/// bracketed paste, a driver feature); paste returns what this app copied.
@MainActor
public final class Pasteboard {
    /// The current clipboard text, when any.
    public private(set) var string: String?

    // Forwards copies toward the driver's system clipboard; set by App.
    var systemSink: (String) -> Void = { _ in }

    /// Creates an empty pasteboard.
    public init() {}

    /// Stores text, replacing the previous contents, and forwards it to the
    /// system clipboard when the driver supports one.
    ///
    /// - Parameter text: Text to store.
    public func copy(_ text: String) {
        string = text
        systemSink(text)
    }
}
