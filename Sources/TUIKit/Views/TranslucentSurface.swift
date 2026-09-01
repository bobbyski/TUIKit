/// Drawing a surface the terminal can be seen through.
///
/// A cell is opaque or it is the terminal's default — there is no cell that
/// is three-quarters of a colour. So a translucent surface is drawn by the
/// vector layer UNDER the text and the cells above it are cleared to the
/// default, which is the same trick the desktop backdrop and the vector
/// titlebar already use.
///
/// Two fills, because a window and the chrome over it are not the same kind
/// of surface: the document may be translucent, but a menu you can read the
/// document through is a menu you cannot read.
public extension TUIView {
    /// Fills a rect with the theme's translucent window fill, clearing the
    /// cells over it, and reports whether it did.
    ///
    /// - Parameters:
    ///   - painter: The painter for this draw pass.
    ///   - rect: The area to fill, in view coordinates.
    ///   - key: Id unique within this view.
    /// - Returns: False when the terminal has no vector layer or the theme
    ///   asks for solid surfaces — the caller then fills cells as before.
    @discardableResult
    func drawTranslucentWindowSurface(_ painter: Painter, _ rect: Rect, key: String = "surface") -> Bool {
        guard let surface = effectiveTheme.vector?.surface else {
            return false
        }

        return fillTranslucent(painter, rect, key: key, color: surface.windowFill, radius: surface.cornerRadius ?? 0)
    }

    /// Fills a rect with the theme's chrome fill — menus, the menu bar, and
    /// toolbars, which are never more transparent than the window they cover.
    ///
    /// - Parameters:
    ///   - painter: The painter for this draw pass.
    ///   - rect: The area to fill, in view coordinates.
    ///   - key: Id unique within this view.
    /// - Returns: False when the surface could not be drawn.
    @discardableResult
    func drawTranslucentChromeSurface(_ painter: Painter, _ rect: Rect, key: String = "chrome") -> Bool {
        guard let surface = effectiveTheme.vector?.surface else {
            return false
        }

        return fillTranslucent(painter, rect, key: key, color: surface.chromeFill, radius: 0)
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
