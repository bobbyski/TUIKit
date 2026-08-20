import Testing
@testable import TUIKit

@Test @MainActor func styleSheetParsesRulesTolerantly() {
    let sheet = StyleSheet("""
        /* a comment */
        Button { color: red; bold: true; }
        .warning, #save { color: brightYellow; }
        nonsense without braces
        Label { mystery-property: 12; color: #102030; }
        Broken { color: notacolor; }
    """)

    #expect(sheet.rules.count == 3)
    #expect(sheet.rules[0].declarations.count == 2)
    #expect(sheet.rules[1].selectors.count == 2)

    // CSS is open-ended: the unknown property is KEPT (typed by its value's
    // shape, headed for `theme.custom`); a KNOWN property with a value that
    // cannot be what the slot needs is still skipped.
    #expect(sheet.rules[2].declarations.count == 2, "unknown properties parse; they are the app's")
    #expect(sheet.rules[2].declarations[0] == StyleDeclaration(name: "mystery-property", value: .text("12")))
}

@Test @MainActor func selectorsMatchTypeIdClassFocusAndDescendants() {
    let window = Window(frame: Rect(x: 0, y: 0, width: 20, height: 6))
    let panel = Panel("P")
    let button = Button("Go")
    button.identifier = "go"
    button.styleClasses = ["primary", "wide"]
    panel.content.addSubview(button)
    window.addSubview(panel)

    func matches(_ text: String) -> Bool {
        StyleSelector(parsing: text)!.matches(button)
    }

    #expect(matches("Button"))
    #expect(!matches("Label"))
    #expect(matches("#go"))
    #expect(matches(".primary"))
    #expect(matches(".primary.wide"))
    #expect(!matches(".primary.missing"))
    #expect(matches("Button#go.primary"))
    #expect(matches("Panel Button"))
    #expect(matches("Window Panel .primary"))
    #expect(!matches("ListView Button"))

    #expect(!matches("Button:focused"))
    window.makeFirstResponder(button)
    #expect(matches("Button:focused"))

    #expect(StyleSelector(parsing: "#go")!.specificity == 100)
    #expect(StyleSelector(parsing: "Button.primary:focused")!.specificity == 21)
    #expect(StyleSelector(parsing: "Panel Button")!.specificity == 2)
}

@Test @MainActor func styleSheetResolvesThroughTheEffectiveTheme() {
    let window = Window(frame: Rect(x: 0, y: 0, width: 20, height: 4))
    window.styleSheet = StyleSheet("""
        Label   { color: cyan; }
        .warning { color: brightYellow; bold: true; }
        #alarm  { color: brightRed; }
    """)

    let plain = Label("a")
    let warning = Label("b")
    warning.styleClasses = ["warning"]
    let alarm = Label("c")
    alarm.styleClasses = ["warning"]
    alarm.identifier = "alarm"

    for (index, label) in [plain, warning, alarm].enumerated() {
        label.frame = Rect(x: 0, y: index, width: 4, height: 1)
        window.addSubview(label)
    }

    #expect(plain.effectiveTheme.base.foreground == .named(.cyan))
    #expect(warning.effectiveTheme.base.foreground == .named(.brightYellow))
    #expect(warning.effectiveTheme.base.flags.contains(.bold))
    #expect(alarm.effectiveTheme.base.foreground == .named(.brightRed), "id outranks class")
    #expect(alarm.effectiveTheme.base.flags.contains(.bold), "lower-specificity declarations still apply")

    // And the painter picks it up with no control involvement.
    let buffer = SceneRenderer(root: window).render(size: Size(width: 20, height: 4))
    #expect(buffer[Point(x: 0, y: 0)].style.foreground == .named(.cyan))
    #expect(buffer[Point(x: 0, y: 1)].style.foreground == .named(.brightYellow))
    #expect(buffer[Point(x: 0, y: 2)].style.foreground == .named(.brightRed))
}

@Test @MainActor func innerSheetsOverrideOuterOnesAndSlotsApply() {
    let window = Window(frame: Rect(x: 0, y: 0, width: 12, height: 3))
    window.theme = .ocean
    window.styleSheet = StyleSheet("ListView { selection-background: #101010; }")

    let list = ListView(items: ["alpha", "beta"])
    list.styleSheet = StyleSheet("ListView { selection-background: #aa5500; }")
    list.frame = window.bounds
    window.addSubview(list)
    list.select(0)

    #expect(list.effectiveTheme.selection.background == .rgb(red: 0xaa, green: 0x55, blue: 0))
    #expect(
        list.effectiveTheme.base == TUIKit.Theme.ocean.resolved().base,
        "the inherited theme survives underneath the sheet"
    )

    let buffer = SceneRenderer(root: window).render(size: Size(width: 12, height: 3))
    #expect(buffer[Point(x: 0, y: 0)].style.background == .rgb(red: 0xaa, green: 0x55, blue: 0))
}

@Test @MainActor func borderStylesAndSlotBackgroundsApply() {
    let window = Window(frame: Rect(x: 0, y: 0, width: 20, height: 5))
    window.styleSheet = StyleSheet("""
        Panel { border: double; border-color: cyan; header-background: blue; }
    """)

    let panel = Panel("Files")
    panel.anchors = .fill()
    window.addSubview(panel)

    #expect(panel.effectiveTheme.borderStyle == .double)

    let buffer = SceneRenderer(root: window).render(size: Size(width: 20, height: 5))
    let lines = buffer.textLines()

    #expect(lines[0].hasPrefix("╔═ Files "))
    #expect(lines[0].hasSuffix("╗"))
    #expect(lines[4].hasPrefix("╚"))
    #expect(Array(lines[1])[0] == "║")

    #expect(buffer[Point(x: 0, y: 0)].style.foreground == .named(.cyan))
    #expect(buffer[Point(x: 3, y: 0)].style.background == .named(.blue), "header-background colors the title")

    // An inner sheet can remove the border entirely; the title remains.
    panel.styleSheet = StyleSheet("Panel { border: none; }")
    let bare = SceneRenderer(root: window).render(size: Size(width: 20, height: 5)).textLines()

    #expect(bare[0].contains("Files"))
    #expect(!bare[0].contains("╔"))
    #expect(!bare[1].contains("║"))
}

@Test @MainActor func borderStyleWorksDirectlyOnThemes() {
    var theme = TUIKit.Theme.standard
    theme.base.borderStyle = .rounded

    let window = Window(frame: Rect(x: 0, y: 0, width: 12, height: 4))
    window.theme = theme

    let panel = Panel("R")
    panel.anchors = .fill()
    window.addSubview(panel)

    let lines = SceneRenderer(root: window).render(size: Size(width: 12, height: 4)).textLines()
    #expect(lines[0].hasPrefix("╭"))
    #expect(lines[0].hasSuffix("╮"))
    #expect(lines[3].hasPrefix("╰"))
    #expect(lines[3].hasSuffix("╯"))
}

@Test @MainActor func stylesheetTogglesOnAndOffOverAChosenTheme() {
    // 8.15: CSS is an on-top layer, orthogonal to the theme. Toggling it off is
    // just `styleSheet = nil`, and the theme underneath is never touched.
    let window = Window(frame: Rect(x: 0, y: 0, width: 8, height: 2))
    window.theme = .ocean

    let label = Label("hi")
    window.addSubview(label)

    #expect(label.effectiveTheme.background == Theme.ocean.resolved().background, "CSS off → the pure theme")

    // CSS on → overrides just the background; other slots keep the theme.
    window.styleSheet = StyleSheet("Label { background: #112233; }")
    #expect(label.effectiveTheme.background == .rgb(red: 0x11, green: 0x22, blue: 0x33))
    #expect(label.effectiveTheme.accent == Theme.ocean.resolved().accent, "unset slots stay the theme's")

    // Toggle off (= nil) → back to the theme exactly.
    window.styleSheet = nil
    #expect(label.effectiveTheme.background == Theme.ocean.resolved().background)
}

@Test @MainActor func withoutSheetsEverythingIsUnchanged() {
    let window = Window(frame: Rect(x: 0, y: 0, width: 8, height: 2))
    window.theme = .homebrew

    let label = Label("hi")
    label.frame = Rect(x: 0, y: 0, width: 4, height: 1)
    window.addSubview(label)

    #expect(label.effectiveTheme == Theme.homebrew.resolved(), "no sheets → exactly the inherited theme")
    #expect(label.identifier == nil)
    #expect(label.styleClasses.isEmpty)
    #expect(label.styleSheet == nil)
}

// MARK: - Open-ended CSS + the chrome/chart vocabulary

@Test @MainActor func stylesheetsAreOpenEndedNotRestrictedToKnownProperties() {
    // An application invents its own properties; TUIKit keeps them, typed
    // by shape, on the resolved theme it hands back.
    let view = TUIView()
    view.styleSheet = StyleSheet("""
    TUIView {
        glow-color: #ff8800;
        panel-mode: compact;
        pulse: true;
        accent: brightCyan;
    }
    """)

    let theme = view.effectiveTheme
    #expect(theme.customColor("glow-color") == .rgb(red: 255, green: 136, blue: 0))
    #expect(theme.custom["panel-mode"] == .text("compact"))
    #expect(theme.custom["pulse"] == .flag(true))
    #expect(theme.accent == .named(.brightCyan), "known names still write their slots")
}

@Test @MainActor func secondaryAccentTintsToolbarsAndFallsBackToAccent() {
    // Unset anywhere: the secondary accent IS the accent, so themes that
    // predate the slot keep their look.
    #expect(Theme.dark.resolved().secondaryAccent == Theme.dark.resolved().accent)

    // Turbo's content window: toolbar tint blue, while the accent stays the
    // content green every other control draws with.
    let content = Theme.turbo.resolved(for: .contentWindow)
    #expect(content.secondaryAccent == .rgb(red: 0, green: 0, blue: 170))
    #expect(content.accent == .rgb(red: 0, green: 170, blue: 0))

    // A tinted toolbar item rests on the secondary accent.
    let bar = Toolbar()
    bar.theme = .turbo
    bar.themeContext = .contentWindow
    bar.addItem("Run") {}
    bar.frame = Rect(x: 0, y: 0, width: 20, height: 1)
    let buffer = SceneRenderer(root: bar).render(size: Size(width: 20, height: 1))
    #expect(buffer[Point(x: 1, y: 0)].style.foreground == content.secondaryAccent)

    // And the sheet layer can restyle it: `secondary-accent` is a known name.
    bar.styleSheet = StyleSheet("Toolbar { secondary-accent: brightYellow; }")
    let restyled = SceneRenderer(root: bar).render(size: Size(width: 20, height: 1))
    #expect(restyled[Point(x: 1, y: 0)].style.foreground == .named(.brightYellow))
}

@Test @MainActor func chartDataPropertiesRetintTheSeriesPalette() {
    let chart = LineChart(series: [
        .init(label: "a", values: [1, 2]),
        .init(label: "b", values: [2, 1]),
    ])
    chart.showsLegend = true
    chart.theme = .dark
    chart.styleSheet = StyleSheet("""
    LineChart { chart-data-1: brightMagenta; chart-axis: brightBlack; }
    """)
    chart.frame = Rect(x: 0, y: 0, width: 30, height: 8)

    let buffer = SceneRenderer(root: chart).render(size: Size(width: 30, height: 8))

    // Legend series 1 wears the sheet's color; series 2 keeps the derived
    // palette (warning accent) — one entry set does not drop the rest.
    // (Legend layout: entry 2's marker lands at x = label width + 4.)
    #expect(buffer[Point(x: 0, y: 0)].style.foreground == .named(.brightMagenta))
    let derived = Theme.dark.resolved()
    #expect(buffer[Point(x: 5, y: 0)].style.foreground == derived.warningAccent)
}
