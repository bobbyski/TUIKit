/// Drawing a surface the terminal can be seen through.
///
/// A cell is opaque or it is the terminal's default — there is no cell that
/// is three-quarters of a colour. So a translucent surface is drawn by the
/// vector layer UNDER the text and the cells above it are cleared to the
/// default, which is the same trick the desktop backdrop and the vector
/// titlebar already use.
///
/// Only WINDOW BODIES are drawn this way. Menus, the menu bar and toolbars
/// keep their opaque cells, which makes them more solid than the document
/// under them by construction rather than by arithmetic — and keeps them
/// legible on a terminal that draws no vectors at all, where a cleared cell
/// is simply an empty one.
/// Keys the FRAMEWORK claims in a view's chrome namespace.
///
/// A chrome command's id is `"<owner view>_<key>"`, so two keys only collide
/// inside one view — which is exactly where a framework drawing "body" and an
/// application drawing "body" would meet, and the application would lose
/// without ever being told. Everything TUIKit draws on a view an application
/// also draws on carries this prefix.
public enum ChromeKeys {
    /// Namespace for every framework-claimed key.
    public static let prefix = "tuikit."

    /// The translucent fill behind a window's content.
    public static let windowSurface = prefix + "window-surface"
}

public extension TUIView {
    /// Fills a rect with the theme's translucent window fill, clearing the
    /// cells over it, and reports whether it did.
    ///
    /// - Parameters:
    ///   - painter: The painter for this draw pass.
    ///   - rect: The area to fill, in view coordinates.
    ///   - key: Id unique within this view; defaults to the framework's own
    ///     namespaced key, which is what keeps it clear of a host's.
    /// - Returns: False when the terminal has no vector layer or the theme
    ///   asks for solid surfaces — the caller then fills cells as before.
    @discardableResult
    func drawTranslucentWindowSurface(
        _ painter: Painter,
        _ rect: Rect,
        key: String = ChromeKeys.windowSurface
    ) -> Bool {
        guard let surface = effectiveTheme.vector?.surface else {
            return false
        }

        return fillTranslucent(painter, rect, key: key, color: surface.windowFill, radius: surface.cornerRadius ?? 0)
    }

    private func fillTranslucent(
        _ painter: Painter,
        _ rect: Rect,
        key: String,
        color: ChromeColor,
        radius: Double
    ) -> Bool {
        guard let chrome = painter.chrome, rect.size.width > 0, rect.size.height > 0 else {
            return false
        }

        chrome.rect(key, ChromeRect(rect), fill: color, radius: radius)

        // A neutral base defeats the painter's theme substitution, so these
        // cells keep the terminal's own default background and the fill
        // below shows through them.
        painter.withBase(CellStyle()).fill(rect, with: .blank)
        return true
    }
}
