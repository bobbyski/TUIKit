/// Color of a terminal cell's foreground or background.
///
/// Drivers translate these to whatever the terminal supports; views and
/// controls never emit color codes themselves.
public enum TerminalColor: Hashable, Sendable {
    /// The terminal's default color.
    case standard

    /// One of the 16 named ANSI colors.
    case named(NamedColor)

    /// An index into the terminal's 256-color palette.
    case palette(UInt8)

    /// A 24-bit color for terminals that support it.
    case rgb(red: UInt8, green: UInt8, blue: UInt8)

    /// The 16 named ANSI colors.
    public enum NamedColor: String, CaseIterable, Hashable, Sendable {
        case black, red, green, yellow, blue, magenta, cyan, white
        case brightBlack, brightRed, brightGreen, brightYellow
        case brightBlue, brightMagenta, brightCyan, brightWhite
    }
}

/// Text emphasis flags for a terminal cell.
public struct CellFlags: OptionSet, Hashable, Sendable {
    /// Raw bitset value.
    public let rawValue: Int

    /// Creates flags from a raw bitset.
    ///
    /// - Parameter rawValue: Raw bitset value.
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// Bold or increased intensity.
    public static let bold = CellFlags(rawValue: 1 << 0)

    /// Dim or decreased intensity.
    public static let dim = CellFlags(rawValue: 1 << 1)

    /// Italic, where supported.
    public static let italic = CellFlags(rawValue: 1 << 2)

    /// Underlined.
    public static let underline = CellFlags(rawValue: 1 << 3)

    /// Foreground and background swapped.
    public static let inverse = CellFlags(rawValue: 1 << 4)

    /// Struck through, where supported.
    public static let strikethrough = CellFlags(rawValue: 1 << 5)
}

/// Visual style of a terminal cell: colors plus emphasis flags.
public struct CellStyle: Hashable, Sendable {
    /// Foreground (text) color.
    public var foreground: TerminalColor

    /// Background color.
    public var background: TerminalColor

    /// Emphasis flags.
    public var flags: CellFlags

    /// The terminal's default style: default colors, no emphasis.
    public static let `default` = CellStyle()

    /// Creates a cell style.
    ///
    /// - Parameters:
    ///   - foreground: Foreground (text) color.
    ///   - background: Background color.
    ///   - flags: Emphasis flags.
    public init(
        foreground: TerminalColor = .standard,
        background: TerminalColor = .standard,
        flags: CellFlags = []
    ) {
        self.foreground = foreground
        self.background = background
        self.flags = flags
    }
}

/// One terminal cell: a character plus its style.
///
/// Cells are the framework's pixel. Rendering is deterministic all the way
/// down to cells, so tests compare cells (or their text projection) rather
/// than escape-sequence output.
public struct TerminalCell: Hashable, Sendable {
    /// Character shown in the cell.
    public var character: Character

    /// Style applied to the cell.
    public var style: CellStyle

    /// A blank cell in the default style.
    public static let blank = TerminalCell(character: " ")

    /// Creates a cell.
    ///
    /// - Parameters:
    ///   - character: Character shown in the cell.
    ///   - style: Style applied to the cell.
    public init(character: Character, style: CellStyle = .default) {
        self.character = character
        self.style = style
    }
}
