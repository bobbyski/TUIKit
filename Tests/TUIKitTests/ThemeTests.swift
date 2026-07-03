import Testing
@testable import TUIKit

@Test @MainActor func painterResolvesStandardColorsToTheThemeBase() {
    let window = Window(frame: Rect(x: 0, y: 0, width: 10, height: 2))
    window.theme = .homebrew

    let plain = Label("hi")
    plain.frame = Rect(x: 0, y: 0, width: 4, height: 1)
    window.addSubview(plain)

    let red = Label("no", style: CellStyle(foreground: .named(.red)))
    red.frame = Rect(x: 0, y: 1, width: 4, height: 1)
    window.addSubview(red)

    let buffer = SceneRenderer(root: window).render(size: Size(width: 10, height: 2))

    // Standard colors resolve to the theme's palette…
    let themed = buffer[Point(x: 0, y: 0)].style
    #expect(themed.foreground == .rgb(red: 40, green: 254, blue: 20))
    #expect(themed.background == .rgb(red: 0, green: 0, blue: 0))

    // …the window fill too, and explicit colors pass through untouched.
    #expect(buffer[Point(x: 9, y: 0)].style.background == .rgb(red: 0, green: 0, blue: 0))
    #expect(buffer[Point(x: 0, y: 1)].style.foreground == .named(.red))
    #expect(buffer[Point(x: 0, y: 1)].style.background == .rgb(red: 0, green: 0, blue: 0))
}

@Test @MainActor func nearestAncestorThemeWins() {
    let window = Window(frame: Rect(x: 0, y: 0, width: 20, height: 3))
    window.theme = .dark

    let outside = Label("out")
    outside.frame = Rect(x: 0, y: 2, width: 3, height: 1)
    window.addSubview(outside)

    let panel = Panel("P")
    panel.theme = .manPage
    panel.frame = Rect(x: 0, y: 0, width: 12, height: 2)
    window.addSubview(panel)

    #expect(panel.effectiveTheme == .manPage)
    #expect(outside.effectiveTheme == .dark)

    let buffer = SceneRenderer(root: window).render(size: Size(width: 20, height: 3))

    // Panel interior wears Man Page paper; the outside label stays dark.
    #expect(buffer[Point(x: 1, y: 1)].style.background == .rgb(red: 254, green: 244, blue: 156))
    #expect(buffer[Point(x: 0, y: 2)].style.background == .rgb(red: 30, green: 30, blue: 30))
    #expect(buffer[Point(x: 0, y: 2)].style.foreground == .rgb(red: 220, green: 220, blue: 220))
}

@Test @MainActor func selectionUsesTheThemeSlot() {
    let window = Window(frame: Rect(x: 0, y: 0, width: 12, height: 3))
    window.theme = .ocean

    let list = ListView(items: ["alpha", "beta"])
    list.frame = window.bounds
    window.addSubview(list)
    list.select(0)

    let buffer = SceneRenderer(root: window).render(size: Size(width: 12, height: 3))
    let selected = buffer[Point(x: 0, y: 0)].style

    // Ocean selection: background color on the accent.
    #expect(selected.background == .rgb(red: 126, green: 190, blue: 255))
    #expect(selected.foreground == .rgb(red: 34, green: 79, blue: 188))

    let unselected = buffer[Point(x: 0, y: 1)].style
    #expect(unselected.background == .rgb(red: 34, green: 79, blue: 188))
}

@Test @MainActor func themeSwitchingRepaintsTheSubtree() {
    let window = Window(frame: Rect(x: 0, y: 0, width: 8, height: 2))
    window.theme = .dark

    let renderer = SceneRenderer(root: window)
    _ = renderer.render(size: Size(width: 8, height: 2))
    #expect(renderer.renderIfNeeded(size: Size(width: 8, height: 2)) == nil, "clean after a render")

    window.theme = .light
    let repainted = renderer.renderIfNeeded(size: Size(width: 8, height: 2))

    #expect(repainted != nil, "assigning a theme dirties the subtree")
    #expect(repainted?[Point(x: 0, y: 0)].style.background == .rgb(red: 250, green: 250, blue: 250))
}

@Test @MainActor func paletteInitializerDerivesTheSlots() {
    let theme = TUIKit.Theme(   // qualified: RichSwift also has a Theme
        background: .named(.black),
        foreground: .named(.white),
        accent: .named(.cyan)
    )

    #expect(theme.base == CellStyle(foreground: .named(.white), background: .named(.black)))
    #expect(theme.selection == CellStyle(foreground: .named(.black), background: .named(.cyan)))
    #expect(theme.header.foreground == .named(.cyan))
    #expect(theme.header.flags.contains(.bold))
    #expect(theme.placeholder.flags.contains(.dim))

    // The standard theme adds no color anywhere — selection is inverse.
    #expect(TUIKit.Theme.standard.selection == CellStyle(flags: .inverse))
    #expect(TUIKit.Theme.standard.base == CellStyle())
}
