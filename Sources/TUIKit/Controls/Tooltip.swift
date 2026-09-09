import Foundation

/// Hover text, shown after the pointer rests (PLAN Phase 11.5).
///
/// The terminal analogue of `NSView.toolTip` and SwiftUI's `.help(_:)`: set
/// ``TUIView/toolTip`` on any view and the window shows this panel once the
/// pointer has been still over it for ``Window/tooltipDelay``.
///
/// **It never takes focus.** A tooltip appears because the pointer happened to
/// rest somewhere, which is the weakest possible signal of intent — taking the
/// keyboard away from whatever the user was actually working in would make the
/// feature worse than absent.
///
/// **Floating chrome, so `.menus`.** It covers other content and must not
/// borrow that content's colour, which is what `.accessoryView` would do (see
/// `Docs/HOW_TO_WRITE_A_GOOD_TUI.md`, rule 3). It also fills its own cells
/// before drawing: a panel you can see through is a panel that reads as
/// corruption.
@MainActor
public final class TooltipPanel: TUIView {
    /// The help text.
    public let text: String

    /// Creates a panel for one line of help text.
    ///
    /// - Parameter text: The text to show.
    public init(text: String) {
        self.text = text
        super.init(frame: .zero)
        themeContext = .menus
    }

    /// Never — see the type's note.
    public override var acceptsFirstResponder: Bool {
        false
    }

    /// A boxed single line: the text, a cell of padding each side, a border.
    public override var intrinsicContentSize: Size? {
        Size(width: DisplayWidth.of(text) + 4, height: 3)
    }

    public override func draw(_ painter: Painter) {
        let theme = effectiveTheme
        painter.withBase(theme.base).fill(bounds, with: .blank)
        painter.drawBox(bounds, style: theme.border, border: theme.borderStyle)
        painter.write(text, at: Point(x: 2, y: 1), style: theme.base)
    }
}
