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
}

/// Semantic style palette for a view subtree.
///
/// A theme names the *roles* styles play rather than styling each control:
///
/// | Slot          | Used by                                              |
/// |---------------|------------------------------------------------------|
/// | `base`        | Every cell whose colors are `.standard` (see below)  |
/// | `accent`      | The theme's highlight color                          |
/// | `selection`   | Selected rows/segments (lists, tables, trees, menus) |
/// | `header`      | Table headers, panel titles, menu bar                |
/// | `border`      | Boxes, separators, dividers, scroll indicators       |
/// | `placeholder` | Placeholder and other de-emphasized text             |
///
/// **Cascade.** Assign a theme to any view (`view.theme = .ocean`) and its
/// whole subtree adopts it; the nearest ancestor's theme wins and the root
/// default is `.standard`, which reproduces the untinted terminal look.
/// Application of `base` is mechanical: the `Painter` substitutes the
/// theme's colors wherever a drawn cell's foreground/background is
/// `.standard`, so plain controls pick up the palette with no per-control
/// code — the theme rides the painter exactly like translation and
/// clipping do.
///
/// Switching is reset-safe: assigning `theme` repaints the subtree, and
/// every slot is a complete `CellStyle`, so no stale colors survive.
///
/// ```swift
/// window.theme = .homebrew          // green-on-black, everywhere
/// inspector.theme = .manPage        // except this pane
/// ```
public struct Theme: Hashable, Sendable {
    /// Colors for ordinary cells (substituted where a cell is `.standard`).
    public var base: CellStyle

    /// The theme's highlight color.
    public var accent: TerminalColor

    /// Selected rows and segments.
    public var selection: CellStyle

    /// Table headers, panel titles, the menu bar.
    public var header: CellStyle

    /// Boxes, separators, dividers, scroll indicators.
    public var border: CellStyle

    /// How panel and dropdown borders are drawn.
    public var borderStyle: BorderStyle

    /// Scroll indicators: `background` is the track, `foreground` the
    /// thumb. When either is `.standard` (a colorless theme), indicators
    /// fall back to solid video-attribute blocks.
    public var scrollbar: CellStyle

    /// Placeholder and de-emphasized text.
    public var placeholder: CellStyle

    /// Creates a theme slot by slot.
    ///
    /// - Parameters:
    ///   - base: Colors for ordinary cells.
    ///   - accent: Highlight color.
    ///   - selection: Selected rows and segments.
    ///   - header: Headers and titles.
    ///   - border: Boxes and separators.
    ///   - borderStyle: Box-drawing variant. Defaults to `.single`.
    ///   - scrollbar: Track (background) and thumb (foreground) colors.
    ///     Defaults to gray track, white thumb — visibly distinct from any
    ///     window background.
    ///   - placeholder: De-emphasized text.
    public init(
        base: CellStyle,
        accent: TerminalColor,
        selection: CellStyle,
        header: CellStyle,
        border: CellStyle,
        borderStyle: BorderStyle = .single,
        scrollbar: CellStyle = CellStyle(foreground: .named(.white), background: .named(.brightBlack)),
        placeholder: CellStyle
    ) {
        self.base = base
        self.accent = accent
        self.selection = selection
        self.header = header
        self.border = border
        self.borderStyle = borderStyle
        self.scrollbar = scrollbar
        self.placeholder = placeholder
    }

    /// Derives a full theme from a three-color palette.
    ///
    /// Selection shows the background color on the accent, headers are the
    /// accent in bold, borders use the plain palette, and placeholders dim
    /// it — override any slot afterwards.
    ///
    /// - Parameters:
    ///   - background: Background color.
    ///   - foreground: Text color.
    ///   - accent: Highlight color.
    public init(background: TerminalColor, foreground: TerminalColor, accent: TerminalColor) {
        let base = CellStyle(foreground: foreground, background: background)

        // Scrollbar shades: the track sits 30% of the way from the
        // background toward the text color, the thumb 70% — always
        // distinct from the window background.
        let track = TerminalColor.blend(background, toward: foreground, fraction: 0.3)
        let thumb = TerminalColor.blend(background, toward: foreground, fraction: 0.7)

        self.init(
            base: base,
            accent: accent,
            selection: CellStyle(foreground: background, background: accent),
            header: CellStyle(foreground: accent, background: background, flags: .bold),
            border: base,
            scrollbar: CellStyle(
                foreground: thumb ?? foreground,
                background: track ?? .named(.brightBlack)
            ),
            placeholder: CellStyle(foreground: foreground, background: background, flags: .dim)
        )
    }

    // MARK: - Built-in themes

    /// The terminal's own colors, selection by video inverse — TUIKit's
    /// look before themes existed, and the root default.
    public static let standard = Theme(
        base: CellStyle(),
        accent: .standard,
        selection: CellStyle(flags: .inverse),
        header: CellStyle(flags: .bold),
        border: CellStyle(),
        placeholder: CellStyle(flags: .dim)
    )

    /// Like `standard`, but promises to add no color anywhere: emphasis
    /// only. For monochrome terminals and purists.
    public static let mono: Theme = {
        var theme = Theme.standard
        theme.scrollbar = CellStyle()   // colorless: video-attribute blocks
        return theme
    }()

    /// Soft dark: near-black background, warm gray text, blue accent.
    public static let dark = Theme(
        background: .rgb(red: 30, green: 30, blue: 30),
        foreground: .rgb(red: 220, green: 220, blue: 220),
        accent: .rgb(red: 10, green: 132, blue: 255)
    )

    /// Soft light: paper-white background, near-black text, blue accent.
    public static let light = Theme(
        background: .rgb(red: 250, green: 250, blue: 250),
        foreground: .rgb(red: 25, green: 25, blue: 25),
        accent: .rgb(red: 0, green: 100, blue: 210)
    )

    /// Phosphor green on black.
    public static let homebrew = Theme(
        background: .rgb(red: 0, green: 0, blue: 0),
        foreground: .rgb(red: 40, green: 254, blue: 20),
        accent: .rgb(red: 40, green: 254, blue: 20)
    )

    /// Cream text on lawn green.
    public static let grass = Theme(
        background: .rgb(red: 19, green: 119, blue: 61),
        foreground: .rgb(red: 255, green: 240, blue: 165),
        accent: .rgb(red: 255, green: 176, blue: 3)
    )

    /// White on deep sea blue.
    public static let ocean = Theme(
        background: .rgb(red: 34, green: 79, blue: 188),
        foreground: .rgb(red: 255, green: 255, blue: 255),
        accent: .rgb(red: 126, green: 190, blue: 255)
    )

    /// Sand on baked red clay.
    public static let redSands = Theme(
        background: .rgb(red: 122, green: 37, blue: 30),
        foreground: .rgb(red: 215, green: 201, blue: 167),
        accent: .rgb(red: 223, green: 189, blue: 34)
    )

    /// Black text on manual-page yellow.
    public static let manPage = Theme(
        background: .rgb(red: 254, green: 244, blue: 156),
        foreground: .rgb(red: 0, green: 0, blue: 0),
        accent: .rgb(red: 178, green: 102, blue: 0)
    )

    /// Dark brown ink on aged paper.
    public static let novel = Theme(
        background: .rgb(red: 223, green: 219, blue: 195),
        foreground: .rgb(red: 59, green: 35, blue: 34),
        accent: .rgb(red: 141, green: 0, blue: 0)
    )

    /// Crisp white on true black.
    public static let pro = Theme(
        background: .rgb(red: 0, green: 0, blue: 0),
        foreground: .rgb(red: 242, green: 242, blue: 242),
        accent: .rgb(red: 52, green: 152, blue: 255)
    )

    /// Black on translucent silver.
    public static let silverAerogel = Theme(
        background: .rgb(red: 146, green: 146, blue: 146),
        foreground: .rgb(red: 0, green: 0, blue: 0),
        accent: .rgb(red: 240, green: 240, blue: 240)
    )

    /// Linear blend between two colors, when both have known RGB values
    /// (true color or the 16 named colors); `nil` otherwise.
    ///
    /// - Parameters:
    ///   - from: Start color (fraction 0).
    ///   - toward: End color (fraction 1).
    ///   - fraction: Mix amount, 0...1.
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
