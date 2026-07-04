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

@Test @MainActor func turboThemeResolvesGrayBaseAndBlueContentWindow() {
    #expect(Theme.builtIn.contains { $0.name == "Turbo" })
    // Double border is reserved for floating window frames; base (menus,
    // interior lines) is single.
    #expect(Theme.turbo.base.borderStyle == .single)
    #expect(Theme.turbo.contentWindow?.borderStyle == .double)
    #expect(Theme.turbo.secondaryWindows?.borderStyle == .double)

    let panel = TUIKit.Panel("Edit")
    panel.theme = .turbo
    let window = Window(frame: Rect(x: 0, y: 0, width: 12, height: 4))
    panel.frame = window.bounds
    window.addSubview(panel)

    // No context → the gray `base`, white *single* border.
    var buffer = SceneRenderer(root: window).render(size: Size(width: 12, height: 4))
    let corner = buffer[Point(x: 0, y: 0)]
    #expect(corner.character == "┌", "interior/menu borders are single")
    #expect(corner.style.foreground == .rgb(red: 255, green: 255, blue: 255))
    #expect(corner.style.background == .rgb(red: 170, green: 170, blue: 170), "base is the gray surface")
    #expect(buffer[Point(x: 1, y: 1)].style.background == .rgb(red: 170, green: 170, blue: 170))

    // The contentWindow context resolves the blue editor look with a double frame.
    panel.themeContext = .contentWindow
    buffer = SceneRenderer(root: window).render(size: Size(width: 12, height: 4))
    #expect(buffer[Point(x: 0, y: 0)].character == "╔", "floating window frames are double")
    #expect(buffer[Point(x: 0, y: 0)].style.background == .rgb(red: 0, green: 0, blue: 170), "editor blue")
    #expect(buffer[Point(x: 1, y: 1)].style.background == .rgb(red: 0, green: 0, blue: 170))
}

@Test func borderTeeMixesFrameAndDividerStyles() {
    // A single interior line meeting a double frame → mixed tee.
    #expect(BorderStyle.double.tee(.left, nub: .single) == "╟")
    #expect(BorderStyle.double.tee(.right, nub: .single) == "╢")
    #expect(BorderStyle.double.tee(.top, nub: .single) == "╤")
    #expect(BorderStyle.double.tee(.bottom, nub: .single) == "╧")
    // Same style on both sides → the standard junctions.
    #expect(BorderStyle.single.tee(.left, nub: .single) == "├")
    #expect(BorderStyle.double.tee(.left, nub: .double) == "╠")
    // The other mix, and no border.
    #expect(BorderStyle.single.tee(.left, nub: .double) == "╞")
    #expect(BorderStyle.none.tee(.left, nub: .single) == nil)
}

@Test @MainActor func turboInteriorLinesStaySingleInDoubleFrameContexts() {
    // Frames double, interior lines single — even inside a double-framed window.
    #expect(Theme.turbo.resolved(for: .contentWindow).borderStyle == .double)
    #expect(Theme.turbo.resolved(for: .contentWindow).dividerStyle == .single)

    let window = Window(frame: Rect(x: 0, y: 0, width: 6, height: 3))
    window.theme = .turbo
    window.themeContext = .contentWindow

    let divider = Divider(axis: .vertical)
    divider.frame = Rect(x: 2, y: 0, width: 1, height: 3)
    window.addSubview(divider)

    let buffer = SceneRenderer(root: window).render(size: Size(width: 6, height: 3))
    #expect(buffer[Point(x: 2, y: 1)].character == "│", "interior divider is single, not the double frame's ║")
}

@Test @MainActor func dividerConnectionControlsWelding() {
    let welded = Theme.standard                       // default → welded
    var flat = Theme.standard
    flat.base.dividerConnection = .notWelded

    #expect(welded.resolved().dividerConnection == .welded, "default is welded")
    #expect(flat.resolved().dividerConnection == .notWelded)

    // A horizontal divider spanning the content welds into the left border with
    // a tee — unless the theme says notWelded, then the border stays plain.
    func leftBorderAtDividerRow(_ theme: Theme) -> Character {
        let panel = Panel("P")
        panel.theme = theme
        panel.frame = Rect(x: 0, y: 0, width: 10, height: 5)
        let divider = Divider(axis: .horizontal)
        divider.frame = Rect(x: 0, y: 1, width: 8, height: 1)   // spans the content width
        panel.content.addSubview(divider)

        let window = Window(frame: panel.frame)
        window.addSubview(panel)
        return SceneRenderer(root: window).render(size: Size(width: 10, height: 5))[Point(x: 0, y: 2)].character
    }

    #expect(leftBorderAtDividerRow(welded) == "├", "welded → the divider welds into the border")
    #expect(leftBorderAtDividerRow(flat) == "│", "notWelded → plain border, no tee")
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

    #expect(panel.effectiveTheme == Theme.manPage.resolved())
    #expect(outside.effectiveTheme == Theme.dark.resolved())

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

@Test @MainActor func surfaceHelperDerivesTheSlots() {
    let resolved = TUIKit.Theme
        .surface("T", background: .named(.black), foreground: .named(.white), accent: .named(.cyan))
        .resolved()

    #expect(resolved.base == CellStyle(foreground: .named(.white), background: .named(.black)))
    #expect(resolved.selection == CellStyle(foreground: .named(.black), background: .named(.cyan)))
    #expect(resolved.headerForeground == .named(.cyan))
    #expect(resolved.headerAttributes.contains(.bold))
    #expect(resolved.placeholderAttributes.contains(.dim))

    // The standard theme adds no color anywhere — selection is inverse.
    let standard = TUIKit.Theme.standard.resolved()
    #expect(standard.selection == CellStyle(flags: .inverse))
    #expect(standard.base == CellStyle())
}
