import Foundation

/// A clickable link: underlined text that opens a URL — or hands it to you.
///
/// ```text
///   Release notes     ← `.text`: underlined, accent-coloured
///   (?)               ← `.helpButton`: the round help button
/// ```
///
/// Enter, Space, or a click opens the link. With `onOpen` set the URL is
/// handed over and nothing else happens — the app decides (open it in its
/// own browser pane, log it, copy it). Without it, the URL goes to the
/// system opener (`open` on macOS, `xdg-open` elsewhere), detached and never
/// waited on.
///
/// ```swift
/// let notes = Link("Release notes", url: "https://example.com/notes")
/// notes.onOpen = { url in browserPane.open(url) }
///
/// let help = Link.help(anchor: "themes", baseURL: "https://example.com/help#")
/// ```
///
/// Phase 16 note: this is a focusable cell control. OSC 8 terminal
/// hyperlinks — clickable without focus, in terminals that render them —
/// need a cell-level URL attribute and are not part of this first cut.
@MainActor
public final class Link: TUIView {
    /// How a link dresses.
    public enum Presentation: Hashable, Sendable {
        /// Underlined text.
        case text

        /// The round `(?)` help button.
        case helpButton
    }

    /// Visible text (ignored by `.helpButton`).
    public var title: String {
        didSet {
            if title != oldValue {
                superview?.setNeedsLayout()
                setNeedsDisplay()
            }
        }
    }

    /// What opening goes to.
    public var url: String

    /// Text or help button.
    public var presentation: Presentation {
        didSet {
            if presentation != oldValue {
                superview?.setNeedsLayout()
                setNeedsDisplay()
            }
        }
    }

    /// Receives the URL instead of the system opener, when set.
    public var onOpen: ((String) -> Void)?

    /// Creates a link.
    ///
    /// - Parameters:
    ///   - title: Visible text.
    ///   - url: What opening goes to.
    ///   - presentation: Text (the default) or the help button.
    public init(_ title: String, url: String, presentation: Presentation = .text) {
        self.title = title
        self.url = url
        self.presentation = presentation
        super.init(frame: .zero)
    }

    /// The round `(?)` help button that opens an anchor in the app's help.
    ///
    /// - Parameters:
    ///   - anchor: Help anchor, appended to `baseURL`.
    ///   - baseURL: Where the help lives.
    /// - Returns: A link in its `.helpButton` dress.
    public static func help(anchor: String, baseURL: String) -> Link {
        Link("?", url: baseURL + anchor, presentation: .helpButton)
    }

    /// Links take keyboard focus.
    public override var acceptsFirstResponder: Bool {
        true
    }

    /// One row at the title's width — three cells for the help button.
    public override var intrinsicContentSize: Size? {
        switch presentation {
        case .text:
            return Size(width: title.count, height: 1)

        case .helpButton:
            return Size(width: 3, height: 1)
        }
    }

    /// Opens the link exactly as interaction would.
    public func open() {
        if let onOpen {
            onOpen(url)
        } else {
            Self.openExternally(url)
        }
    }

    /// Draws the underlined title, or the help button.
    public override func draw(_ painter: Painter) {
        let theme = effectiveTheme

        guard bounds.size.width > 0, bounds.size.height > 0 else {
            return
        }

        switch presentation {
        case .text:
            var style = isFirstResponder ? theme.selection : theme.base

            if !isFirstResponder, let accent = theme.cueAccent(over: theme.background) {
                style.foreground = accent
            }

            style.flags.insert(.underline)
            painter.write(Label.truncated(title, width: bounds.size.width), at: .zero, style: style)

        case .helpButton:
            painter.write("(?)", at: .zero, style: isFirstResponder ? theme.defaultButton : theme.button)
        }
    }

    /// Enter or Space opens.
    public override func keyDown(_ key: KeyInput) -> Bool {
        guard key.modifiers.isEmpty else {
            return false
        }

        switch key.key {
        case .enter, .character(" "):
            open()
            return true

        default:
            return false
        }
    }

    /// A click opens.
    public override func mouseEvent(_ mouse: MouseInput) -> Bool {
        guard mouse.action == .press, mouse.button == .left else {
            return false
        }

        open()
        return true
    }

    // Hands a URL to the platform opener without waiting — a blocked main
    // thread is the one thing a link must never cost.
    private static func openExternally(_ url: String) {
        let process = Process()

        #if os(macOS)
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        #else
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xdg-open")
        #endif

        process.arguments = [url]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }
}
