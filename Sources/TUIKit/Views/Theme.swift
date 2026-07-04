/// How boxes and panel borders are drawn.
public enum BorderStyle: String, Hashable, Sendable, CaseIterable {
    /// No border characters at all.
    case none

    /// `┌─┐` single lines (the default).
    case single

    /// `╭─╮` single lines with rounded corners.
    case rounded

    /// `╔═╗` double lines.
    case double

    /// `┏━┓` heavy lines.
    case heavy

    // Box-drawing characters, or nil for .none.
    var characters: (
        topLeft: Character, topRight: Character,
        bottomLeft: Character, bottomRight: Character,
        horizontal: Character, vertical: Character
    )? {
        switch self {
        case .none:
            return nil

        case .single:
            return ("┌", "┐", "└", "┘", "─", "│")

        case .rounded:
            return ("╭", "╮", "╰", "╯", "─", "│")

        case .double:
            return ("╔", "╗", "╚", "╝", "═", "║")

        case .heavy:
            return ("┏", "┓", "┗", "┛", "━", "┃")
        }
    }

    // Junction glyphs for connected dividers: tees against each edge and
    // the four-way crossing. Rounded borders use the single-line tees.
    var junctions: (
        teeLeft: Character, teeRight: Character,
        teeTop: Character, teeBottom: Character,
        cross: Character
    )? {
        switch self {
        case .none:
            return nil

        case .single, .rounded:
            return ("├", "┤", "┬", "┴", "┼")

        case .double:
            return ("╠", "╣", "╦", "╩", "╬")

        case .heavy:
            return ("┣", "┫", "┳", "┻", "╋")
        }
    }

    /// Which side of a frame an interior line abuts.
    enum TeeSide { case left, right, top, bottom }

    /// Glyph for a frame border of *this* style where an interior line of
    /// `nub` style meets it from the inside (used when a `Panel` welds an
    /// interior divider into its frame). Same styles use the standard
    /// junctions; single↔double pairs use the mixed box-drawing tees (e.g. a
    /// single divider into a double frame → `╟`); anything else falls back to
    /// the frame's own junction.
    func tee(_ side: TeeSide, nub: BorderStyle) -> Character? {
        switch (self, nub) {
        case (.double, .single), (.double, .rounded):
            switch side {
            case .left: return "╟"
            case .right: return "╢"
            case .top: return "╤"
            case .bottom: return "╧"
            }

        case (.single, .double), (.rounded, .double):
            switch side {
            case .left: return "╞"
            case .right: return "╡"
            case .top: return "╥"
            case .bottom: return "╨"
            }

        default:
            guard let junctions else { return nil }
            switch side {
            case .left: return junctions.teeLeft
            case .right: return junctions.teeRight
            case .top: return junctions.teeTop
            case .bottom: return junctions.teeBottom
            }
        }
    }
}

// MARK: - Built-in themes
//
// The `Theme` type itself (the slot × context matrix) lives in ThemeModel.swift.
// These are the shipped themes. Most are *single-surface* — one `base` palette
// that every context inherits — built with `surface(...)`. Turbo is the
// multi-context example (gray chrome/dialogs, a blue content window).

extension Theme {
    /// A single-surface theme: one `base` palette every context inherits,
    /// derived from three colors (mirrors the classic 3-color palette).
    ///
    /// - Parameters:
    ///   - name: Display name.
    ///   - background: Window background.
    ///   - foreground: Text color.
    ///   - accent: Highlight color.
    public static func surface(
        _ name: String,
        background: TerminalColor,
        foreground: TerminalColor,
        accent: TerminalColor
    ) -> Theme {
        // Scrollbar shades: track 30% and thumb 70% of the way from the
        // background toward the text — always distinct from the window.
        let track = TerminalColor.blend(background, toward: foreground, fraction: 0.3) ?? .named(.brightBlack)
        let thumb = TerminalColor.blend(background, toward: foreground, fraction: 0.7) ?? foreground

        var base = ThemePalette()
        base.foreground = foreground
        base.background = background
        base.accent = accent
        base.warningAccent = .named(.brightYellow)
        base.errorAccent = .named(.brightRed)
        base.acceleratorColor = accent
        base.acceleratorAttributes = [.underline]
        base.selectionForeground = background
        base.selectionBackground = accent
        base.headerForeground = accent
        base.headerBackground = background
        base.headerAttributes = [.bold]
        base.borderForeground = foreground
        base.borderBackground = background
        base.borderStyle = .single
        base.scrollbarThumb = thumb
        base.scrollbarTrack = track
        base.placeholderForeground = foreground
        base.placeholderBackground = background
        base.placeholderAttributes = [.dim]
        base.fieldForeground = foreground
        base.fieldBackground = background
        base.fieldAttributes = [.underline]
        // Ordinary buttons: accent text on the window's own surface, so the
        // pill is invisible and reads as the minimal tinted look.
        base.buttonForeground = accent
        base.buttonBackground = background
        base.defaultButtonForeground = background
        base.defaultButtonBackground = accent
        base.destructiveButtonForeground = .named(.brightWhite)
        base.destructiveButtonBackground = .named(.red)
        return Theme(name: name, base: base)
    }

    /// The terminal's own colors, selection by video inverse — TUIKit's look
    /// before themes existed, and the root default. The accent is a real color
    /// (bright cyan) so recolor-based focus cues work here too.
    public static let standard: Theme = {
        var base = ThemePalette()
        base.foreground = .standard
        base.background = .standard
        base.accent = .named(.brightCyan)
        base.warningAccent = .named(.brightYellow)
        base.errorAccent = .named(.brightRed)
        base.acceleratorColor = .standard
        base.acceleratorAttributes = [.underline]
        base.selectionForeground = .standard
        base.selectionBackground = .standard
        base.selectionAttributes = [.inverse]
        base.headerForeground = .standard
        base.headerBackground = .standard
        base.headerAttributes = [.bold]
        base.borderForeground = .standard
        base.borderBackground = .standard
        base.borderStyle = .single
        base.scrollbarThumb = .named(.white)
        base.scrollbarTrack = .named(.brightBlack)
        base.placeholderForeground = .standard
        base.placeholderBackground = .standard
        base.placeholderAttributes = [.dim]
        base.fieldForeground = .standard
        base.fieldBackground = .standard
        base.fieldAttributes = [.underline]
        base.buttonForeground = .named(.brightCyan)   // accent text, no fill
        base.buttonBackground = .standard
        base.defaultButtonForeground = .named(.brightGreen)
        base.defaultButtonBackground = .standard
        base.destructiveButtonForeground = .named(.brightRed)
        base.destructiveButtonBackground = .standard
        return Theme(name: "Standard", base: base)
    }()

    /// Like `standard`, but promises no color: emphasis only. Accent and
    /// scrollbar colors drop to `.standard` so cues fall back to video attrs.
    public static let mono: Theme = {
        var theme = Theme.standard
        theme.name = "Mono"
        theme.base.accent = .standard
        theme.base.scrollbarThumb = .standard
        theme.base.scrollbarTrack = .standard
        theme.base.buttonForeground = .standard   // colorless: buttons rest on emphasis
        theme.base.buttonBackground = .standard
        return theme
    }()

    /// Soft dark: near-black background, warm gray text, blue accent.
    public static let dark = surface(
        "Dark",
        background: .rgb(red: 30, green: 30, blue: 30),
        foreground: .rgb(red: 220, green: 220, blue: 220),
        accent: .rgb(red: 10, green: 132, blue: 255)
    )

    /// Soft light: paper-white background, near-black text, blue accent.
    public static let light = surface(
        "Light",
        background: .rgb(red: 250, green: 250, blue: 250),
        foreground: .rgb(red: 25, green: 25, blue: 25),
        accent: .rgb(red: 0, green: 100, blue: 210)
    )

    /// Phosphor green on black.
    public static let homebrew = surface(
        "Homebrew",
        background: .rgb(red: 0, green: 0, blue: 0),
        foreground: .rgb(red: 40, green: 254, blue: 20),
        accent: .rgb(red: 40, green: 254, blue: 20)
    )

    /// Cream text on lawn green.
    public static let grass = surface(
        "Grass",
        background: .rgb(red: 19, green: 119, blue: 61),
        foreground: .rgb(red: 255, green: 240, blue: 165),
        accent: .rgb(red: 255, green: 176, blue: 3)
    )

    /// White on deep sea blue.
    public static let ocean = surface(
        "Ocean",
        background: .rgb(red: 34, green: 79, blue: 188),
        foreground: .rgb(red: 255, green: 255, blue: 255),
        accent: .rgb(red: 126, green: 190, blue: 255)
    )

    /// Sand on baked red clay.
    public static let redSands = surface(
        "Red Sands",
        background: .rgb(red: 122, green: 37, blue: 30),
        foreground: .rgb(red: 215, green: 201, blue: 167),
        accent: .rgb(red: 223, green: 189, blue: 34)
    )

    /// Black text on manual-page yellow.
    public static let manPage = surface(
        "Man Page",
        background: .rgb(red: 254, green: 244, blue: 156),
        foreground: .rgb(red: 0, green: 0, blue: 0),
        accent: .rgb(red: 178, green: 102, blue: 0)
    )

    /// Dark brown ink on aged paper.
    public static let novel = surface(
        "Novel",
        background: .rgb(red: 223, green: 219, blue: 195),
        foreground: .rgb(red: 59, green: 35, blue: 34),
        accent: .rgb(red: 141, green: 0, blue: 0)
    )

    /// Crisp white on true black.
    public static let pro = surface(
        "Pro",
        background: .rgb(red: 0, green: 0, blue: 0),
        foreground: .rgb(red: 242, green: 242, blue: 242),
        accent: .rgb(red: 52, green: 152, blue: 255)
    )

    /// Black on translucent silver.
    public static let silverAerogel = surface(
        "Silver Aerogel",
        background: .rgb(red: 146, green: 146, blue: 146),
        foreground: .rgb(red: 0, green: 0, blue: 0),
        accent: .rgb(red: 240, green: 240, blue: 240)
    )

    /// Turbo / Borland IDE (Turbo Pascal, Turbo C, …) — the multi-context
    /// example. `base` is the gray chrome/dialog surface; `contentWindow` is
    /// the blue code editor; `desktop` paints a lighter-blue backdrop. (See
    /// Docs/Themes.md.)
    public static let turbo: Theme = {
        var base = ThemePalette()
        base.foreground = .rgb(red: 0, green: 0, blue: 0)            // black
        base.background = .rgb(red: 170, green: 170, blue: 170)      // light gray
        base.accent = .rgb(red: 0, green: 170, blue: 0)             // green
        base.warningAccent = .rgb(red: 255, green: 170, blue: 0)    // amber
        base.errorAccent = .rgb(red: 255, green: 0, blue: 0)       // red
        base.acceleratorColor = .rgb(red: 255, green: 85, blue: 85)   // bright red mnemonic
        base.acceleratorAttributes = []   // the color carries it — no underline (Borland)
        base.selectionForeground = .rgb(red: 0, green: 0, blue: 0)
        base.selectionBackground = .rgb(red: 0, green: 170, blue: 170)   // cyan
        base.headerForeground = .rgb(red: 0, green: 0, blue: 0)
        base.headerBackground = .rgb(red: 170, green: 170, blue: 170)
        base.headerAttributes = [.bold]
        base.borderForeground = .rgb(red: 255, green: 255, blue: 255)    // white
        base.borderBackground = .rgb(red: 170, green: 170, blue: 170)
        base.borderStyle = .single   // menus, dropdowns, interior lines are single
        base.scrollbarThumb = .rgb(red: 85, green: 85, blue: 85)         // dark gray
        base.scrollbarTrack = .rgb(red: 127, green: 127, blue: 127)     // gray
        base.placeholderForeground = .rgb(red: 85, green: 85, blue: 85)
        base.placeholderBackground = .rgb(red: 170, green: 170, blue: 170)
        base.placeholderAttributes = [.dim]
        base.fieldForeground = .rgb(red: 255, green: 255, blue: 85)      // yellow
        base.fieldBackground = .rgb(red: 0, green: 0, blue: 170)         // blue well
        base.buttonForeground = .rgb(red: 255, green: 255, blue: 255)    // white
        base.buttonBackground = .rgb(red: 85, green: 85, blue: 85)       // dark gray pill
        base.buttonShadowColor = .rgb(red: 0, green: 0, blue: 0)         // drop shadow + press animation
        base.defaultButtonForeground = .rgb(red: 255, green: 255, blue: 255)
        base.defaultButtonBackground = .rgb(red: 0, green: 170, blue: 0)  // green
        base.destructiveButtonForeground = .rgb(red: 255, green: 255, blue: 255)
        base.destructiveButtonBackground = .rgb(red: 170, green: 0, blue: 0)   // red

        var content = ThemePalette()
        content.foreground = .rgb(red: 255, green: 255, blue: 85)    // yellow
        content.background = .rgb(red: 0, green: 0, blue: 170)       // blue
        content.headerForeground = .rgb(red: 255, green: 255, blue: 255)
        content.headerBackground = .rgb(red: 0, green: 0, blue: 170)
        content.borderForeground = .rgb(red: 255, green: 255, blue: 255)
        content.borderBackground = .rgb(red: 0, green: 0, blue: 170)
        content.borderStyle = .double   // floating window frame → double border
        content.scrollbarThumb = .rgb(red: 85, green: 255, blue: 255)    // light cyan
        content.scrollbarTrack = .rgb(red: 0, green: 0, blue: 110)       // navy
        content.placeholderForeground = .rgb(red: 0, green: 170, blue: 170)
        content.placeholderBackground = .rgb(red: 0, green: 0, blue: 170)

        var desktop = ThemePalette()
        desktop.background = .rgb(red: 85, green: 85, blue: 255)     // light blue backdrop
        desktop.foreground = .rgb(red: 255, green: 255, blue: 255)   // white

        // Dialogs are gray (base) but, being floating windows, wear a double
        // frame — the only override they need over base.
        var dialog = ThemePalette()
        dialog.borderStyle = .double

        return Theme(
            name: "Turbo",
            base: base,
            desktop: desktop,
            contentWindow: content,
            secondaryWindows: dialog,
            modalWindows: dialog
        )
    }()

    /// Turbo with flat buttons: the same Borland palette, but no button drop
    /// shadow (and therefore no press-down animation) — buttons stay one-row
    /// pills, like every other theme.
    public static let modernTurbo: Theme = {
        var theme = Theme.turbo
        theme.name = "Modern Turbo"
        theme.base.buttonShadowColor = nil   // unset → resolves .standard → no shadow
        return theme
    }()

    /// Linear blend between two colors, when both have known RGB values
    /// (true color or the 16 named colors); `nil` otherwise.
    public static func blendColors(
        _ from: TerminalColor,
        toward: TerminalColor,
        fraction: Double
    ) -> TerminalColor? {
        TerminalColor.blend(from, toward: toward, fraction: fraction)
    }

    /// Every built-in theme with a display name (demo pickers, settings).
    public static let builtIn: [(name: String, theme: Theme)] = [
        ("Standard", .standard),
        ("Dark", .dark),
        ("Light", .light),
        ("Homebrew", .homebrew),
        ("Grass", .grass),
        ("Ocean", .ocean),
        ("Red Sands", .redSands),
        ("Man Page", .manPage),
        ("Novel", .novel),
        ("Pro", .pro),
        ("Silver Aerogel", .silverAerogel),
        ("Turbo", .turbo),
        ("Modern Turbo", .modernTurbo),
    ]
}

extension TerminalColor {
    // Linear blend when both colors have known RGB values.
    static func blend(_ from: TerminalColor, toward: TerminalColor, fraction: Double) -> TerminalColor? {
        guard let a = from.rgbComponents, let b = toward.rgbComponents else {
            return nil
        }

        func mix(_ x: UInt8, _ y: UInt8) -> UInt8 {
            UInt8(clamping: Int(Double(x) + (Double(y) - Double(x)) * fraction))
        }

        return .rgb(red: mix(a.red, b.red), green: mix(a.green, b.green), blue: mix(a.blue, b.blue))
    }

    // Known RGB values; named colors use the common xterm defaults.
    var rgbComponents: (red: UInt8, green: UInt8, blue: UInt8)? {
        switch self {
        case .rgb(let red, let green, let blue):
            return (red, green, blue)

        case .named(let named):
            return named.rgbApproximation

        case .palette, .standard:
            return nil
        }
    }
}

extension TerminalColor.NamedColor {
    // xterm's default palette for the 16 named colors.
    var rgbApproximation: (red: UInt8, green: UInt8, blue: UInt8) {
        switch self {
        case .black: return (0, 0, 0)
        case .red: return (205, 0, 0)
        case .green: return (0, 205, 0)
        case .yellow: return (205, 205, 0)
        case .blue: return (0, 0, 238)
        case .magenta: return (205, 0, 205)
        case .cyan: return (0, 205, 205)
        case .white: return (229, 229, 229)
        case .brightBlack: return (127, 127, 127)
        case .brightRed: return (255, 0, 0)
        case .brightGreen: return (0, 255, 0)
        case .brightYellow: return (255, 255, 0)
        case .brightBlue: return (92, 92, 255)
        case .brightMagenta: return (255, 0, 255)
        case .brightCyan: return (0, 255, 255)
        case .brightWhite: return (255, 255, 255)
        }
    }
}
