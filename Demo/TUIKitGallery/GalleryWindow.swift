import Foundation
import TUIKit

// The gallery window: an icon toolbar across the top, then folder tabs, one
// per control group. RULE (PLAN.md maintenance rules): a new TUIKit control
// lands with a spot in one of these tabs, in the same commit.

/// Builds one gallery window — a resizable, maximizable *content* window
/// (Turbo dresses it blue with a white double frame) whose content is a
/// folder-tab view over every control in the kit.
@MainActor
func makeGalleryWindow(index: Int, app: App) -> FloatingWindow {
    let window = FloatingWindow(
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

    installToolbar(on: window)

    let tabs = TabView()
    tabs.addTab("Buttons", content: makeButtonsTab(app: app))
    tabs.addTab("Inputs", content: makeInputsTab(app: app))
    tabs.addTab("Pickers", content: makePickersTab())
    tabs.addTab("Lists", content: makeListsTab())
    tabs.addTab("Text", content: makeTextTab())
    tabs.addTab("Layout", content: makeLayoutTab())
    tabs.addTab("Charts", content: makeChartsTab())
    tabs.anchors = .fill()
    window.content.addSubview(tabs)

    return window
}

// The window toolbar: icon buttons, a flexible address field (R6), and the
// long-press example — hold Back for its history menu, exactly the browser
// gesture the feature was built for.
@MainActor
private func installToolbar(on window: FloatingWindow) {
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
    bar.addItem("Settings", glyph: "⚙") {
        address.setText("tuikit://settings")
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
