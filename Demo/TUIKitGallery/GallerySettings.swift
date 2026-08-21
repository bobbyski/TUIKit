import Foundation
import TUIKit

/// The gallery's real preferences: a `Preferences` suite on disk and the
/// `PreferencesDialog` that edits it — reached from the toolbar's Settings
/// button and File ▸ Preferences…, the way an app would do it.
///
/// Keys: `theme` (a built-in theme name), `controlsPanelOpen` (whether the
/// Controls slide-out starts open), `showsHints` (the status-bar hint).
@MainActor
final class GallerySettings {
    let store: Preferences

    /// Re-dresses the app; installed by the shell, used by the Appearance page.
    var applyTheme: (Theme) -> Void = { _ in }

    /// Shows or hides the status-bar hint; installed by the shell.
    var setHintsVisible: (Bool) -> Void = { _ in }

    init(store: Preferences) {
        self.store = store
    }

    /// The stored theme, if it names a built-in one.
    var storedTheme: Theme? {
        guard let name = store.string(forKey: "theme") else {
            return nil
        }

        return Theme.builtIn.first { $0.name == name }?.theme
    }

    var controlsPanelOpen: Bool {
        get { store.bool(forKey: "controlsPanelOpen") ?? false }
        set { store.set(newValue, forKey: "controlsPanelOpen") }
    }

    var showsHints: Bool {
        get { store.bool(forKey: "showsHints") ?? true }
        set { store.set(newValue, forKey: "showsHints") }
    }

    /// Presents the preferences dialog — the same pages in either selector
    /// style (the toolbar strip is the default; the split list is the
    /// legacy look).
    func presentPreferences(in app: App, style: PreferencesDialog.SelectorStyle = .toolbar) {
        let dialog = PreferencesDialog(style: style)

        // General: the two behaviours the gallery itself reads.
        let panel = Checkbox("Open the Controls panel at launch", isChecked: controlsPanelOpen)
        panel.onChange = { [weak self] in self?.controlsPanelOpen = $0 }
        let hints = Checkbox("Show the status-bar hint", isChecked: showsHints)
        hints.onChange = { [weak self] in
            self?.showsHints = $0
            self?.setHintsVisible($0)
        }
        let general = Form(spacing: 0) {
            Field("Startup") { panel }
            Field("Status bar") { hints }
        }

        // Appearance: the theme, applied live and remembered.
        let names = Theme.builtIn.map(\.name)
        let current = store.string(forKey: "theme").flatMap { names.firstIndex(of: $0) } ?? (names.firstIndex(of: "Modern Turbo") ?? 0)
        let themePopUp = PopUpButton(items: names, selectedIndex: current)
        themePopUp.onSelectionChanged = { [weak self] index in
            guard let self, names.indices.contains(index) else { return }
            self.store.set(names[index], forKey: "theme")
            self.applyTheme(Theme.builtIn[index].theme)
        }
        let appearance = Form(spacing: 0) {
            Field("Theme") { themePopUp }
        }

        dialog.addPage("General", icon: "⚙", content: general)
        dialog.addPage("Appearance", icon: "✎", content: appearance)
        dialog.addButton("&Done", isDefault: true)
        dialog.onDismiss = { [weak dialog, weak app] in
            if let dialog, let app {
                app.dismiss(dialog)
            }
        }
        dialog.sizeToFit(in: app.desktop.bounds.size)
        app.present(dialog)
        dialog.sizeToFit(in: app.desktop.bounds.size)
    }
}
