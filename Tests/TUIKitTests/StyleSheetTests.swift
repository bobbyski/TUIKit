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
    #expect(sheet.rules[2].declarations.count == 1, "unknown properties and bad values are skipped")
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
