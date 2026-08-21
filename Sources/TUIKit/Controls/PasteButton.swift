/// A button that reads the app's pasteboard and hands you what it found.
///
/// ```text
///   [ Paste ]   →   onPaste("the clipboard text")
/// ```
///
/// Activating reads `Pasteboard.string` — the app's clipboard, which is what
/// cut and copy in this app wrote (reading the *system* clipboard is a driver
/// story; see `Pasteboard`). Text goes to `onPaste`; an empty board calls
/// `onEmpty` instead, so the app can say so. The button inside is an
/// ordinary `Button`: roles, styles, accelerators and long-press all apply.
///
/// ```swift
/// let paste = PasteButton { text in address.setText(text) }
/// paste.onEmpty = { status.flash("Nothing to paste") }
/// ```
@MainActor
public final class PasteButton: TUIView {
    /// The button doing the pressing.
    public let button: Button

    /// Receives the pasteboard text.
    public var onPaste: (String) -> Void

    /// Called instead when the pasteboard is empty.
    public var onEmpty: () -> Void = {}

    /// The clipboard to read; `nil` (the default) reads the window's app's.
    public var pasteboard: Pasteboard?

    /// Creates a paste button.
    ///
    /// - Parameters:
    ///   - title: Button title; `&` marks the accelerator.
    ///   - onPaste: Receives the pasteboard text.
    public init(_ title: String = "&Paste", onPaste: @escaping (String) -> Void = { _ in }) {
        button = Button(title)
        self.onPaste = onPaste
        super.init(frame: .zero)
        button.anchors = .fill()
        addSubview(button)

        button.onActivate = { [weak self] in
            self?.paste()
        }
    }

    /// Focus lands on the button inside.
    public override var acceptsFirstResponder: Bool {
        false
    }

    /// The button's natural size.
    public override var intrinsicContentSize: Size? {
        button.intrinsicContentSize
    }

    /// Reads the pasteboard and reports, exactly as activating would.
    public func paste() {
        let board = pasteboard ?? owningWindow?.app?.pasteboard

        if let text = board?.string, !text.isEmpty {
            onPaste(text)
        } else {
            onEmpty()
        }
    }
}
