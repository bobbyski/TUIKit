/// The screen background behind every window.
///
/// The desktop is the root of the screen: `App` sizes it to the terminal
/// and presents windows as its subviews, so it is drawn wherever no window
/// covers the screen. Style it like anything else — give it a theme and a
/// fill pattern:
///
/// ```swift
/// app.desktop.theme = .dark
/// app.desktop.fillCharacter = "▒"     // the classic desktop weave
/// ```
///
/// Because themes cascade, the desktop's theme is also the default for
/// every window that doesn't set its own.
@MainActor
public final class Desktop: TUIView {
    /// Character tiled across the background. Defaults to a space.
    public var fillCharacter: Character = " " {
        didSet {
            if fillCharacter != oldValue {
                setNeedsDisplay()
            }
        }
    }

    /// Style for the fill. `.standard` colors resolve through the theme.
    public var fillStyle = CellStyle() {
        didSet {
            if fillStyle != oldValue {
                setNeedsDisplay()
            }
        }
    }

    /// Creates a desktop.
    public init() {
        super.init(frame: .zero)
    }

    /// Tiles the background.
    public override func draw(_ painter: Painter) {
        painter.fill(bounds, with: TerminalCell(character: fillCharacter, style: fillStyle))
    }
}
