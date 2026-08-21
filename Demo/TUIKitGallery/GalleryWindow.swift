import Foundation
import TUIKit

// The gallery window: an icon toolbar across the top, then folder tabs, one
// per control group. RULE (PLAN.md maintenance rules): a new TUIKit control
// lands with a spot in one of these tabs, in the same commit.

/// The gallery window: a content window with the Controls slide-out on its
/// left edge — the TUIKit sidebar, as an app uses it. `^L` toggles it, so
/// does the `[>]`/`[<]` button after the title.
@MainActor
final class GalleryWindow: FloatingWindow {
    override func handleHotKey(_ key: KeyInput) -> Bool {
        if key.modifiers == .control, key.key == .character("l") {
            toggleSlideOut(.leading)
            return true
        }

        return super.handleHotKey(key)
    }
}

/// Builds one gallery window — a resizable, maximizable *content* window
/// (Turbo dresses it blue with a white double frame) whose content is a
/// folder-tab view over every control in the kit, with a Controls panel
/// that slides out of the left edge to jump between the tabs.
@MainActor
func makeGalleryWindow(index: Int, app: App, settings: GallerySettings) -> GalleryWindow {
    let window = GalleryWindow(
        title: index == 0 ? "TUIKit Gallery" : "TUIKit Gallery \(index + 1)",
        frame: Rect(x: 2 + index * 2, y: 1 + index, width: 78, height: 24)
    )
    window.themeContext = .contentWindow   // the document surface: Turbo blue
    window.minimumWindowSize = Size(width: 50, height: 14)
    window.maximizeInsets = EdgeInsets(top: 1, bottom: 1)   // keep menu + status visible
    window.onCloseRequest = { [weak app, weak window] in
        if let app, let window {
            app.dismiss(window)
        }
    }

    installToolbar(on: window, app: app, settings: settings)

    let tabs = TabView()
    let pages: [(title: String, summary: String, content: TUIView)] = [
        ("Buttons", "roles, long-press, dialogs", makeButtonsTab(app: app, settings: settings)),
        ("Inputs", "fields, sliders, tokens", makeInputsTab(app: app)),
        ("Pickers", "dates, colours, matrix", makePickersTab()),
        ("Lists", "lists, trees, tables", makeListsTab()),
        ("Text", "editors and markdown", makeTextTab()),
        ("Layout", "stacks, splits, forms", makeLayoutTab()),
        ("Navigation", "wizard, pages, accordion", makeNavigationTab()),
        ("Charts", "cells and VTG", makeChartsTab()),
    ]

    for page in pages {
        tabs.addTab(page.title, content: page.content)
    }

    // A rule between the toolbar and the folder tabs; connected, so the
    // window welds it into its frame (╟─╢).
    let content = VStack(spacing: 0)
    content.addSubview(pinnedHeight(Divider(axis: .horizontal), 1))
    content.addSubview(tabs)
    content.anchors = .fill()
    window.content.addSubview(content)

    // The Controls panel: the slide-out, holding an index of the tabs.
    // Selecting a row shows that tab; the panel stays put (pinned) because
    // jumping between tabs is exactly when you want it open.
    let index = SidebarList(items: pages.map { SidebarItem(icon: "▸", title: $0.title, subtitle: $0.summary) })
    index.onSelectionChanged = { [weak tabs] selected in
        if let selected {
            tabs?.select(selected)
        }
    }
    index.onActivate = { [weak tabs] selected in
        tabs?.select(selected)
    }

    let panel = window.addSlideOut(.leading, title: "Controls", content: index, length: 28, minimumLength: 16)
    panel.isPinned = true
    window.slideOutToggleEdge = .leading

    if settings.controlsPanelOpen {
        window.openSlideOut(.leading)
    }

    return window
}

// The window toolbar: icon buttons, a flexible address field (R6), and the
// long-press example — hold Back for its history menu, exactly the browser
// gesture the feature was built for.
@MainActor
private func installToolbar(on window: FloatingWindow, app: App, settings: GallerySettings) {
    let bar = Toolbar()
    bar.displayMode = .both   // glyph over title: the two-row bar, shown off

    let address = TextField()
    address.setText("tuikit://gallery/charts")

    let back = bar.addItem("Back", glyph: "◀") {
        address.setText("tuikit://gallery/back — quick click")
    }
    back.longPressAction = { [weak window] in
        guard let window else {
            return
        }

        let history = Menu("")

        for entry in ["gallery/charts", "gallery/text", "gallery/buttons"] {
            history.addItem("tuikit://\(entry)") {
                address.setText("tuikit://\(entry) — from held Back")
            }
        }

        // Below the toolbar row, at the button.
        window.presentContextMenu(history, at: Point(x: 3, y: 2))
    }

    bar.addItem("Forward", glyph: "▶") {
        address.setText("tuikit://gallery/forward")
    }
    bar.addItem("Reload", glyph: "⟳") {
        address.setText("tuikit://gallery — reloaded")
    }
    bar.add(.divider())
    bar.add(.view(address, title: "Address", flexible: true))
    bar.add(.divider())
    bar.addItem("Settings", glyph: "⚙") { [weak app] in
        if let app {
            settings.presentPreferences(in: app)   // the real preferences dialog
        }
    }

    window.setToolbar(bar)
}

// MARK: - Shared layout helpers (used by every tab file)

/// A group box: a titled panel whose content is a padded vertical stack.
@MainActor
func group(_ title: String, spacing: Int = 1, _ children: [TUIView]) -> Panel {
    let panel = Panel(title)
    let stack = VStack(spacing: spacing, insets: EdgeInsets(top: 0, left: 1, bottom: 0, right: 1))

    for child in children {
        stack.addSubview(child)
    }

    stack.anchors = .fill()
    panel.content.addSubview(stack)
    return panel
}

/// Pins a stack row to an exact height, so flexible rows don't absorb it.
@MainActor
@discardableResult
func pinnedHeight(_ view: TUIView, _ height: Int) -> TUIView {
    view.minimumSize = Size(width: 0, height: height)
    view.maximumSize = Size(width: Int.max, height: height)
    return view
}

/// A row of side-by-side flexible children.
@MainActor
func row(spacing: Int = 1, _ children: [TUIView]) -> HStack {
    let stack = HStack(spacing: spacing)

    for child in children {
        stack.addSubview(child)
    }

    return stack
}
