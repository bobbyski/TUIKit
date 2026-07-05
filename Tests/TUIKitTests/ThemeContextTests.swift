import Testing
@testable import TUIKit

// `effectiveTheme` resolves a view's *context* by walking up the superview
// chain (like the theme itself). A "rainbow" theme — every context a distinct
// sentinel background — makes any mis-resolution observable (nil→base can't
// mask it, since each context differs from base).

@MainActor
private func rainbowTheme() -> Theme {
    func palette(_ v: UInt8) -> ThemePalette {
        var p = ThemePalette()
        p.background = .rgb(red: v, green: v, blue: v)
        p.foreground = .rgb(red: v, green: v, blue: v)
        return p
    }

    return Theme(
        name: "Rainbow",
        base: palette(0),
        desktop: palette(10),
        contentWindow: palette(20),
        secondaryWindows: palette(30),
        modalWindows: palette(40),
        accessoryView: palette(50)
    )
}

private func rgb(_ v: UInt8) -> TerminalColor { .rgb(red: v, green: v, blue: v) }

@Test @MainActor func effectiveThemeResolvesContextUpTheTree() {
    let root = TUIView()
    root.theme = rainbowTheme()   // theme lives at the root, no context (→ base)

    let content = TUIView()
    content.themeContext = .contentWindow
    root.addSubview(content)

    let leaf = TUIView()          // nil context — inherits the parent's
    content.addSubview(leaf)

    let sidebar = TUIView()
    sidebar.themeContext = .desktop
    root.addSubview(sidebar)

    #expect(root.effectiveTheme.background == rgb(0), "root: no context → base")
    #expect(content.effectiveTheme.background == rgb(20), "contentWindow context")
    #expect(leaf.effectiveTheme.background == rgb(20), "nil child inherits its ancestor's context")
    #expect(sidebar.effectiveTheme.background == rgb(10), "sibling desktop context — no leak from content's subtree")
}

@Test @MainActor func accessoryContextAppliesToItsSubtreeOnly() {
    let root = TUIView()
    root.theme = rainbowTheme()

    let editor = TUIView()
    editor.themeContext = .contentWindow
    root.addSubview(editor)

    let inspector = TUIView()
    inspector.themeContext = .accessoryView
    editor.addSubview(inspector)

    let inspectorChild = TUIView()   // nil — inherits accessoryView, not contentWindow
    inspector.addSubview(inspectorChild)

    #expect(editor.effectiveTheme.background == rgb(20))
    #expect(inspector.effectiveTheme.background == rgb(50), "accessory resolves its own context")
    #expect(inspectorChild.effectiveTheme.background == rgb(50),
            "child inherits the accessoryView context, not the enclosing contentWindow")
}

@Test @MainActor func settingAContextRestylesOnlyThatSubtree() {
    let root = TUIView()
    root.theme = rainbowTheme()

    let a = TUIView()
    root.addSubview(a)
    let b = TUIView()
    root.addSubview(b)

    #expect(a.effectiveTheme.background == rgb(0), "both start at base")
    #expect(b.effectiveTheme.background == rgb(0))

    a.themeContext = .modalWindows

    #expect(a.effectiveTheme.background == rgb(40), "a's subtree switches")
    #expect(b.effectiveTheme.background == rgb(0), "b is untouched")
}

@Test @MainActor func nilChildResolvesAncestorContextAfterItsOwnRefresh() {
    // The case that drives the parent-link decision: a refresh requested *from*
    // a nil-context child must still resolve the ancestor's context.
    let root = TUIView()
    root.theme = rainbowTheme()

    let modal = TUIView()
    modal.themeContext = .modalWindows
    root.addSubview(modal)

    let deep = TUIView()   // nil context, deep inside the modal subtree
    modal.addSubview(deep)

    deep.setNeedsDisplay()   // the child asks to redraw itself

    #expect(deep.effectiveTheme.background == rgb(40),
            "the nil child resolves the modal context via the parent walk, not base")
}

@Test @MainActor func reparentingAViewReResolvesItsContext() {
    let root = TUIView()
    root.theme = rainbowTheme()

    let contentPane = TUIView()
    contentPane.themeContext = .contentWindow
    root.addSubview(contentPane)

    let desktopPane = TUIView()
    desktopPane.themeContext = .desktop
    root.addSubview(desktopPane)

    let mover = TUIView()   // nil context — takes on whichever parent it's under
    contentPane.addSubview(mover)
    #expect(mover.effectiveTheme.background == rgb(20), "under contentWindow")

    desktopPane.addSubview(mover)   // move it
    #expect(mover.effectiveTheme.background == rgb(10), "after reparenting, resolves the new ancestor's context")
}
