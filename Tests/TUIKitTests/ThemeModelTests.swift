import Testing
import Foundation
@testable import TUIKit

// The next-gen context-matrix theme model (Docs/Themes.md). These tests use
// distinct "rainbow" sentinels so nil→base fallback can never mask a
// mis-resolution.

private func rgb(_ v: UInt8) -> TerminalColor { .rgb(red: v, green: v, blue: v) }

// MARK: - Codable / JSON

@Test func themeDefinitionRoundTripsThroughJSON() throws {
    var base = ThemePalette()
    base.foreground = .rgb(red: 255, green: 255, blue: 85)
    base.background = .rgb(red: 0, green: 0, blue: 170)
    base.accent = .named(.brightCyan)
    base.selectionForeground = .standard
    base.selectionAttributes = [.inverse]
    base.headerAttributes = [.bold]
    base.borderStyle = .double
    base.scrollbarTrack = .palette(240)

    var content = ThemePalette()
    content.background = .rgb(red: 0, green: 0, blue: 170)   // sparse overlay

    let theme = Theme(name: "Turbo", base: base, contentWindow: content)

    let data = try JSONEncoder().encode(theme)
    let back = try JSONDecoder().decode(Theme.self, from: data)

    #expect(back == theme, "encode → decode is lossless across rgb/named/standard/palette + flags + borderStyle")
}

@Test func themeLoadsFromJSONText() throws {
    // As if read from a .json theme file.
    let json = """
    {
      "name": "Turbo",
      "base": { "foreground": "#FFFF55", "background": "#0000AA",
                "borderStyle": "double", "headerAttributes": ["bold"] },
      "contentWindow": { "background": "#0000AA" }
    }
    """

    let theme = try JSONDecoder().decode(Theme.self, from: Data(json.utf8))

    #expect(theme.name == "Turbo")
    #expect(theme.base.foreground == .rgb(red: 255, green: 255, blue: 85))
    #expect(theme.base.background == .rgb(red: 0, green: 0, blue: 170))
    #expect(theme.base.borderStyle == .double)
    #expect(theme.base.headerAttributes == [.bold])

    // Sparse: keys not present decode to nil.
    #expect(theme.base.accent == nil)
    #expect(theme.contentWindow?.background == .rgb(red: 0, green: 0, blue: 170))
    #expect(theme.contentWindow?.foreground == nil)
    #expect(theme.desktop == nil)
}

@Test func encodingOmitsNilSlots() throws {
    var base = ThemePalette()
    base.foreground = .named(.white)   // just one slot set
    let theme = Theme(name: "Sparse", base: base)

    let text = String(decoding: try JSONEncoder().encode(theme), as: UTF8.self)
    #expect(text.contains("\"foreground\""))
    #expect(!text.contains("\"accent\""), "nil slots are omitted, not encoded as null")
    #expect(!text.contains("\"desktop\""), "nil contexts are omitted")
}

// MARK: - Resolution

@Test func nilContextResolvesEntirelyAgainstBase() {
    var base = ThemePalette()
    base.foreground = rgb(1)
    base.background = rgb(2)
    base.accent = rgb(3)

    var desktop = ThemePalette()
    desktop.background = rgb(9)   // exists, but must be ignored for nil context

    let resolved = Theme(name: "R", base: base, desktop: desktop).resolved(for: nil)

    #expect(resolved.foreground == rgb(1))
    #expect(resolved.background == rgb(2))
    #expect(resolved.accent == rgb(3))
}

@Test func contextOverridesWinButUnsetSlotsInheritBase() {
    var base = ThemePalette()
    base.foreground = rgb(1)
    base.background = rgb(2)
    base.accent = rgb(3)

    var desktop = ThemePalette()
    desktop.background = rgb(9)   // desktop overrides only the background

    let d = Theme(name: "R", base: base, desktop: desktop).resolved(for: .desktop)

    #expect(d.background == rgb(9), "context override wins")
    #expect(d.foreground == rgb(1), "unset slot inherits base")
    #expect(d.accent == rgb(3), "unset slot inherits base")
}

@Test func accessoryViewFallsBackThroughContentWindowThenBase() {
    var base = ThemePalette()
    base.foreground = rgb(1)
    base.background = rgb(1)
    base.accent = rgb(1)

    var content = ThemePalette()
    content.foreground = rgb(2)     // only foreground

    var accessory = ThemePalette()
    accessory.background = rgb(3)    // only background

    let theme = Theme(name: "R", base: base, contentWindow: content, accessoryView: accessory)
    let a = theme.resolved(for: .accessoryView)

    #expect(a.background == rgb(3), "accessory's own value wins")
    #expect(a.foreground == rgb(2), "falls back to contentWindow — NOT base")
    #expect(a.accent == rgb(1), "set in neither → base")

    // contentWindow itself doesn't see the accessory overlay.
    let c = theme.resolved(for: .contentWindow)
    #expect(c.foreground == rgb(2))
    #expect(c.background == rgb(1), "contentWindow inherits base, not the accessory")
}

@Test func resolvedFlagsAndBorderStyleAndConveniences() {
    var base = ThemePalette()
    base.selectionForeground = .named(.black)
    base.selectionBackground = .named(.cyan)
    base.selectionAttributes = [.bold]
    base.borderForeground = .named(.white)
    base.borderStyle = .double

    let r = Theme(name: "R", base: base).resolved()

    #expect(r.borderStyle == .double)
    #expect(r.selectionAttributes == [.bold])
    #expect(r.selection == CellStyle(foreground: .named(.black), background: .named(.cyan), flags: [.bold]),
            "the .selection convenience is built from the flat slots")
    #expect(r.border == CellStyle(foreground: .named(.white), background: .standard),
            "an unset background resolves to .standard")
}
