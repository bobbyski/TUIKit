import Foundation
import TUIKit

/// The gallery's OmegaCLIDE-form shell: menu bar strip on top, the gallery
/// window floating on the desktop, a status strip along the bottom. Boots
/// into Modern Turbo; the Theme menu re-dresses everything live.
@MainActor
final class GalleryApp {
    let app = App(driver: ANSIDriver())
    let settings = GallerySettings(store: Preferences(suite: "com.tuikit.gallery"))
    private var windowCount = 0

    func run() async throws {
        let app = self.app

        // Backdrop for themes that don't paint their own desktop (their
        // desktop-context background resolves `.standard`) — without it the
        // terminal default shows through and reads as a hole.
        let neutralBackdrop = TerminalColor.rgb(red: 128, green: 128, blue: 128)

        let shell = GalleryShellWindow()
        shell.onQuit = { app.stop() }

        // Status strip content, declared early so the theme path can
        // restyle it.
        let statusTitle = Label(" TUIKit Gallery")
        let statusHint = Label("Tab ↹ moves focus · ^L controls panel · Theme menu restyles")
        let clock = Label("--:--:--")

        func styleStatusChrome() {
            let header = shell.effectiveTheme.header
            statusTitle.style = header
            var plain = header
            plain.flags.remove(.bold)
            statusHint.style = plain
            clock.style = plain
        }

        // The one theming path, used at boot, by every Theme menu item, and
        // by the preferences dialog's Appearance page.
        func applyGalleryTheme(_ theme: Theme) {
            app.applyTheme(theme)

            let backdrop = theme.resolved(for: .desktop).background
            app.desktop.fillStyle = CellStyle(
                background: backdrop == .standard ? neutralBackdrop : backdrop
            )

            styleStatusChrome()
        }

        let settings = self.settings
        settings.applyTheme = applyGalleryTheme
        settings.setHintsVisible = { [weak statusHint] visible in
            statusHint?.text = visible ? "Tab ↹ moves focus · ^L controls panel · Theme menu restyles" : ""
        }

        // File: more gallery windows, preferences, close, quit.
        let fileMenu = Menu("&File")
        fileMenu.addItem("&New Gallery Window", keyEquivalent: KeyInput(key: .character("n"), modifiers: .control)) {
            self.windowCount += 1
            app.present(makeGalleryWindow(index: self.windowCount, app: app, settings: settings))
        }
        fileMenu.addSeparator()
        fileMenu.addItem("&Preferences…", keyEquivalent: KeyInput(key: .character("p"), modifiers: .control)) {
            settings.presentPreferences(in: app)
        }
        fileMenu.addSeparator()
        fileMenu.addItem("&Close Window", keyEquivalent: KeyInput(key: .character("w"), modifiers: .control)) {
            if let target = app.windows.last(where: { $0 !== shell }) {
                app.dismiss(target)
            }
        }
        fileMenu.addSeparator()
        fileMenu.addItem("&Quit", keyEquivalent: KeyInput(key: .character("q"), modifiers: .control)) {
            app.stop()
        }

        // Theme: every built-in, so the gallery doubles as the theme tour.
        let themeMenu = Menu("&Theme")
        for (name, theme) in TUIKit.Theme.builtIn {
            themeMenu.addItem(name) {
                applyGalleryTheme(theme)
            }
        }

        // View: the Controls slide-out of the frontmost gallery window — the
        // menu's equivalent of ^L and the [>] title button.
        let viewMenu = Menu("&View")
        viewMenu.addItem("Toggle &Controls Panel", keyEquivalent: KeyInput(key: .character("l"), modifiers: .control)) {
            (app.windows.last { $0 is GalleryWindow } as? GalleryWindow)?.toggleSlideOut(.leading)
        }

        let menuBar = MenuBar()
        menuBar.addMenu(fileMenu)
        menuBar.addMenu(viewMenu)
        menuBar.addMenu(themeMenu)
        menuBar.anchors = AnchorSet(leading: 0, trailing: 0, top: 0, height: 1)
        shell.addSubview(menuBar)
        shell.menuBar = menuBar
        shell.makeFirstResponder(menuBar)

        // Status strip with a live clock.
        let clockFormatter = DateFormatter()
        clockFormatter.dateFormat = "HH:mm:ss"
        func refreshClock() { clock.text = clockFormatter.string(from: Date()) }
        refreshClock()
        app.addTimer(every: .seconds(1)) { refreshClock() }

        let status = StatusBar()
        status.showsSeparators = false
        status.addSegment(statusTitle, minimumWidth: 16)
        status.addSegment(statusHint, percentage: 100)
        status.addSegment(clock, minimumWidth: 10)
        status.anchors = AnchorSet(leading: 0, trailing: 0, bottom: 0, height: 1)
        shell.addSubview(status)

        // Boot look: the remembered theme, else Modern Turbo — via the same
        // path the menu and the preferences dialog take.
        applyGalleryTheme(settings.storedTheme ?? .modernTurbo)
        settings.setHintsVisible(settings.showsHints)

        app.present(makeGalleryWindow(index: 0, app: app, settings: settings))

        do {
            try await app.run(shell)
        } catch {
            print("The gallery needs a real terminal (\(error)).")
            return
        }

        print("Restored terminal.")
    }
}

/// Full-screen root window that draws only its top (menu) and bottom
/// (status) rows; everything between is click-through desktop, so the
/// gallery window floats freely and stays interactive.
@MainActor
final class GalleryShellWindow: Window {
    var onQuit: () -> Void = {}

    /// While a menu is open, Esc closes it instead of quitting.
    weak var menuBar: MenuBar?

    override func draw(_ painter: Painter) {
        painter.fill(Rect(x: 0, y: 0, width: bounds.size.width, height: 1), with: .blank)
        painter.fill(Rect(x: 0, y: bounds.size.height - 1, width: bounds.size.width, height: 1), with: .blank)
    }

    /// Claim only the bar rows and open dropdowns; everywhere else clicks
    /// fall through to the windows behind.
    override func hitTest(_ point: Point) -> (view: TUIView, local: Point)? {
        guard let hit = super.hitTest(point) else {
            return nil
        }

        if hit.view === self, point.y > 0, point.y < bounds.size.height - 1 {
            return nil
        }

        return hit
    }

    /// Esc quits from anywhere — unless a dropdown is open, which owns it.
    override func handleHotKey(_ key: KeyInput) -> Bool {
        if key.key == .escape, key.modifiers.isEmpty {
            if menuBar?.isMenuOpen == true {
                return false
            }

            onQuit()
            return true
        }

        return super.handleHotKey(key)
    }
}
