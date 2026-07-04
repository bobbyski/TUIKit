import Foundation
import TUIKit

/// The interactive demo's desktop-and-menu shell. It owns the shared `App`
/// and the window counter; each window factory lives in its own file as a
/// `DemoApp` extension (see `Declarative/` and `Traditional/`).
@MainActor
final class DemoApp {
    let app = App(driver: ANSIDriver())
    var exampleCount = 0

    /// Builds the desktop, menu bar, and status strip, opens the initial
    /// windows, and runs the app until it stops.
    func run() async throws {
        // Rebind the property to a local so the many menu closures below capture
        // `app` directly rather than `self` (the factories in the other files do
        // the same). `app.desktop` is the screen-filling root behind every window;
        // styling it here sets the default look, and because themes cascade, its
        // theme is inherited by any window that doesn't set its own.
        let app = self.app
        app.desktop.fillStyle = CellStyle(background: .rgb(red: 128, green: 128, blue: 128))
        app.desktop.theme = .dark   // inherited default for un-themed windows

        // Root menu strip: File spawns example windows, Theme restyles the key one.
        let menuWindow = MenuBarWindow()
        menuWindow.onQuit = { app.stop() }

        // Bottom status-strip text, declared up here so the Theme menu (built
        // next) can re-style it whenever the theme changes.
        let statusTitle = Label(" TUIKit Demo")
        let statusHint = Label("File ▸ New… opens examples · close a window to dismiss it")
        let clock = Label("--:--:--")

        // The menu bar and status strip are *chrome*, so their text wears the
        // theme's `header` slot (Turbo's gray bar, etc.). The bars themselves
        // already fill with `header`; this makes their content match instead of
        // rendering as window-colored (blue/yellow) text on the gray strip.
        // Called at startup and again on every theme switch below.
        func styleStatusChrome() {
            let header = menuWindow.effectiveTheme.header
            statusTitle.style = header           // bold title
            var plain = header
            plain.flags.remove(.bold)
            statusHint.style = plain
            clock.style = plain
        }

        let fileMenu = Menu("File")
        fileMenu.addItem("New Declarative Example", keyEquivalent: KeyInput(key: .character("n"), modifiers: .control)) {
            self.exampleCount += 1
            app.present(self.makeDeclarativeExample(index: self.exampleCount))
        }
        fileMenu.addItem("New Manual Example", keyEquivalent: KeyInput(key: .character("m"), modifiers: .control)) {
            self.exampleCount += 1
            app.present(self.makeManualExample(index: self.exampleCount))
        }
        fileMenu.addItem("New Contact Book", keyEquivalent: KeyInput(key: .character("b"), modifiers: .control)) {
            self.exampleCount += 1
            app.present(self.makeContactBook(index: self.exampleCount))
        }
        fileMenu.addItem("New Demo Source", keyEquivalent: KeyInput(key: .character("d"), modifiers: .control)) {
            self.exampleCount += 1
            app.present(self.makeDemoSource(index: self.exampleCount))
        }
        fileMenu.addSeparator()
        fileMenu.addItem("Close Window", keyEquivalent: KeyInput(key: .character("w"), modifiers: .control)) {
            // Opening the menu made the strip key, so target the top-most example.
            if let target = app.windows.last(where: { $0 !== menuWindow }) {
                app.dismiss(target)
            }
        }
        fileMenu.addSeparator()
        fileMenu.addItem("Quit", keyEquivalent: KeyInput(key: .character("q"), modifiers: .control)) {
            app.stop()
        }

        let themeMenu = Menu("Theme")
        for (name, theme) in TUIKit.Theme.builtIn {
            themeMenu.addItem(name) {
                // One call themes the whole app — desktop and every window. Views
                // can still opt out locally (e.g. the declarative window pins its
                // controls to `.standard`).
                app.applyTheme(theme)
                // Paint the desktop with a *lightened* version of the theme
                // background, so windows (drawn on the theme background) stand
                // out against a distinct backdrop — Turbo Pascal's light-blue
                // desktop under its royal-blue windows. Uses the existing
                // Desktop.fillStyle + Theme.blendColors; colorless themes (no RGB
                // to blend) fall back to the plain background.
                let bg = theme.base.background
                let backdrop = TUIKit.Theme.blendColors(bg, toward: .named(.white), fraction: 0.3) ?? bg
                app.desktop.fillStyle = CellStyle(background: backdrop)
                // Re-color the status text to the new theme's chrome slot.
                styleStatusChrome()
            }
        }

        let menuBar = MenuBar()
        menuBar.addMenu(fileMenu)
        menuBar.addMenu(themeMenu)
        // Span the full width so the whole menu row is gray chrome, not just the
        // titles' width (trailing: 0 stretches it edge-to-edge).
        menuBar.anchors = AnchorSet(leading: 0, trailing: 0, top: 0, height: 1)
        menuWindow.addSubview(menuBar)
        menuWindow.menuBar = menuBar
        menuWindow.makeFirstResponder(menuBar)

        // Global status bar along the very bottom, hosting the chrome labels
        // declared above and a live clock (a second use of the App timer).
        let clockFormatter = DateFormatter()
        clockFormatter.dateFormat = "HH:mm:ss"
        func refreshClock() { clock.text = clockFormatter.string(from: Date()) }
        refreshClock()
        app.addTimer(every: .seconds(1)) { refreshClock() }

        let globalStatus = StatusBar()
        globalStatus.showsSeparators = false   // Borland-style: one flat strip, no │ dividers
        globalStatus.addSegment(statusTitle, minimumWidth: 14)
        globalStatus.addSegment(statusHint, percentage: 100)
        globalStatus.addSegment(clock, minimumWidth: 10)
        globalStatus.anchors = AnchorSet(leading: 0, trailing: 0, bottom: 0, height: 1)
        menuWindow.addSubview(globalStatus)

        styleStatusChrome()   // initial pass, matching the startup theme

        // Load the global contact list once, at startup.
        ContactStore.shared.loadIfNeeded()

        // The declarative example is the default; a Contact Book opens beside it so
        // the new feature is visible. File ▸ New… opens more of any kind.
        // `present` stacks a window on the desktop (last one is "key" / focused).
        app.present(makeDeclarativeExample(index: 0))
        app.present(makeContactBook(index: 0))

        // `app.run` takes over the terminal and loops until stopped. We pass the
        // menu-bar window as the initial/root window: it fills the screen but is
        // click-through except for its bar (see MenuBarWindow.hitTest), so the
        // example windows presented above sit "on top" and stay interactive.
        // Without a real TTY (e.g. piped output) the driver throws — we catch it
        // and exit cleanly so `swift run` doesn't crash in CI.
        do {
            try await app.run(menuWindow)
        } catch {
            print("Interactive mode needs a real terminal (\(error)).")
            return
        }

        print("Restored terminal.")
    }
}

/// Full-screen root window that draws only its top row — the menu bar
/// strip. Everything below stays desktop, with floating windows overlapping
/// freely; menu dropdowns still open below the bar because they are this
/// window's subviews.
@MainActor
final class MenuBarWindow: Window {
    var onQuit: () -> Void = {}

    /// While one of its menus is open, Esc closes the menu instead of
    /// quitting.
    weak var menuBar: MenuBar?

    /// The menu row (top) and the global status row (bottom) get a solid
    /// backing; the desktop shows through everything between.
    override func draw(_ painter: Painter) {
        painter.fill(
            Rect(x: 0, y: 0, width: bounds.size.width, height: 1),
            with: .blank
        )
        painter.fill(
            Rect(x: 0, y: bounds.size.height - 1, width: bounds.size.width, height: 1),
            with: .blank
        )
    }

    /// Claim only the bar row and open dropdowns; everywhere else is
    /// click-through, so clicks reach the floating windows behind.
    override func hitTest(_ point: Point) -> (view: TUIView, local: Point)? {
        guard let hit = super.hitTest(point) else {
            return nil
        }

        if hit.view === self, point.y > 0 {
            return nil
        }

        return hit
    }

    /// Esc quits from anywhere via the hot-key pass (before focused views),
    /// unless a menu is open — then the dropdown handles it.
    override func handleHotKey(_ key: KeyInput) -> Bool {
        if key.key == .escape, key.modifiers.isEmpty {
            if menuBar?.isMenuOpen == true {
                return false
            }

            onQuit()
            return true
        }

        return false
    }
}

