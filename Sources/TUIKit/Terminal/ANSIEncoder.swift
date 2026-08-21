/// Encodes cells and styles into ANSI escape sequences.
///
/// The encoder is pure — bytes in, string out, no terminal state — so it is
/// fully unit-testable. The future `ANSIDriver` composes this encoder with
/// raw-mode handling and input decoding; the demo app uses it directly to
/// print styled buffers to a regular terminal.
public enum ANSIEncoder {
    /// The Select Graphic Rendition sequence for a style.
    ///
    /// The sequence always starts from a reset (`0`), so encoded styles are
    /// self-contained and order-independent.
    ///
    /// - Parameter style: Style to encode.
    /// - Returns: The SGR escape sequence for the style.
    public static func sequence(for style: CellStyle) -> String {
        var codes: [String] = ["0"]

        if style.flags.contains(.bold) { codes.append("1") }
        if style.flags.contains(.dim) { codes.append("2") }
        if style.flags.contains(.italic) { codes.append("3") }
        if style.flags.contains(.underline) { codes.append("4") }
        if style.flags.contains(.inverse) { codes.append("7") }
        if style.flags.contains(.strikethrough) { codes.append("9") }

        codes.append(contentsOf: colorCodes(style.foreground, isForeground: true))
        codes.append(contentsOf: colorCodes(style.background, isForeground: false))

        return "\u{1B}[\(codes.joined(separator: ";"))m"
    }

    /// The SGR reset sequence.
    public static let reset = "\u{1B}[0m"

    /// Encodes a full buffer as styled text lines.
    ///
    /// Consecutive cells with the same style share one escape sequence, and
    /// every line ends with a reset so partial output never bleeds styles
    /// into the surrounding terminal.
    ///
    /// - Parameter buffer: Buffer to encode.
    /// - Returns: One ANSI-styled string per row.
    public static func encode(_ buffer: CellBuffer) -> [String] {
        var lines: [String] = []

        for y in 0..<buffer.size.height {
            var line = ""
            var activeStyle: CellStyle? = nil

            for x in 0..<buffer.size.width {
                let cell = buffer[Point(x: x, y: y)]

                if cell.style != activeStyle {
                    line += sequence(for: cell.style)
                    activeStyle = cell.style
                }

                // A continuation cell is the right half of the glyph before
                // it: the terminal's cursor is already here, and emitting
                // anything would push the rest of the row one column right.
                // The style run still merges, since it carries the same style.
                guard !cell.isContinuation else {
                    continue
                }

                line.append(cell.character)
            }

            lines.append(line + reset)
        }

        return lines
    }

    /// Composes the wire frame for a set of encoded lines, repainting only
    /// what changed.
    ///
    /// Every emitted row is prefixed with an absolute cursor move, so rows
    /// are independent and any subset can be rewritten. With no previous
    /// frame — or one of a different height — every row is emitted. An
    /// identical frame produces an empty string: write nothing.
    ///
    /// This is what keeps an idle app quiet. A one-cell change (a status
    /// clock) repaints one row, not the whole screen — the difference
    /// between ~100 bytes and ~100 KB a second flowing at a terminal
    /// whose parser, scrollback, and renderer all have to swallow it.
    ///
    /// - Parameters:
    ///   - lines: This frame's encoded rows, from ``encode(_:)``.
    ///   - previous: The rows last presented, or `nil` to force a full paint.
    /// - Returns: The bytes to write — possibly empty.
    public static func frame(lines: [String], previous: [String]?) -> String {
        var output = ""

        for (row, line) in lines.enumerated() {
            if let previous, previous.count == lines.count, previous[row] == line {
                continue
            }

            output += "\u{1B}[\(row + 1);1H" + line
        }

        return output
    }

    // Maps a color to its SGR parameter codes.
    private static func colorCodes(_ color: TerminalColor, isForeground: Bool) -> [String] {
        switch color {
        case .standard:
            return []

        case .named(let named):
            let base = namedColorBase(named)
            return [String(isForeground ? base : base + 10)]

        case .palette(let index):
            return [isForeground ? "38" : "48", "5", String(index)]

        case .rgb(let red, let green, let blue):
            return [isForeground ? "38" : "48", "2", String(red), String(green), String(blue)]
        }
    }

    // The foreground SGR code for a named color; backgrounds add 10.
    private static func namedColorBase(_ color: TerminalColor.NamedColor) -> Int {
        switch color {
        case .black: 30
        case .red: 31
        case .green: 32
        case .yellow: 33
        case .blue: 34
        case .magenta: 35
        case .cyan: 36
        case .white: 37
        case .brightBlack: 90
        case .brightRed: 91
        case .brightGreen: 92
        case .brightYellow: 93
        case .brightBlue: 94
        case .brightMagenta: 95
        case .brightCyan: 96
        case .brightWhite: 97
        }
    }
}
