/// A window's toolbar: the bar pinned across the top of its content.
///
/// ```text
///   ╔═ Project ═══════════════════════════════[+][x]╗
///   ║ ✓ Save │ ⚒ Build  ▶ Run  ■ Stop        ⚙ ...  ║ ← toolbar (always here)
///   ╟───────────────┬───────────────────────────────╢
///   ║ Files         │ main.swift                    ║
///   ║ ▾ Sources     │  1 │ import Foundation        ║
///   ╚═══════════════╧═══════════════════════════◢═══╝
/// ```
///
/// Bobby: *"the difference between toolbar and ribbon is that ribbons can be
/// anywhere, toolbars are always on top."* That is the whole distinction, and
/// this is the half of it that needed code: a ``Ribbon`` is a view you place
/// like any other, while a ``Toolbar`` is handed to the WINDOW, which decides
/// where it goes — and the answer is always the top.
///
/// The consequence is that placement stops being a caller's decision, and so
/// stops being a caller's bug. The toolbar takes its rows off the top of the
/// window's interior before anything else is measured, which means:
///
/// - Slide-outs start *below* it. A toolbar spans the window, so the Files
///   panel does not run up alongside the Build button.
/// - The document shrinks by exactly the toolbar's height, without the
///   window's content having to know a toolbar exists.
/// - Hiding it gives the rows straight back, with no layout code anywhere
///   else needing to care.
public extension Window {
    /// The window's toolbar, if it has one.
    var toolbar: Toolbar? {
        windowToolbar
    }

    /// Pins a toolbar across the top of the window, or removes it.
    ///
    /// - Parameter toolbar: The bar, or nil to remove the current one.
    func setToolbar(_ toolbar: Toolbar?) {
        guard toolbar !== windowToolbar else {
            return
        }

        windowToolbar?.removeFromSuperview()
        windowToolbar = toolbar

        if let toolbar {
            // Added last so it draws over the content beneath it, and so a
            // window built before its toolbar still ends up with the bar on
            // top rather than behind the editor.
            addSubview(toolbar)
        }

        setNeedsLayout()
        setNeedsDisplay()
    }

    /// Shows or hides the toolbar, relaying out the window around it.
    ///
    /// - Parameter isVisible: Whether the bar draws and takes rows.
    func setToolbarVisible(_ isVisible: Bool) {
        guard let windowToolbar, windowToolbar.isHidden == isVisible else {
            return
        }

        windowToolbar.isHidden = !isVisible
        setNeedsLayout()
        setNeedsDisplay()
    }

    /// Whether the window has a toolbar and it is showing.
    var isToolbarVisible: Bool {
        windowToolbar.map { !$0.isHidden } ?? false
    }
}

public extension Window {
    /// The interior left for slide-outs and the document: everything the
    /// window offers, minus the toolbar's rows.
    ///
    /// Computed, never stored, because it is read during layout by the very
    /// pass that would have to keep a stored copy honest.
    var slideOutContentRegion: Rect {
        let region = slideOutRegion

        guard let toolbar = windowToolbar, !toolbar.isHidden else {
            return region
        }

        // A toolbar never takes the whole window: at minimum the document
        // keeps a row, or a bar in a very short window would leave a project
        // with nowhere to show its code.
        let rows = min(toolbar.rowCount, max(0, region.size.height - 1))

        return Rect(
            x: region.minX,
            y: region.minY + rows,
            width: region.size.width,
            height: region.size.height - rows
        )
    }

    /// Places the toolbar across the top of the window's interior.
    ///
    /// Called from `layoutSubviews` before the slide-outs, which then lay
    /// themselves out in what is left.
    internal func layoutWindowToolbar() {
        guard let toolbar = windowToolbar, !toolbar.isHidden else {
            return
        }

        let region = slideOutRegion
        let rows = min(toolbar.rowCount, max(0, region.size.height - 1))

        toolbar.frame = Rect(
            x: region.minX,
            y: region.minY,
            width: region.size.width,
            height: rows
        )
        toolbar.layoutIfNeeded()
    }
}
