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
    /// Decodes from the theme-file spelling (see the type's Codable notes).
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

    /// Encodes as the theme-file spelling.
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

    /// Decodes from an array of flag names.
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

    /// Encodes as an array of flag names.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(Self.names.filter { contains($0.flag) }.map(\.name))
    }
}

extension BorderStyle: Codable {
    /// Decodes from the style's raw-value name.
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

    /// Encodes as the style's raw-value name.
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

    /// Menu dropdowns, pop-up lists, context menus. Floating chrome pins
    /// ITSELF here (`MenuDropdown`, `PopUpList` set it in their inits), so
    /// a menu popped over a blue content window still wears the menu look —
    /// opaque chrome, single border — rather than dissolving into whatever
    /// surface it happens to cover. Resolves `menus` → `base`.
    case menus
}

/// Whether dividers/separators visually connect (weld) into borders and each
/// other with tee/cross junctions, or read as plain, unattached lines.
public enum DividerConnection: String, Codable, Hashable, Sendable, CaseIterable {
    /// Tee/cross junctions where lines meet borders and each other (Borland).
    case welded

    /// Plain lines — no junctions, nothing welds into a border.
    case notWelded
}

// MARK: - Vector chrome styling (Phase 10)

/// How a theme dresses the vector chrome layer, when a VTG terminal is
/// present (see Docs/VTGChrome.md).
///
/// Entirely optional at every level: a theme without a `vector` block (or a
/// block without a section) simply keeps cell rendering for that piece, and
/// plain terminals never consult this at all. Scalar sizes are fractions of
/// the cell height, like everything in `ChromeCommand`.
public struct VectorChrome: Codable, Hashable, Sendable {
    /// Where a chrome titlebar puts the window buttons.
    public enum TitleButtonPlacement: String, Codable, Hashable, Sendable {
        /// Close (then maximize) at the left edge — the Ubuntu arrangement.
        case leading

        /// Close at the right edge, maximize beside it.
        case trailing
    }

    /// The window titlebar: a gradient bar with rounded top corners and
    /// circular window buttons, replacing the cell-drawn top border.
    public struct TitleBar: Codable, Hashable, Sendable {
        /// Gradient color at the bar's top edge.
        public var topColor: ChromeColor

        /// Gradient color at the bar's bottom edge.
        public var bottomColor: ChromeColor

        /// Top-corner radius in cell heights (default 0.35).
        public var cornerRadius: Double?

        /// Optional thin outline over the bar.
        public var strokeColor: ChromeColor?

        /// Title text color (cells; default: the header slot's foreground).
        public var textColor: TerminalColor?

        /// Window-button side (default trailing, matching cell chrome).
        public var buttonPlacement: TitleButtonPlacement?

        /// Fill of the circular close button.
        public var closeButtonColor: ChromeColor

        /// Color of the `×` glyph over the close circle.
        public var closeSymbolColor: TerminalColor?

        /// Fill of the circular maximize/restore button (default: a dimmer
        /// take on the close fill).
        public var auxiliaryButtonColor: ChromeColor?

        /// Color of the glyph over the maximize circle.
        public var auxiliarySymbolColor: TerminalColor?

        /// Creates a titlebar style.
        public init(
            topColor: ChromeColor,
            bottomColor: ChromeColor,
            cornerRadius: Double? = nil,
            strokeColor: ChromeColor? = nil,
            textColor: TerminalColor? = nil,
            buttonPlacement: TitleButtonPlacement? = nil,
            closeButtonColor: ChromeColor,
            closeSymbolColor: TerminalColor? = nil,
            auxiliaryButtonColor: ChromeColor? = nil,
            auxiliarySymbolColor: TerminalColor? = nil
        ) {
            self.topColor = topColor
            self.bottomColor = bottomColor
            self.cornerRadius = cornerRadius
            self.strokeColor = strokeColor
            self.textColor = textColor
            self.buttonPlacement = buttonPlacement
            self.closeButtonColor = closeButtonColor
            self.closeSymbolColor = closeSymbolColor
            self.auxiliaryButtonColor = auxiliaryButtonColor
            self.auxiliarySymbolColor = auxiliarySymbolColor
        }
    }

    /// Push buttons: a rounded gradient pill behind the label text.
    public struct Button: Codable, Hashable, Sendable {
        /// Gradient color at the pill's top edge.
        public var topColor: ChromeColor

        /// Gradient color at the pill's bottom edge.
        public var bottomColor: ChromeColor

        /// Thin outline around the pill.
        public var strokeColor: ChromeColor?

        /// Corner radius in cell heights (default 0.4).
        public var cornerRadius: Double?

        /// Label color (cells; default: the theme's `buttonForeground`).
        public var textColor: TerminalColor?

        /// Outline while the button has keyboard focus (the focus glow).
        public var focusStrokeColor: ChromeColor?

        /// Gradient top while pressed (default: the resting bottom color).
        public var pressedTopColor: ChromeColor?

        /// Gradient bottom while pressed (default: the resting top color).
        public var pressedBottomColor: ChromeColor?

        /// Creates a button style.
        public init(
            topColor: ChromeColor,
            bottomColor: ChromeColor,
            strokeColor: ChromeColor? = nil,
            cornerRadius: Double? = nil,
            textColor: TerminalColor? = nil,
            focusStrokeColor: ChromeColor? = nil,
            pressedTopColor: ChromeColor? = nil,
            pressedBottomColor: ChromeColor? = nil
        ) {
            self.topColor = topColor
            self.bottomColor = bottomColor
            self.strokeColor = strokeColor
            self.cornerRadius = cornerRadius
            self.textColor = textColor
            self.focusStrokeColor = focusStrokeColor
            self.pressedTopColor = pressedTopColor
            self.pressedBottomColor = pressedBottomColor
        }
    }

    /// The desktop backdrop: a full-screen vertical gradient the windows
    /// float over (the desktop's cells go transparent so it shows through).
    public struct DesktopBackdrop: Codable, Hashable, Sendable {
        /// Gradient color at the screen top.
        public var topColor: ChromeColor

        /// Gradient color at the screen bottom.
        public var bottomColor: ChromeColor

        /// Creates a backdrop style.
        public init(topColor: ChromeColor, bottomColor: ChromeColor) {
            self.topColor = topColor
            self.bottomColor = bottomColor
        }
    }

    /// How the vector layer fills the SURFACES — window bodies and the
    /// chrome strips over them — when the theme wants them translucent.
    ///
    /// Cells cannot be part-way transparent: a cell either carries a colour
    /// or it carries the terminal's default, and the terminal decides how
    /// solid that default is. So a translucent surface is drawn by the
    /// vector layer under the text, and the cells above it are cleared to the
    /// default so it shows through — the same trick the desktop backdrop and
    /// the vector titlebar already use.
    ///
    /// **Chrome is always at least as opaque as the window it covers.** A
    /// menu you can read the document through is a menu you cannot read, and
    /// a menu bar that dissolves into the window under it stops reading as a
    /// separate strip. ``init(windowFill:chromeFill:cornerRadius:)`` enforces
    /// it rather than trusting each theme to remember.
    public struct Surface: Codable, Hashable, Sendable {
        /// Fill behind a window's body — the translucent one.
        public var windowFill: ChromeColor

        /// Fill behind menus, the menu bar and toolbars.
        public var chromeFill: ChromeColor

        /// Corner radius for the window fill, in cell heights.
        public var cornerRadius: Double?

        /// Creates a surface style, raising `chromeFill`'s alpha to the
        /// window's when a theme asks for chrome you can see through more
        /// than the document.
        public init(windowFill: ChromeColor, chromeFill: ChromeColor, cornerRadius: Double? = nil) {
            self.windowFill = windowFill
            self.chromeFill = chromeFill
            self.chromeFill.alpha = max(chromeFill.alpha, windowFill.alpha)
            self.cornerRadius = cornerRadius
        }
    }

    /// Titlebar styling, or `nil` to keep the cell-drawn top border.
    public var titleBar: TitleBar?

    /// Translucent surface fills, or `nil` for solid cell backgrounds.
    public var surface: Surface?

    /// Button styling, or `nil` to keep cell-drawn buttons.
    public var button: Button?

    /// Desktop backdrop, or `nil` to keep the cell-filled desktop.
    public var desktop: DesktopBackdrop?

    /// Soft shadow behind floating windows (needs a `desktop` backdrop to
    /// show through), usually translucent black. `nil` for none.
    public var windowShadow: ChromeColor?

    /// Creates a vector chrome block.
    public init(
        titleBar: TitleBar? = nil,
        button: Button? = nil,
        desktop: DesktopBackdrop? = nil,
        windowShadow: ChromeColor? = nil,
        surface: Surface? = nil
    ) {
        self.surface = surface
        self.titleBar = titleBar
        self.button = button
        self.desktop = desktop
        self.windowShadow = windowShadow
    }
}

// MARK: - Palette (one context's slots — all optional)

/// One context's slot values. Every field is optional: `nil` inherits through
/// the fallback chain (ending at `base`, which must be complete). Flat,
/// descriptive keys make it a clean JSON object; missing keys decode to `nil`
/// and `nil` fields are omitted on encode.
public struct ThemePalette: Codable, Hashable, Sendable {
    /// Body text color.
    public var foreground: TerminalColor?
    /// Window/panel background.
    public var background: TerminalColor?
    /// Attributes for ordinary text.
    public var baseAttributes: CellFlags?

    /// Accent color.
    public var accent: TerminalColor?
    /// Secondary accent — chrome tinting (toolbar items) distinct from the
    /// content accent. `nil` inherits, ultimately falling back to `accent`.
    public var secondaryAccent: TerminalColor?
    /// Warning accent color.
    public var warningAccent: TerminalColor?
    /// Error accent color.
    public var errorAccent: TerminalColor?

    /// Chart axis and tick-label color. `nil` falls back to
    /// `placeholderForeground`.
    public var chartAxisColor: TerminalColor?
    /// The data-series palette charts cycle through (`chartData1`…`10` in
    /// stylesheets). `nil` derives from the accents at draw time.
    public var chartData: [TerminalColor]?

    /// Mnemonic (accelerator) letter color.
    public var acceleratorColor: TerminalColor?
    /// Mnemonic (accelerator) letter attributes.
    public var acceleratorAttributes: CellFlags?

    /// Selected-row text color.
    public var selectionForeground: TerminalColor?
    /// Selected-row background.
    public var selectionBackground: TerminalColor?
    /// Selected-row attributes.
    public var selectionAttributes: CellFlags?

    /// Header text color.
    public var headerForeground: TerminalColor?
    /// Header background.
    public var headerBackground: TerminalColor?
    /// Header attributes.
    public var headerAttributes: CellFlags?

    /// Toolbar/ribbon strip text color. `nil` falls back to the header —
    /// the slot exists so a theme can dress the toolbar as chrome (Turbo's
    /// gray bar on the blue document) WITHOUT dragging window titles and
    /// folder tabs, which also wear `header`, along with it.
    public var toolbarForeground: TerminalColor?
    /// Toolbar/ribbon strip background. `nil` falls back to the header.
    public var toolbarBackground: TerminalColor?

    /// Border line color.
    public var borderForeground: TerminalColor?
    /// Border background.
    public var borderBackground: TerminalColor?
    /// Frame style for window/panel borders.
    public var borderStyle: BorderStyle?
    /// Style for interior dividers and separators.
    public var dividerStyle: BorderStyle?
    /// Whether dividers weld into borders.
    public var dividerConnection: DividerConnection?

    /// Scrollbar thumb color.
    public var scrollbarThumb: TerminalColor?
    /// Scrollbar track color.
    public var scrollbarTrack: TerminalColor?

    /// Placeholder text color.
    public var placeholderForeground: TerminalColor?
    /// Placeholder background.
    public var placeholderBackground: TerminalColor?
    /// Placeholder attributes.
    public var placeholderAttributes: CellFlags?

    /// Editable-field text color.
    public var fieldForeground: TerminalColor?
    /// Editable-field background.
    public var fieldBackground: TerminalColor?
    /// Editable-field attributes.
    public var fieldAttributes: CellFlags?

    /// Ordinary button text color.
    public var buttonForeground: TerminalColor?
    /// Ordinary button fill.
    public var buttonBackground: TerminalColor?
    /// Button drop-shadow color.
    public var buttonShadowColor: TerminalColor?

    /// Default button text color.
    public var defaultButtonForeground: TerminalColor?
    /// Default button fill.
    public var defaultButtonBackground: TerminalColor?

    /// Destructive button text color.
    public var destructiveButtonForeground: TerminalColor?
    /// Destructive button fill.
    public var destructiveButtonBackground: TerminalColor?

    /// Vector chrome styling for VTG terminals (Phase 10). `nil` inherits;
    /// unresolved anywhere means "no chrome — cells only".
    public var vector: VectorChrome?

    /// An empty palette (everything inherits).
    public init() {}
}

// MARK: - Resolved theme (flat, complete — what controls draw with)

/// A fully-resolved palette for one context: every slot has a value. Controls
/// read the CellStyle conveniences (`.selection`, `.header`, …); CSS layers on
/// top by writing the flat stored properties.
public struct ResolvedTheme: Hashable, Sendable {
    /// Body text color.
    public var foreground: TerminalColor
    /// Window/panel background.
    public var background: TerminalColor
    /// Attributes for ordinary text.
    public var baseAttributes: CellFlags

    /// Accent color.
    public var accent: TerminalColor
    /// Secondary accent: chrome tinting (toolbar items), resolved to
    /// `accent` when no palette in the chain sets one — so themes that
    /// predate the slot keep their look.
    public var secondaryAccent: TerminalColor
    /// Warning accent color.
    public var warningAccent: TerminalColor
    /// Error accent color.
    public var errorAccent: TerminalColor

    /// Chart axis and tick-label color (resolved to `placeholderForeground`
    /// when unset).
    public var chartAxisColor: TerminalColor
    /// The explicit data-series palette, or empty to derive from the
    /// accents — read through ``chartData(_:)``, never directly.
    public var chartDataColors: [TerminalColor]

    /// The mnemonic (accelerator) letter's color — red in Turbo. Overlaid on
    /// the surrounding cell's background, keeping menus/buttons intact.
    public var acceleratorColor: TerminalColor
    /// Attributes for the mnemonic letter (e.g. `.underline` on colorless themes).
    public var acceleratorAttributes: CellFlags

    /// Selected-row text color.
    public var selectionForeground: TerminalColor
    /// Selected-row background.
    public var selectionBackground: TerminalColor
    /// Selected-row attributes.
    public var selectionAttributes: CellFlags

    /// Header text color.
    public var headerForeground: TerminalColor
    /// Header background.
    public var headerBackground: TerminalColor
    /// Header attributes.
    public var headerAttributes: CellFlags

    /// Toolbar/ribbon strip text color (resolved to the header's when
    /// unset — see the palette slot's rationale).
    public var toolbarForeground: TerminalColor
    /// Toolbar/ribbon strip background (resolved to the header's when
    /// unset).
    public var toolbarBackground: TerminalColor

    /// Border line color.
    public var borderForeground: TerminalColor
    /// Border background.
    public var borderBackground: TerminalColor
    /// Box-drawing style for window/panel *frames*.
    public var borderStyle: BorderStyle
    /// Box-drawing style for *interior* lines (dividers, split bars, separators).
    /// Usually `.single` even when frames are `.double` (the Borland rule).
    public var dividerStyle: BorderStyle
    /// Whether dividers weld into borders/each other with junctions.
    public var dividerConnection: DividerConnection

    /// Scrollbar thumb color.
    public var scrollbarThumb: TerminalColor
    /// Scrollbar track color.
    public var scrollbarTrack: TerminalColor

    /// Placeholder text color.
    public var placeholderForeground: TerminalColor
    /// Placeholder background.
    public var placeholderBackground: TerminalColor
    /// Placeholder attributes.
    public var placeholderAttributes: CellFlags

    /// Editable-field text color.
    public var fieldForeground: TerminalColor
    /// Editable-field background.
    public var fieldBackground: TerminalColor
    /// Editable-field attributes.
    public var fieldAttributes: CellFlags

    /// The resting fill for an ordinary (non-default) button. Themes that want
    /// the minimal "accent text" look set the background to the window's own,
    /// so the pill is invisible; a theme like Turbo gives it a distinct fill.
    public var buttonForeground: TerminalColor
    /// Ordinary button fill.
    public var buttonBackground: TerminalColor

    /// Drop-shadow color for buttons — `.standard` (the default) means no
    /// shadow. When set (Turbo: black), buttons render a shadow one cell
    /// right and one row below, and pressing animates the face onto it.
    public var buttonShadowColor: TerminalColor

    /// Default button text color.
    public var defaultButtonForeground: TerminalColor
    /// Default button fill.
    public var defaultButtonBackground: TerminalColor

    /// Destructive button text color.
    public var destructiveButtonForeground: TerminalColor
    /// Destructive button fill.
    public var destructiveButtonBackground: TerminalColor

    /// Vector chrome styling, when the theme defines any (Phase 10). Views
    /// only consult it while the frame carries a `ChromeSurface`, so it is
    /// inert on plain terminals.
    public var vector: VectorChrome?

    /// Stylesheet properties TUIKit does not know, kept as declared —
    /// CSS is open-ended, and this is where the open end arrives. An app
    /// that styles `glow-color: #ff8800;` reads it here (see
    /// ``customColor(_:)``); themes themselves never populate it.
    public var custom: [String: StyleDeclaration.Value] = [:]

    /// A custom stylesheet property's color value, when it is one.
    ///
    /// - Parameter name: The property name as written in the sheet.
    public func customColor(_ name: String) -> TerminalColor? {
        if case .color(let color) = custom[name] {
            return color
        }

        return nil
    }

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

    /// Toolbar and ribbon strips (falls back to `header` when the theme
    /// doesn't split them).
    public var toolbar: CellStyle {
        CellStyle(foreground: toolbarForeground, background: toolbarBackground, flags: headerAttributes)
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

    /// An ordinary (non-default) button's resting fill.
    public var button: CellStyle {
        CellStyle(foreground: buttonForeground, background: buttonBackground)
    }

    /// The button drop-shadow color, or `nil` when the theme has none.
    public var buttonShadow: TerminalColor? {
        buttonShadowColor == .standard ? nil : buttonShadowColor
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
    ///
    /// When the accelerator color *is* the surface's background (surface
    /// themes derive both from the accent, so a default button's pill and the
    /// mnemonic collide), the letter keeps the face's own foreground instead —
    /// the attributes (underline) still mark it, and it stays visible.
    public func accelerator(over base: CellStyle) -> CellStyle {
        var style = base

        if acceleratorColor != base.background {
            style.foreground = acceleratorColor
        }

        style.flags.formUnion(acceleratorAttributes)
        return style
    }

    /// The data-series ink for chart series `index` (0-based), cycling.
    ///
    /// An explicit palette (`chartData` in the theme, `chart-data-1`…`10`
    /// in a stylesheet) is used as given; without one the palette derives
    /// from the slots every theme already has — `chartAccent`,
    /// `warningAccent`, `errorAccent`, `foreground` — so charts are legible
    /// under any theme, colorless ones included.
    public func chartData(_ index: Int) -> TerminalColor {
        let palette = chartDataColors.isEmpty
            ? [chartAccent, warningAccent, errorAccent, foreground]
            : chartDataColors
        let count = palette.count
        return palette[((index % count) + count) % count]
    }

    /// The accent charts derive their first series from: the accent — unless
    /// the accent IS the surface (a theme may point it at a surface on
    /// purpose), where invisible data would be worse than un-tinted data.
    /// Then the body foreground.
    var chartAccent: TerminalColor {
        accent != background ? accent : foreground
    }

    /// De-emphasized chart text (axes, ticks, waiting time): the chart-axis
    /// slot on the chart's own surface. Deliberately no background — the
    /// placeholder slot this falls back to carries one tuned for other
    /// surfaces (Turbo: gray toolbars), and a chart must not import it.
    var chartDeemphasis: CellStyle {
        CellStyle(foreground: chartAxisColor, flags: placeholderAttributes)
    }

    /// The accent for a focus/drag cue drawn over `background`, or nil when
    /// it would vanish into it.
    ///
    /// A theme may point `accent` AT a surface on purpose — Turbo's content
    /// window makes it the document blue so toolbar tinting sits right on
    /// the gray chrome — and a divider recoloring its line to that accent
    /// while focused disappeared into its own window, taking the grab
    /// handle's visibility with it. No cue beats an invisible control: the
    /// same rule colorless themes already follow (`.standard` accent → no
    /// recolor), extended to accents that merely match this surface.
    public func cueAccent(over background: TerminalColor) -> TerminalColor? {
        guard accent != .standard, accent != background else {
            return nil
        }

        return accent
    }
}

// MARK: - Theme definition (the matrix)

/// A named theme: a complete `base` palette plus optional per-context overlays.
/// Codable, so themes ship and load as JSON.
public struct Theme: Codable, Hashable, Sendable {
    /// The theme's display name.
    public var name: String
    /// The complete base palette every context falls back to.
    public var base: ThemePalette
    /// Overlay for the desktop context.
    public var desktop: ThemePalette?
    /// Overlay for the content-window context.
    public var contentWindow: ThemePalette?
    /// Overlay for secondary windows.
    public var secondaryWindows: ThemePalette?
    /// Overlay for modal windows.
    public var modalWindows: ThemePalette?
    /// Overlay for accessory views.
    public var accessoryView: ThemePalette?
    /// Overlay for menu dropdowns and pop-up lists (see
    /// ``ThemeContext/menus``). `nil` — the common case — means menus
    /// simply wear `base`, the chrome surface.
    public var menus: ThemePalette?

    /// Creates a theme from a base palette and optional per-context overlays.
    public init(
        name: String,
        base: ThemePalette,
        desktop: ThemePalette? = nil,
        contentWindow: ThemePalette? = nil,
        secondaryWindows: ThemePalette? = nil,
        modalWindows: ThemePalette? = nil,
        accessoryView: ThemePalette? = nil,
        menus: ThemePalette? = nil
    ) {
        self.name = name
        self.base = base
        self.desktop = desktop
        self.contentWindow = contentWindow
        self.secondaryWindows = secondaryWindows
        self.modalWindows = modalWindows
        self.accessoryView = accessoryView
        self.menus = menus
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

        var vector: VectorChrome?
        for palette in chain where palette.vector != nil {
            vector = palette.vector
            break
        }

        // Slots with a sibling-slot fallback rather than a `.standard` one.
        let resolvedAccent = color(\.accent)

        var secondaryAccent = resolvedAccent
        for palette in chain where palette.secondaryAccent != nil {
            secondaryAccent = palette.secondaryAccent!
            break
        }

        var chartAxisColor = color(\.placeholderForeground)
        for palette in chain where palette.chartAxisColor != nil {
            chartAxisColor = palette.chartAxisColor!
            break
        }

        var toolbarForeground = color(\.headerForeground)
        for palette in chain where palette.toolbarForeground != nil {
            toolbarForeground = palette.toolbarForeground!
            break
        }

        var toolbarBackground = color(\.headerBackground)
        for palette in chain where palette.toolbarBackground != nil {
            toolbarBackground = palette.toolbarBackground!
            break
        }

        var chartDataColors: [TerminalColor] = []
        for palette in chain where palette.chartData != nil {
            chartDataColors = palette.chartData!
            break
        }

        return ResolvedTheme(
            foreground: color(\.foreground),
            background: color(\.background),
            baseAttributes: flags(\.baseAttributes),
            accent: resolvedAccent,
            secondaryAccent: secondaryAccent,
            warningAccent: color(\.warningAccent),
            errorAccent: color(\.errorAccent),
            chartAxisColor: chartAxisColor,
            chartDataColors: chartDataColors,
            acceleratorColor: color(\.acceleratorColor),
            acceleratorAttributes: flags(\.acceleratorAttributes),
            selectionForeground: color(\.selectionForeground),
            selectionBackground: color(\.selectionBackground),
            selectionAttributes: flags(\.selectionAttributes),
            headerForeground: color(\.headerForeground),
            headerBackground: color(\.headerBackground),
            headerAttributes: flags(\.headerAttributes),
            toolbarForeground: toolbarForeground,
            toolbarBackground: toolbarBackground,
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
            buttonForeground: color(\.buttonForeground),
            buttonBackground: color(\.buttonBackground),
            buttonShadowColor: color(\.buttonShadowColor),
            defaultButtonForeground: color(\.defaultButtonForeground),
            defaultButtonBackground: color(\.defaultButtonBackground),
            destructiveButtonForeground: color(\.destructiveButtonForeground),
            destructiveButtonBackground: color(\.destructiveButtonBackground),
            vector: vector
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

        case .menus:
            // Floating chrome: never the surface being covered.
            return [menus, base].compactMap { $0 }
        }
    }
}
