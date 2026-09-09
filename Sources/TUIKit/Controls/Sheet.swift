import Foundation

/// A dialog that belongs to one window (PLAN Phase 11.2).
///
/// A `Dialog` centres on the screen and owns all input while it is key: it is
/// the app asking a question. A sheet is narrower in both senses — it hangs
/// from a particular window's title row, and it blocks **only that window**.
/// The rest of a non-modal stack stays live, which is the whole point: saving
/// one document should not stop you reading another.
///
///     let sheet = Sheet(title: "Save changes?", message: "…", on: editor)
///     sheet.addButton("Save", isDefault: true) { … }
///     app.presentSheet(sheet)
///
/// **It is not modal in the app-wide sense**, and deliberately does not set
/// `isModal`: that flag makes the key window swallow every click aimed
/// anywhere else, which is the behaviour a sheet exists to avoid. The host is
/// blocked instead, by the window router sending its presses here.
public final class Sheet: Dialog {
    /// The window this sheet hangs from.
    ///
    /// Weak: the host owns the relationship, and a sheet outliving its window
    /// is a bug rather than a state to support.
    public private(set) weak var host: Window?

    /// Creates a sheet attached to a window.
    ///
    /// - Parameters:
    ///   - title: The sheet's title.
    ///   - message: Body text; newlines produce multiple lines.
    ///   - host: The window it belongs to.
    public init(title: String, message: String = "", on host: Window) {
        self.host = host
        super.init(title: title, message: message)

        // Not `.modalWindows`: that context is the theme's "the app is asking
        // you" look, and a sheet is one window's business. `.secondaryWindows`
        // is what a supporting window wears.
        themeContext = .secondaryWindows
        isModal = false
        isMovable = false   // it is attached; dragging it off its window is a lie
    }

    /// Places the sheet under its host's title row, centred on it.
    ///
    /// Clamped to the desktop, because a host near the right-hand edge would
    /// otherwise hang its sheet off the screen — and a sheet you cannot read
    /// is worse than one that is a few cells off centre.
    ///
    /// - Parameter desktop: The area windows live in.
    func anchor(in desktop: Rect) {
        guard let host else {
            return
        }

        let size = frame.size
        let centred = host.frame.minX + (host.frame.size.width - size.width) / 2
        let under = host.frame.minY + 1

        // An empty desktop means nobody has told us the screen size yet — at
        // construction, or in a test with no run loop. Clamping to nothing
        // would put every sheet at the origin, which looks like the anchor
        // failing rather than the screen being unknown.
        guard !desktop.isEmpty else {
            frame = Rect(origin: Point(x: max(0, centred), y: max(0, under)), size: size)
            return
        }

        let x = max(desktop.minX, min(centred, desktop.maxX - size.width))
        let y = max(desktop.minY, min(under, desktop.maxY - size.height))

        frame = Rect(origin: Point(x: x, y: y), size: size)
    }
}
