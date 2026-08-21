// R8b — the highlighting seam. `SyntaxTextView` colours lines through this
// protocol; the built-in lexers (HTML, JavaScript, CSS — R8a) are its first
// implementations, and a consumer with exact tokens of its own (a browser's
// view-source, say) can hand the view a highlighter instead of a language
// string.
//
// The `inout HighlightState` is the whole design: highlighting must be
// per-line to stay cheap for a big file, but a multi-line comment, a
// template literal, or a `<script>` body all cross line boundaries.
// Carrying the end state forward is what makes line-at-a-time correct;
// `SyntaxTextView` already caches per line, so it caches the state
// alongside — and an edit that changes a line's END state invalidates
// everything after it automatically.

/// The lexing state one line ends in, carried into the next.
///
/// Opaque to everything but the highlighter that produced it: an `Int` the
/// implementation packs however it likes (mode bits, nesting depths, an
/// embedded sub-highlighter's state). Two lines with equal states highlight
/// identically, which is what lets the view cache aggressively.
public struct HighlightState: Hashable, Sendable {
    /// The highlighter's packed state.
    public var rawValue: Int

    /// Creates a state.
    public init(rawValue: Int = 0) {
        self.rawValue = rawValue
    }

    /// The state before the first line: no comment open, no string open.
    public static let initial = HighlightState()
}

/// What a highlighted span *is* — semantic, never a colour. The view maps
/// kinds onto styles, so a highlighter works under every theme.
public enum HighlightKind: Hashable, Sendable, CaseIterable {
    /// Ordinary source text.
    case plain

    /// A language keyword (`function`, `return`, `@media`).
    case keyword

    /// A string literal, including template literals.
    case string

    /// A numeric literal.
    case number

    /// A comment, line or block.
    case comment

    /// A regular-expression literal — the reason a keyword matcher cannot
    /// highlight JavaScript.
    case regex

    /// A markup tag: the angle brackets and the element name.
    case tag

    /// An attribute name inside a tag (or a CSS property name).
    case attributeName

    /// An attribute value inside a tag.
    case attributeValue

    /// A character entity (`&amp;`).
    case entity

    /// A doctype or other markup declaration.
    case doctype
}

/// One highlighted span within a line, in `Character` offsets.
///
/// Spans never overlap and arrive in order; characters no span covers are
/// ``HighlightKind/plain``.
public struct HighlightSpan: Hashable, Sendable {
    /// Offset of the first character.
    public var start: Int

    /// Number of characters.
    public var length: Int

    /// What the span is.
    public var kind: HighlightKind

    /// Creates a span.
    public init(start: Int, length: Int, kind: HighlightKind) {
        self.start = start
        self.length = length
        self.kind = kind
    }
}

/// Produces styled spans for one line at a time, threading state across
/// lines. See the file header for why this is the shape.
public protocol SyntaxHighlighting: Sendable {
    /// Styled spans for one line, given the state the previous line ended
    /// in. On return, `state` is the state THIS line ends in.
    ///
    /// - Parameters:
    ///   - line: One line of source, without its newline.
    ///   - state: In: the previous line's end state. Out: this line's.
    /// - Returns: Non-overlapping spans in order; gaps are plain.
    func highlight(line: String, state: inout HighlightState) -> [HighlightSpan]
}

/// The built-in highlighters, keyed by the `language` strings
/// ``SyntaxTextView`` accepts.
public enum SyntaxHighlighters {
    /// The built-in highlighter for a language, or nil when the language
    /// falls through to the RichSwift keyword path (`swift`, `python`,
    /// `json`, …).
    public static func builtIn(for language: String) -> (any SyntaxHighlighting)? {
        switch language.lowercased() {
        case "html", "htm", "xhtml":
            return HTMLHighlighter()

        case "js", "javascript", "mjs", "jsx":
            return JavaScriptHighlighter()

        case "css":
            return CSSHighlighter()
        case "markdown", "md":
            return MarkdownHighlighter()

        default:
            return nil
        }
    }
}

extension HighlightKind {
    /// The cell style a kind renders with — chosen to match the RichSwift
    /// syntax palette (bold magenta keywords, green strings, cyan numbers,
    /// dim comments) so a Swift file and an HTML file read as one family.
    var cellStyle: CellStyle {
        switch self {
        case .plain:
            return CellStyle()

        case .keyword:
            return CellStyle(foreground: .named(.magenta), flags: [.bold])

        case .string, .attributeValue:
            return CellStyle(foreground: .named(.green))

        case .number:
            return CellStyle(foreground: .named(.cyan))

        case .comment:
            return CellStyle(flags: [.dim])

        case .regex:
            return CellStyle(foreground: .named(.red))

        case .tag:
            // Bright, not plain blue: markup must survive blue surfaces
            // (Turbo's content window) as well as light ones.
            return CellStyle(foreground: .named(.brightBlue), flags: [.bold])

        case .attributeName:
            return CellStyle(foreground: .named(.cyan))

        case .entity:
            return CellStyle(foreground: .named(.yellow))

        case .doctype:
            return CellStyle(flags: [.dim])
        }
    }
}
