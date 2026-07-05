import Testing
@testable import TUIKit

@Test @MainActor func applyThemeThemesDesktopAndEveryWindow() {
    let app = App(driver: HeadlessDriver(size: Size(width: 20, height: 10)))

    let a = Window(frame: Rect(x: 0, y: 0, width: 8, height: 4))
    let b = Window(frame: Rect(x: 0, y: 0, width: 8, height: 4))
    b.theme = .dark   // a pre-existing per-window override
    app.present(a)
    app.present(b)

    app.applyTheme(.homebrew)

    // The desktop is the single app-wide anchor; window overrides are cleared
    // so both windows inherit it.
    #expect(app.desktop.theme == .homebrew)
    #expect(a.theme == nil)
    #expect(b.theme == nil, "applyTheme clears prior per-window overrides")
    #expect(a.effectiveTheme == Theme.homebrew.resolved())
    #expect(b.effectiveTheme == Theme.homebrew.resolved())
}

@Test @MainActor func applyThemeLeavesDeepControlOverridesIntact() {
    let app = App(driver: HeadlessDriver(size: Size(width: 20, height: 10)))

    let window = Window(frame: Rect(x: 0, y: 0, width: 8, height: 4))
    let pinned = Label("x")
    pinned.theme = .standard        // a deliberate local exception
    window.addSubview(pinned)
    app.present(window)

    app.applyTheme(.homebrew)

    // The app theme cascades, but a control that pinned its own theme keeps it.
    #expect(window.effectiveTheme == Theme.homebrew.resolved())
    #expect(pinned.effectiveTheme == Theme.standard.resolved(), "a per-control override survives an app theme")
}

@Test @MainActor func windowsPresentedAfterApplyThemeInheritIt() {
    let app = App(driver: HeadlessDriver(size: Size(width: 20, height: 10)))
    app.applyTheme(.homebrew)

    let late = Window(frame: Rect(x: 0, y: 0, width: 8, height: 4))
    app.present(late)

    #expect(late.effectiveTheme == Theme.homebrew.resolved(), "a later window inherits the app theme")
}
