import RichSwift

/// Displays RichSwift content — markup or any `RichRenderable` — as cells.
///
/// This is the TUIKit↔RichSwift bridge (the Textual↔Rich relationship):
/// RichSwift renders rich *content*, TUIKit composites it into the
/// interactive screen. Two paths:
///
/// - **Markup** goes through `Markup.parse`, so styles map directly onto
///   cells with no escape sequences involved:
///
///   ```swift
///   let banner = RichText(markup: "[bold magenta]Build[/] [green]passed[/]")
///   ```
///
/// - **Renderables** (tables, panels, markdown, syntax, anything
///   `RichRenderable`) render at the view's width and are decoded back
///   into styled cells:
///
///   ```swift
///   let table = RichText(renderable: buildMatrix)   // a RichSwift Table
///   ```
///
/// The view is display-only (no focus, no input) and never wraps — content
/// wider than the view truncates, taller content clips.
@MainActor
public final class RichText: TUIView {
    // What the view shows.
    private enum Content {
        case markup(String)
        case renderable(any RichRenderable)
    }

    private var content: Content {
        didSet {
            cachedWidth = nil
            cachedLines = []
            superview?.setNeedsLayout()
            setNeedsDisplay()
        }
    }

    // Lines rendered for `cachedWidth`.
    private var cachedLines: [[StyledRun]] = []
    private var cachedWidth: Int?

    /// Creates a view showing Rich-style markup.
    ///
    /// - Parameter markup: Markup text (`"[bold red]Error[/]"`).
    public init(markup: String) {
        self.content = .markup(markup)
        super.init(frame: .zero)
    }

    /// Creates a view showing any RichSwift renderable.
    ///
    /// - Parameter renderable: Table, panel, markdown, syntax, and so on.
    public init(renderable: any RichRenderable) {
        self.content = .renderable(renderable)
        super.init(frame: .zero)
    }

    /// Replaces the content with markup.
    ///
    /// - Parameter markup: Markup text.
    public func setMarkup(_ markup: String) {
        content = .markup(markup)
    }

    /// Replaces the content with a renderable.
    ///
    /// - Parameter renderable: Table, panel, markdown, syntax, and so on.
    public func setRenderable(_ renderable: any RichRenderable) {
        content = .renderable(renderable)
    }

    /// Natural size: the content rendered without a width constraint.
    public override var intrinsicContentSize: Size? {
        let lines = renderedLines(width: 4096)
        let width = lines.map { $0.reduce(0) { $0 + $1.text.count } }.max() ?? 0
        return Size(width: width, height: lines.count)
    }

    /// Draws the styled lines, truncated to the view's bounds.
    public override func draw(_ painter: Painter) {
        let width = bounds.size.width

        guard width > 0 else {
            return
        }

        for (row, runs) in renderedLines(width: width).enumerated() {
            guard row < bounds.size.height else {
                break
            }

            var x = 0

            for run in runs {
                painter.write(run.text, at: Point(x: x, y: row), style: run.style)
                x += run.text.count
            }
        }
    }

    // MARK: - Rendering

    // Renders (and caches) the content for a width.
    private func renderedLines(width: Int) -> [[StyledRun]] {
        if cachedWidth == width {
            return cachedLines
        }

        let lines: [[StyledRun]]

        switch content {
        case .markup(let markup):
            // Direct path: parsed segments carry their styles; no escapes.
            lines = Self.splitLines(
                Markup.parse(markup).map {
                    StyledRun(text: $0.text, style: CellStyle(rich: $0.style))
                }
            )

        case .renderable(let renderable):
            // Renderables emit an ANSI string; decode it back into cells.
            let context = RenderContext(width: width, colorMode: .standard, markup: true)
            lines = SGRDecoder.lines(from: renderable.render(in: context))
        }

        cachedWidth = width
        cachedLines = lines
        return lines
    }

    // Splits runs containing newlines into per-line run arrays.
    static func splitLines(_ runs: [StyledRun]) -> [[StyledRun]] {
        var lines: [[StyledRun]] = [[]]

        for run in runs {
            let pieces = run.text.split(separator: "\n", omittingEmptySubsequences: false)

            for (index, piece) in pieces.enumerated() {
                if index > 0 {
                    lines.append([])
                }

                if !piece.isEmpty {
                    lines[lines.count - 1].append(StyledRun(text: String(piece), style: run.style))
                }
            }
        }

        return lines
    }
}

/// A run of text sharing one cell style (framework-internal).
struct StyledRun: Equatable {
    var text: String
    var style: CellStyle
}

// MARK: - RichSwift style bridging

extension CellStyle {
    /// Maps a RichSwift style onto a cell style (blink is dropped — cells
    /// have no blink attribute).
    init(rich: RichSwift.Style) {
        self.init()

        if rich.bold { flags.insert(.bold) }
        if rich.dim { flags.insert(.dim) }
        if rich.italic { flags.insert(.italic) }
        if rich.underline { flags.insert(.underline) }
        if rich.strikethrough { flags.insert(.strikethrough) }
        if rich.inverse { flags.insert(.inverse) }

        if let color = rich.foreground, let mapped = TerminalColor(rich: color) {
            foreground = mapped
        }

        if let color = rich.background, let mapped = TerminalColor(rich: color) {
            background = mapped
        }
    }
}

extension TerminalColor {
    /// Maps a RichSwift color; unknown named colors map to `nil`.
    init?(rich: RichSwift.Color) {
        switch rich {
        case .named(let name):
            let lowered = name.lowercased()

            guard let named = NamedColor.allCases.first(where: { $0.rawValue.lowercased() == lowered }) else {
                return nil
            }

            self = .named(named)

        case .indexed(let index):
            self = .palette(index)

        case .rgb(let red, let green, let blue):
            self = .rgb(red: red, green: green, blue: blue)
        }
    }
}

// MARK: - SGR decoding

/// Decodes SGR-styled strings (RichSwift renderable output) into styled
/// runs per line (framework-internal).
///
/// This is the inverse of `ANSIEncoder`, scoped to the SGR subset RichSwift
/// emits: reset, the attribute-on codes, 16-color, 256-color, and RGB
/// foregrounds/backgrounds. Unknown codes and non-SGR sequences are skipped.
enum SGRDecoder {
    /// Splits a styled string into per-line runs.
    ///
    /// - Parameter string: Text containing SGR escape sequences.
    /// - Returns: One run array per line.
    static func lines(from string: String) -> [[StyledRun]] {
        var lines: [[StyledRun]] = [[]]
        var style = CellStyle()
        var buffer = ""

        func flush() {
            if !buffer.isEmpty {
                lines[lines.count - 1].append(StyledRun(text: buffer, style: style))
                buffer.removeAll(keepingCapacity: true)
            }
        }

        var iterator = string.makeIterator()

        while let character = iterator.next() {
            if character == "\u{001B}" {
                flush()

                guard let bracket = iterator.next(), bracket == "[" else {
                    continue
                }

                var parameters = ""

                while let next = iterator.next() {
                    if next.isNumber || next == ";" {
                        parameters.append(next)
                    } else {
                        if next == "m" {
                            apply(parameters, to: &style)
                        }

                        break
                    }
                }

                continue
            }

            if character == "\n" {
                flush()
                lines.append([])
                continue
            }

            buffer.append(character)
        }

        flush()
        return lines
    }

    // Applies one SGR parameter list to a style.
    private static func apply(_ parameters: String, to style: inout CellStyle) {
        let codes = parameters.split(separator: ";").compactMap { Int($0) }
        var index = 0

        // Empty parameters mean reset.
        if codes.isEmpty {
            style = CellStyle()
            return
        }

        while index < codes.count {
            let code = codes[index]

            switch code {
            case 0:
                style = CellStyle()

            case 1:
                style.flags.insert(.bold)

            case 2:
                style.flags.insert(.dim)

            case 3:
                style.flags.insert(.italic)

            case 4:
                style.flags.insert(.underline)

            case 7:
                style.flags.insert(.inverse)

            case 9:
                style.flags.insert(.strikethrough)

            case 30...37:
                style.foreground = .named(TerminalColor.NamedColor.allCases[code - 30])

            case 90...97:
                style.foreground = .named(TerminalColor.NamedColor.allCases[code - 90 + 8])

            case 39:
                style.foreground = .standard

            case 40...47:
                style.background = .named(TerminalColor.NamedColor.allCases[code - 40])

            case 100...107:
                style.background = .named(TerminalColor.NamedColor.allCases[code - 100 + 8])

            case 49:
                style.background = .standard

            case 38, 48:
                // Extended color: 38;5;n or 38;2;r;g;b (and 48;… variants).
                let isBackground = code == 48

                guard index + 1 < codes.count else {
                    return
                }

                if codes[index + 1] == 5, index + 2 < codes.count {
                    let color = TerminalColor.palette(UInt8(clamping: codes[index + 2]))
                    isBackground ? (style.background = color) : (style.foreground = color)
                    index += 2
                } else if codes[index + 1] == 2, index + 4 < codes.count {
                    let color = TerminalColor.rgb(
                        red: UInt8(clamping: codes[index + 2]),
                        green: UInt8(clamping: codes[index + 3]),
                        blue: UInt8(clamping: codes[index + 4])
                    )
                    isBackground ? (style.background = color) : (style.foreground = color)
                    index += 4
                }

            default:
                break
            }

            index += 1
        }
    }
}
