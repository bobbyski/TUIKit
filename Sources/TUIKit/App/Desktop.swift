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

    /// Tiles the background — or, on a VTG terminal under a theme with a
    /// desktop backdrop, draws a full-screen vertical gradient and clears
    /// the cells over it so it shows through (Phase 10). The gradient
    /// replaces `fillCharacter` patterns while chrome is active.
    public override func draw(_ painter: Painter) {
        let theme = effectiveTheme

        if let chrome = painter.chrome, let backdrop = theme.vector?.desktop {
            chrome.verticalGradient(
                "backdrop",
                ChromeRect(bounds),
                top: backdrop.topColor,
                bottom: backdrop.bottomColor,
                steps: min(24, max(8, bounds.size.height))
            )

            // Truly default-background cells (a neutral base defeats the
            // painter's theme substitution), so the terminal shows the
            // gradient behind them.
            let transparent = painter.withBase(CellStyle())
            transparent.fill(bounds, with: .blank)

            drawWindowShadows(chrome)
            return
        }

        painter.fill(bounds, with: TerminalCell(character: fillCharacter, style: fillStyle))
    }

    // Soft shadows behind floating windows, drawn by the desktop because a
    // window cannot paint outside its own frame (the clipping contract).
    // Slightly offset and rounded like the titlebar above each shadow.
    private func drawWindowShadows(_ chrome: ChromeSurface) {
        for subview in subviews {
            guard let window = subview as? Window, !window.isHidden, !window.fillsScreen,
                  let vector = window.effectiveTheme.vector,
                  let shadow = vector.windowShadow else {
                continue
            }

            let frame = ChromeRect(window.frame)

            // Keyed by the window's IDENTITY, not its index. Indices shift
            // whenever a window is activated (`activate` re-adds it to the
            // front), closed, or maximized — and a retained shape whose key
            // moves to a different window is a shape the reconciler cannot
            // match to what it drew last frame.
            chrome.rect(
                "shadow-\(UInt(bitPattern: ObjectIdentifier(window).hashValue))",
                ChromeRect(x: frame.x + 0.3, y: frame.y + 0.18, width: frame.width, height: frame.height),
                fill: shadow,
                radius: vector.titleBar?.cornerRadius ?? 0.35,
                corners: .all
            )
        }
    }
}
