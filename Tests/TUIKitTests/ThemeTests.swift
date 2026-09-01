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

@Test @MainActor func modernTurboIsTurboWithoutButtonShadows() {
    #expect(Theme.builtIn.contains { $0.name == "Modern Turbo" })

    // Same palette, one difference: no button shadow → flat one-row buttons.
    #expect(Theme.turbo.resolved().buttonShadow != nil)
    #expect(Theme.modernTurbo.resolved().buttonShadow == nil)

    var flattened = Theme.turbo
    flattened.name = "Modern Turbo"
    flattened.base.buttonShadowColor = nil
    #expect(Theme.modernTurbo == flattened, "everything but the shadow matches Turbo")

    // And a button under it keeps the flat intrinsic.
    let button = Button("OK")
    let window = Window(frame: Rect(x: 0, y: 0, width: 8, height: 3))
    window.theme = .modernTurbo
    window.addSubview(button)
    #expect(button.intrinsicContentSize == Size(width: 4, height: 1))
}

@Test @MainActor func themeSwitchRelayoutsThemeDependentIntrinsics() {
    // Switching the app theme must re-run layout, not just repaint: intrinsic
    // sizes are theme-dependent (Turbo buttons grow a column + row for their
    // drop shadow), and stale frames truncate labels ("Res…") and lose the
    // red mnemonics — the regression from the 2026-07-04 screenshot.
    let desktop = Desktop()
    desktop.frame = Rect(x: 0, y: 0, width: 60, height: 20)
    desktop.theme = .dark

    let window = FloatingWindow(title: "Form", frame: Rect(x: 0, y: 0, width: 40, height: 10))
    window.themeContext = .secondaryWindows
    let reset = Button("&Reset")
    let save = Button("&Save")
    save.role = .default
    let row = HStack(spacing: 2) { reset; save }
    row.anchors = AnchorSet(leading: 2, trailing: 2, top: 2, height: 2)
    window.content.addSubview(row)
    desktop.addSubview(window)

    let renderer = SceneRenderer(root: desktop)
    _ = renderer.render(size: Size(width: 60, height: 20))
    #expect(reset.frame.size == Size(width: 7, height: 2), "dark: flat intrinsic width")

    // The demo's Theme menu: desktop theme changes, window overrides clear.
    desktop.theme = .turbo
    window.theme = nil
    let buffer = renderer.render(size: Size(width: 60, height: 20))

    // Frames grew for the shadow — so the labels render whole, not "Res…".
    #expect(reset.frame.size == Size(width: 8, height: 2), "turbo: +1 column, shadow row")
    #expect(save.frame.size == Size(width: 7, height: 2))

    let faceRow = (0..<60).map { String(buffer[Point(x: $0, y: 3)].character) }.joined()
    #expect(faceRow.contains("Reset"), "no truncation after the switch")
    #expect(faceRow.contains("Save"))

    // The red mnemonics survived the switch too.
    let rColumn = faceRow.distance(from: faceRow.startIndex, to: faceRow.firstIndex(of: "R")!)
    #expect(buffer[Point(x: rColumn, y: 3)].style.foreground == .rgb(red: 255, green: 85, blue: 85))
}

// MARK: - Translucent surfaces


@Test func turboAmbianceIsTurboWithAmbiancesManners() {
    let ambiance = Theme.turboAmbiance
    let turbo = Theme.turbo

    // The palette is Turbo's, unchanged — a terminal without VTG renders the
    // two identically apart from the border style.
    #expect(ambiance.base.background == turbo.base.background)
    #expect(ambiance.contentWindow?.background == turbo.contentWindow?.background)
    #expect(ambiance.base.acceleratorColor == turbo.base.acceleratorColor)

    #expect(ambiance.base.selectionBackground == turbo.base.selectionBackground)
    #expect(ambiance.base.scrollbarThumb == turbo.base.scrollbarThumb)
    #expect(ambiance.base.scrollbarTrack == turbo.base.scrollbarTrack)

    // Menus and the menu bar are Turbo's, letter for letter: the theme
    // changes how things are DRAWN, not what colour they are.
    #expect(ambiance.resolved(for: .menus).base.background == turbo.resolved(for: .menus).base.background)
    #expect(ambiance.resolved(for: .menus).base.foreground == turbo.resolved(for: .menus).base.foreground)
    #expect(ambiance.resolved(for: .menus).selection.background == turbo.resolved(for: .menus).selection.background)

    // Two things are drawn rather than typed — the title bar and the
    // buttons — and nothing else is. A desktop gradient or a shadow would
    // make it a different theme rather than a better-drawn one.
    let vector = ambiance.base.vector
    #expect(vector?.titleBar != nil)
    #expect(vector?.button != nil)
    #expect(vector?.desktop == nil, "no desktop gradient")
    #expect(vector?.windowShadow == nil, "no shadow")
    #expect(vector?.surface == nil, "no translucency")

    // The title bar is one colour rather than a gradient, and the button is
    // Turbo's own pill with a curve on it.
    #expect(vector?.titleBar?.topColor == vector?.titleBar?.bottomColor)
    #expect(vector?.button?.topColor == vector?.button?.bottomColor)
    #expect((vector?.button?.cornerRadius ?? 0) > 0)

    #expect(Theme.ambiance.base.vector?.surface != nil, "Ambiance keeps the translucency")

    // Turbo itself is untouched: no vector chrome, no transparency.
    #expect(turbo.base.vector?.surface == nil)

    #expect(Theme.builtIn.contains { $0.name == "Turbo Ambiance" })
}

@Test @MainActor func aTranslucentThemeDrawsSurfacesWithTheVectorLayer() {
    // A window body under Turbo Ambiance: the fill is a vector rect and the
    // cells over it go back to the terminal's default, which is what lets
    // the desktop show through them.
    let panel = Panel("Doc")
    panel.theme = .ambiance
    panel.frame = Rect(x: 0, y: 0, width: 20, height: 6)

    let renderer = SceneRenderer(root: panel)
    renderer.chromeEnabled = true
    let buffer = renderer.render(size: Size(width: 20, height: 6))

    let body = renderer.chromeCommands.first { $0.id.hasSuffix(ChromeKeys.windowSurface) }
    #expect(body != nil, "the window body is drawn by the vector layer")
    #expect(buffer[Point(x: 10, y: 3)].style.background == TerminalColor.standard, "…and its cells are transparent")

    // The same panel under Turbo paints solid cells and asks the vector
    // layer for nothing.
    let solid = Panel("Doc")
    solid.theme = .turbo
    solid.frame = Rect(x: 0, y: 0, width: 20, height: 6)

    let plain = SceneRenderer(root: solid)
    plain.chromeEnabled = true
    let solidBuffer = plain.render(size: Size(width: 20, height: 6))

    #expect(!plain.chromeCommands.contains { $0.id.hasSuffix(ChromeKeys.windowSurface) })
    #expect(solidBuffer[Point(x: 10, y: 3)].style.background != TerminalColor.standard)
}

@Test @MainActor func aThumbIsPushedOffItsTrackUntilItCanBeSeen() {
    // The bug this fixes: a theme picking two neighbouring shades of one
    // gray for thumb and track. The ARROWS stayed legible — a glyph has a
    // shape to find — while the thumb read as an empty bar.
    let track = TerminalColor.rgb(red: 229, green: 227, blue: 223)
    let whisper = TerminalColor.rgb(red: 181, green: 179, blue: 172)
    let corrected = ScrollView.contrasting(whisper, against: track)

    #expect(corrected != whisper)

    guard case .rgb(let red, let green, let blue) = corrected else {
        Issue.record("an rgb thumb stays rgb")
        return
    }

    // Darker, because the track is light — and still the theme's own hue
    // rather than a stock gray.
    #expect(red < 181 && green < 179 && blue < 172)
    #expect(red > green - 20 && blue < red, "the warm gray is still warm")

    // A dark track pushes the other way.
    let onDark = ScrollView.contrasting(
        .rgb(red: 60, green: 60, blue: 60),
        against: .rgb(red: 20, green: 20, blue: 30)
    )

    guard case .rgb(let lightened, _, _) = onDark else {
        Issue.record("an rgb thumb stays rgb")
        return
    }

    #expect(lightened > 60)

    // A pairing that already reads is left exactly as the theme wrote it.
    let cyan = TerminalColor.rgb(red: 85, green: 255, blue: 255)
    #expect(ScrollView.contrasting(cyan, against: .rgb(red: 0, green: 0, blue: 110)) == cyan)

    // Named colours belong to the terminal, so they are not second-guessed.
    #expect(ScrollView.contrasting(.named(.blue), against: .named(.blue)) == .named(.blue))
}

@Test @MainActor func everyBuiltInThemesThumbIsVisibleWhereItIsDRAWN() {
    // The palettes keep their own two shades — a theme's colours are the
    // theme's business. What is guaranteed is what reaches the screen: by
    // the time a bar is painted, its thumb clears the floor.
    for (name, theme) in Theme.builtIn {
        for context in [ThemeContext.contentWindow, .menus, .secondaryWindows, nil] {
            let resolved = theme.resolved(for: context)
            let (track, thumb) = ScrollView.indicatorStyles(for: resolved, focused: false)

            guard case .rgb = thumb.background, case .rgb = track.background else {
                continue   // named or default colours are the terminal's call
            }

            let corrected = ScrollView.contrasting(thumb.background, against: track.background)
            #expect(
                corrected == thumb.background,
                "\(name) [\(context.map { "\($0)" } ?? "base")] draws a thumb that is still too close to its track"
            )
        }
    }
}


@Test @MainActor func theNamespacedStyleNamesReachTheSlotsTheyName() {
    // `background`, `color` and `selection` are the most borrowed words in
    // styling. These four spellings say whose they are, so a sheet written
    // for something else cannot repaint a scrollbar by accident.
    let list = ListView(items: ["one"])
    list.styleSheet = StyleSheet("""
        ListView {
            tuikit.secondaryControlMarker: #55FFFF;
            tuikit.secondaryControlBackground: #000066;
            tuikit.selectedItemColor: #0000AA;
            tuikit.selectedItemBackgroundColor: #FFFF55;
        }
        """)

    let theme = list.effectiveTheme
    #expect(theme.scrollbar.foreground == .rgb(red: 85, green: 255, blue: 255))
    #expect(theme.scrollbar.background == .rgb(red: 0, green: 0, blue: 102))
    #expect(theme.selection.foreground == .rgb(red: 0, green: 0, blue: 170))
    #expect(theme.selection.background == .rgb(red: 255, green: 255, blue: 85))

    // The generic spellings still work: nothing written already stops
    // reading.
    let older = ListView(items: ["one"])
    older.styleSheet = StyleSheet("ListView { scrollbar-color: #112233; }")
    #expect(older.effectiveTheme.scrollbar.foreground == .rgb(red: 17, green: 34, blue: 51))
}


// The sixteen inks a Turbo window is allowed to use.
private let egaPalette: Set<[Int]> = [
    [0, 0, 0], [0, 0, 170], [0, 170, 0], [0, 170, 170],
    [170, 0, 0], [170, 0, 170], [170, 85, 0], [170, 170, 170],
    [85, 85, 85], [85, 85, 255], [85, 255, 85], [85, 255, 255],
    [255, 85, 85], [255, 85, 255], [255, 255, 85], [255, 255, 255],
]

@Test func turboAmbiancesVectorChromeUsesOnlyTurbosInks() {
    // The theme is Turbo's colours drawn Ambiance's way. A colour invented
    // for the chrome would be a colour Turbo does not have, which is the one
    // thing this theme may not do — so the gradients, the window buttons and
    // the shadow all come out of the same sixteen inks.
    let vector = try! #require(Theme.turboAmbiance.base.vector)

    func check(_ color: ChromeColor?, _ what: String) {
        guard let color else { return }
        #expect(egaPalette.contains([Int(color.red), Int(color.green), Int(color.blue)]), "\(what) is not an EGA ink")
    }

    func check(_ color: TerminalColor?, _ what: String) {
        guard case .rgb(let red, let green, let blue)? = color else { return }
        #expect(egaPalette.contains([Int(red), Int(green), Int(blue)]), "\(what) is not an EGA ink")
    }

    let bar = try! #require(vector.titleBar)
    check(bar.topColor, "titlebar top")
    check(bar.bottomColor, "titlebar bottom")
    check(bar.strokeColor, "titlebar stroke")
    check(bar.textColor, "titlebar text")
    check(bar.closeButtonColor, "close button")
    check(bar.closeSymbolColor, "close symbol")
    check(bar.auxiliaryButtonColor, "maximize button")
    check(bar.auxiliarySymbolColor, "maximize symbol")

    let button = try! #require(vector.button)
    check(button.topColor, "button top")
    check(button.bottomColor, "button bottom")
    check(button.strokeColor, "button stroke")
    check(button.textColor, "button text")
    check(button.focusStrokeColor, "focus stroke")
    check(button.pressedTopColor, "pressed top")
    check(button.pressedBottomColor, "pressed bottom")

    #expect(vector.desktop == nil)
    #expect(vector.windowShadow == nil)
}

@Test @MainActor func turboAmbiancePaintsTheSameCellsAsTurbo() {
    // Cell for cell, on a VTG terminal: the menu bar, the toolbar, the list,
    // the selection, the scrollbar. Whatever Ambiance contributes, it is not
    // a different colour anywhere.
    func scene(_ theme: Theme) -> CellBuffer {
        let panel = Panel("Doc")
        panel.theme = theme
        panel.frame = Rect(x: 0, y: 0, width: 60, height: 14)

        let bar = MenuBar()
        bar.addMenu(Menu("&File"))
        bar.frame = Rect(x: 0, y: 0, width: 60, height: 1)

        let toolbar = Toolbar()
        toolbar.addItem("Open", glyph: "▤") {}
        toolbar.frame = Rect(x: 1, y: 1, width: 58, height: 1)

        let list = ListView(items: (1...30).map { "Item \($0)" })
        list.frame = Rect(x: 1, y: 2, width: 30, height: 10)

        panel.addSubview(bar)
        panel.addSubview(toolbar)
        panel.addSubview(list)
        panel.layoutIfNeeded()

        let renderer = SceneRenderer(root: panel)
        renderer.chromeEnabled = true
        return renderer.render(size: Size(width: 60, height: 14))
    }

    let turbo = scene(.turbo)
    let ambiance = scene(.turboAmbiance)
    var differences = 0

    for y in 0..<14 {
        for x in 0..<60 {
            let expected = turbo[Point(x: x, y: y)].style
            let actual = ambiance[Point(x: x, y: y)].style

            if expected.foreground != actual.foreground || expected.background != actual.background {
                differences += 1
            }
        }
    }

    #expect(differences == 0, "\(differences) cells differ from Turbo")
}
