// The next-generation, context-aware theme model (see Docs/Themes.md).
//
// A `Theme` is a *slot × context* matrix: a complete `base` palette plus sparse
// per-context overlays. Resolving it for a context produces a flat,
// fully-populated `ResolvedTheme` whose CellStyle conveniences (`.selection`,
// `.header`, …) the controls draw with (`TUIView.effectiveTheme`). The built-in
// themes live in Theme.swift; controls draw via `effectiveTheme`.

// MARK: - Codable for the primitives

extension TerminalColor: Codable {
    // Encoded as a single string: "#RRGGBB", a named color's name, "standard",
    // or "palette:N".
    public init(from decoder: Decoder) throws {
        let string = try decoder.singleValueContainer().decode(String.self)

        if string == "standard" {
            self = .standard
        } else if string.hasPrefix("#"), string.count == 7,
                  let r = UInt8(string.dropFirst().prefix(2), radix: 16),
                  let g = UInt8(string.dropFirst(3).prefix(2), radix: 16),
                  let b = UInt8(string.suffix(2), radix: 16) {
            self = .rgb(red: r, green: g, blue: b)
        } else if string.hasPrefix("palette:"), let index = UInt8(string.dropFirst("palette:".count)) {
            self = .palette(index)
        } else if let named = NamedColor(rawValue: string) {
            self = .named(named)
        } else {
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "Unrecognized color \"\(string)\""
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(themeString)
    }

    /// The theme-file spelling of this color.
    var themeString: String {
        switch self {
        case .standard:
            return "standard"

        case .named(let named):
            return named.rawValue

        case .palette(let index):
            return "palette:\(index)"

        case .rgb(let red, let green, let blue):
            return "#" + Self.hex(red) + Self.hex(green) + Self.hex(blue)
        }
    }

    // Two uppercase hex digits, without Foundation.
    private static func hex(_ value: UInt8) -> String {
        let digits = Array("0123456789ABCDEF")
        return String([digits[Int(value >> 4)], digits[Int(value & 0xF)]])
    }
}

extension CellFlags: Codable {
    // Encoded as an array of names, e.g. ["bold", "underline"].
    private static let names: [(flag: CellFlags, name: String)] = [
        (.bold, "bold"), (.dim, "dim"), (.italic, "italic"),
        (.underline, "underline"), (.inverse, "inverse"), (.strikethrough, "strikethrough"),
    ]

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode([String].self)
        var flags: CellFlags = []

        for name in raw {
            if let match = Self.names.first(where: { $0.name == name }) {
                flags.insert(match.flag)
            }
        }

        self = flags
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(Self.names.filter { contains($0.flag) }.map(\.name))
    }
}

extension BorderStyle: Codable {
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)

        guard let value = BorderStyle(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "Unrecognized border style \"\(raw)\""
            )
        }

        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

// MARK: - Contexts

/// Where a view lives, which selects the palette it resolves through. `nil`
/// (on a view) means "follow the parent"; unresolved falls back to `base`.
public enum ThemeContext: String, Codable, Sendable, CaseIterable {
    case desktop
    case contentWindow
    case secondaryWindows
    case modalWindows
    case accessoryView
}

/// Whether dividers/separators visually connect (weld) into borders and each
/// other with tee/cross junctions, or read as plain, unattached lines.
public enum DividerConnection: String, Codable, Hashable, Sendable, CaseIterable {
    /// Tee/cross junctions where lines meet borders and each other (Borland).
    case welded

    /// Plain lines — no junctions, nothing welds into a border.
    case notWelded
}

// MARK: - Palette (one context's slots — all optional)

/// One context's slot values. Every field is optional: `nil` inherits through
/// the fallback chain (ending at `base`, which must be complete). Flat,
/// descriptive keys make it a clean JSON object; missing keys decode to `nil`
/// and `nil` fields are omitted on encode.
public struct ThemePalette: Codable, Hashable, Sendable {
    public var foreground: TerminalColor?
    public var background: TerminalColor?
    public var baseAttributes: CellFlags?

    public var accent: TerminalColor?
    public var warningAccent: TerminalColor?
    public var errorAccent: TerminalColor?

    public var acceleratorColor: TerminalColor?
    public var acceleratorAttributes: CellFlags?

    public var selectionForeground: TerminalColor?
    public var selectionBackground: TerminalColor?
    public var selectionAttributes: CellFlags?

    public var headerForeground: TerminalColor?
    public var headerBackground: TerminalColor?
    public var headerAttributes: CellFlags?

    public var borderForeground: TerminalColor?
    public var borderBackground: TerminalColor?
    public var borderStyle: BorderStyle?
    public var dividerStyle: BorderStyle?
    public var dividerConnection: DividerConnection?

    public var scrollbarThumb: TerminalColor?
    public var scrollbarTrack: TerminalColor?

    public var placeholderForeground: TerminalColor?
    public var placeholderBackground: TerminalColor?
    public var placeholderAttributes: CellFlags?

    public var fieldForeground: TerminalColor?
    public var fieldBackground: TerminalColor?
    public var fieldAttributes: CellFlags?

    public var defaultButtonForeground: TerminalColor?
    public var defaultButtonBackground: TerminalColor?

    public var destructiveButtonForeground: TerminalColor?
    public var destructiveButtonBackground: TerminalColor?

    /// An empty palette (everything inherits).
    public init() {}
}

// MARK: - Resolved theme (flat, complete — what controls draw with)

/// A fully-resolved palette for one context: every slot has a value. Controls
/// read the CellStyle conveniences (`.selection`, `.header`, …); CSS layers on
/// top by writing the flat stored properties.
public struct ResolvedTheme: Hashable, Sendable {
    public var foreground: TerminalColor
    public var background: TerminalColor
    public var baseAttributes: CellFlags

    public var accent: TerminalColor
    public var warningAccent: TerminalColor
    public var errorAccent: TerminalColor

    /// The mnemonic (accelerator) letter's color — red in Turbo. Overlaid on
    /// the surrounding cell's background, keeping menus/buttons intact.
    public var acceleratorColor: TerminalColor
    /// Attributes for the mnemonic letter (e.g. `.underline` on colorless themes).
    public var acceleratorAttributes: CellFlags

    public var selectionForeground: TerminalColor
    public var selectionBackground: TerminalColor
    public var selectionAttributes: CellFlags

    public var headerForeground: TerminalColor
    public var headerBackground: TerminalColor
    public var headerAttributes: CellFlags

    public var borderForeground: TerminalColor
    public var borderBackground: TerminalColor
    /// Box-drawing style for window/panel *frames*.
    public var borderStyle: BorderStyle
    /// Box-drawing style for *interior* lines (dividers, split bars, separators).
    /// Usually `.single` even when frames are `.double` (the Borland rule).
    public var dividerStyle: BorderStyle
    /// Whether dividers weld into borders/each other with junctions.
    public var dividerConnection: DividerConnection

    public var scrollbarThumb: TerminalColor
    public var scrollbarTrack: TerminalColor

    public var placeholderForeground: TerminalColor
    public var placeholderBackground: TerminalColor
    public var placeholderAttributes: CellFlags

    public var fieldForeground: TerminalColor
    public var fieldBackground: TerminalColor
    public var fieldAttributes: CellFlags

    public var defaultButtonForeground: TerminalColor
    public var defaultButtonBackground: TerminalColor

    public var destructiveButtonForeground: TerminalColor
    public var destructiveButtonBackground: TerminalColor

    // MARK: CellStyle conveniences (derived, read-only)

    /// Ordinary cells (the `.standard`-substitution base).
    public var base: CellStyle { CellStyle(foreground: foreground, background: background, flags: baseAttributes) }

    /// Selected rows / segments / menu highlights.
    public var selection: CellStyle {
        CellStyle(foreground: selectionForeground, background: selectionBackground, flags: selectionAttributes)
    }

    /// Menu bar, status bar, panel titles, table headers.
    public var header: CellStyle {
        CellStyle(foreground: headerForeground, background: headerBackground, flags: headerAttributes)
    }

    /// Boxes, dividers, scroll indicators.
    public var border: CellStyle { CellStyle(foreground: borderForeground, background: borderBackground) }

    /// Scroll indicators: foreground = thumb, background = track.
    public var scrollbar: CellStyle { CellStyle(foreground: scrollbarThumb, background: scrollbarTrack) }

    /// De-emphasized text.
    public var placeholder: CellStyle {
        CellStyle(foreground: placeholderForeground, background: placeholderBackground, flags: placeholderAttributes)
    }

    /// Editable field well.
    public var field: CellStyle {
        CellStyle(foreground: fieldForeground, background: fieldBackground, flags: fieldAttributes)
    }

    /// The default (Return/highlighted) button.
    public var defaultButton: CellStyle {
        CellStyle(foreground: defaultButtonForeground, background: defaultButtonBackground)
    }

    /// A destructive-action button.
    public var destructiveButton: CellStyle {
        CellStyle(foreground: destructiveButtonForeground, background: destructiveButtonBackground)
    }

    /// The style for a mnemonic (accelerator) letter sitting on `base`: the
    /// accelerator color and attributes, but `base`'s background — so the red
    /// letter reads against the same menu/button surface as its neighbors.
    public func accelerator(over base: CellStyle) -> CellStyle {
        var style = base
        style.foreground = acceleratorColor
        style.flags.formUnion(acceleratorAttributes)
        return style
    }
}

// MARK: - Theme definition (the matrix)

/// A named theme: a complete `base` palette plus optional per-context overlays.
/// Codable, so themes ship and load as JSON.
public struct Theme: Codable, Hashable, Sendable {
    public var name: String
    public var base: ThemePalette
    public var desktop: ThemePalette?
    public var contentWindow: ThemePalette?
    public var secondaryWindows: ThemePalette?
    public var modalWindows: ThemePalette?
    public var accessoryView: ThemePalette?

    public init(
        name: String,
        base: ThemePalette,
        desktop: ThemePalette? = nil,
        contentWindow: ThemePalette? = nil,
        secondaryWindows: ThemePalette? = nil,
        modalWindows: ThemePalette? = nil,
        accessoryView: ThemePalette? = nil
    ) {
        self.name = name
        self.base = base
        self.desktop = desktop
        self.contentWindow = contentWindow
        self.secondaryWindows = secondaryWindows
        self.modalWindows = modalWindows
        self.accessoryView = accessoryView
    }

    /// Resolves every slot for a context. `nil` context resolves against `base`.
    ///
    /// Fallback chains: `accessoryView` → `contentWindow` → `base`; every other
    /// context → `base`. First non-`nil` value in the chain wins; `base` is
    /// assumed complete (any hole falls back to `.standard` / `.single`).
    public func resolved(for context: ThemeContext? = nil) -> ResolvedTheme {
        let chain = paletteChain(for: context)

        func color(_ keyPath: KeyPath<ThemePalette, TerminalColor?>) -> TerminalColor {
            for palette in chain {
                if let value = palette[keyPath: keyPath] { return value }
            }
            return .standard
        }

        func flags(_ keyPath: KeyPath<ThemePalette, CellFlags?>) -> CellFlags {
            for palette in chain {
                if let value = palette[keyPath: keyPath] { return value }
            }
            return []
        }

        func borderStyle(_ keyPath: KeyPath<ThemePalette, BorderStyle?>, default fallback: BorderStyle) -> BorderStyle {
            for palette in chain {
                if let value = palette[keyPath: keyPath] { return value }
            }
            return fallback
        }

        var connection: DividerConnection = .welded
        for palette in chain where palette.dividerConnection != nil {
            connection = palette.dividerConnection!
            break
        }

        return ResolvedTheme(
            foreground: color(\.foreground),
            background: color(\.background),
            baseAttributes: flags(\.baseAttributes),
            accent: color(\.accent),
            warningAccent: color(\.warningAccent),
            errorAccent: color(\.errorAccent),
            acceleratorColor: color(\.acceleratorColor),
            acceleratorAttributes: flags(\.acceleratorAttributes),
            selectionForeground: color(\.selectionForeground),
            selectionBackground: color(\.selectionBackground),
            selectionAttributes: flags(\.selectionAttributes),
            headerForeground: color(\.headerForeground),
            headerBackground: color(\.headerBackground),
            headerAttributes: flags(\.headerAttributes),
            borderForeground: color(\.borderForeground),
            borderBackground: color(\.borderBackground),
            borderStyle: borderStyle(\.borderStyle, default: .single),
            dividerStyle: borderStyle(\.dividerStyle, default: .single),
            dividerConnection: connection,
            scrollbarThumb: color(\.scrollbarThumb),
            scrollbarTrack: color(\.scrollbarTrack),
            placeholderForeground: color(\.placeholderForeground),
            placeholderBackground: color(\.placeholderBackground),
            placeholderAttributes: flags(\.placeholderAttributes),
            fieldForeground: color(\.fieldForeground),
            fieldBackground: color(\.fieldBackground),
            fieldAttributes: flags(\.fieldAttributes),
            defaultButtonForeground: color(\.defaultButtonForeground),
            defaultButtonBackground: color(\.defaultButtonBackground),
            destructiveButtonForeground: color(\.destructiveButtonForeground),
            destructiveButtonBackground: color(\.destructiveButtonBackground)
        )
    }

    // The palette lookup order for a context, base last.
    private func paletteChain(for context: ThemeContext?) -> [ThemePalette] {
        guard let context else {
            return [base]
        }

        switch context {
        case .desktop:
            return [desktop, base].compactMap { $0 }

        case .contentWindow:
            return [contentWindow, base].compactMap { $0 }

        case .secondaryWindows:
            return [secondaryWindows, base].compactMap { $0 }

        case .modalWindows:
            return [modalWindows, base].compactMap { $0 }

        case .accessoryView:
            // Accessories echo the content window before falling back to base.
            return [accessoryView, contentWindow, base].compactMap { $0 }
        }
    }
}
