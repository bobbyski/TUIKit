// R8a — the JavaScript highlighting lexer: strings in all three quote forms
// (template interpolation included), comments, numbers, keywords, and regex
// literals — which are the reason a keyword matcher cannot do this: `/` is
// division or the start of a pattern depending on what came before it.

/// A lean line-at-a-time JavaScript lexer for ``SyntaxTextView``.
///
/// State packing (see ``HighlightState``): bits 0–3 are the mode (normal,
/// block comment, template literal), bits 4–7 the count of template
/// literals currently open, bits 8–15 the brace depth inside the innermost
/// `${…}`. Pathological nesting deeper than the packing survives a single
/// line fine (a real stack runs within the line) and degrades gracefully
/// across lines.
public struct JavaScriptHighlighter: SyntaxHighlighting {
    /// Creates a JavaScript highlighter.
    public init() {}

    // Mode bits.
    private static let modeNormal = 0
    private static let modeBlockComment = 1
    private static let modeTemplate = 2

    static func packed(mode: Int, templates: Int, braces: Int) -> Int {
        (mode & 0xF) | (min(templates, 15) << 4) | (min(braces, 255) << 8)
    }

    static func unpack(_ raw: Int) -> (mode: Int, templates: Int, braces: Int) {
        (raw & 0xF, (raw >> 4) & 0xF, (raw >> 8) & 0xFF)
    }

    /// Keywords plus the literal identifiers that read as keywords.
    public static let keywords: Set<String> = [
        "abstract", "arguments", "async", "await", "break", "case", "catch",
        "class", "const", "continue", "debugger", "default", "delete", "do",
        "else", "enum", "export", "extends", "false", "finally", "for",
        "function", "get", "if", "implements", "import", "in", "instanceof",
        "interface", "let", "new", "null", "of", "return", "set", "static",
        "super", "switch", "this", "throw", "true", "try", "typeof",
        "undefined", "var", "void", "while", "with", "yield",
    ]

    // Keywords a regex may directly follow (`return /x/`, `typeof /x/`).
    private static let regexPermittingKeywords: Set<String> = [
        "return", "typeof", "instanceof", "in", "of", "new", "delete",
        "void", "throw", "do", "else", "yield", "await", "case",
    ]

    /// Lexes one line. See ``SyntaxHighlighting/highlight(line:state:)``.
    public func highlight(line: String, state: inout HighlightState) -> [HighlightSpan] {
        var lexer = Lexer(line: Array(line), state: Self.unpack(state.rawValue))
        let spans = lexer.run()
        state = HighlightState(rawValue: Self.packed(
            mode: lexer.mode,
            templates: lexer.templateLevels,
            braces: lexer.braceDepth
        ))
        return spans
    }

    // The per-line lexer. A struct so `run()` mutates freely.
    struct Lexer {
        let line: [Character]
        var mode: Int
        var templateLevels: Int
        var braceDepth: Int

        var index = 0
        var spans: [HighlightSpan] = []

        // Whether a `/` here would start a regex: true at expression
        // position (after operators, openers, statement keywords, line
        // start), false after something a value ends with.
        var regexAllowed = true

        init(line: [Character], state: (mode: Int, templates: Int, braces: Int)) {
            self.line = line
            self.mode = state.mode
            self.templateLevels = state.templates
            self.braceDepth = state.braces
        }

        mutating func emit(from start: Int, kind: HighlightKind) {
            guard index > start, kind != .plain else {
                return
            }

            spans.append(HighlightSpan(start: start, length: index - start, kind: kind))
        }

        mutating func run() -> [HighlightSpan] {
            // A line beginning inside a multi-line construct finishes it
            // first.
            if mode == JavaScriptHighlighter.modeBlockComment {
                consumeBlockComment(spanStart: index)
            } else if mode == JavaScriptHighlighter.modeTemplate, braceDepth == 0 {
                consumeTemplateText(spanStart: index)
            }

            while index < line.count {
                lexToken()
            }

            return spans
        }

        // MARK: - Multi-line construct tails

        // Comment text until `*/` (or EOL, leaving the mode open). The span
        // starts at `spanStart` so an opener lexed this line includes its
        // `/*`.
        private mutating func consumeBlockComment(spanStart: Int) {
            while index < line.count {
                if line[index] == "*", index + 1 < line.count, line[index + 1] == "/" {
                    index += 2
                    mode = JavaScriptHighlighter.modeNormal
                    emit(from: spanStart, kind: .comment)
                    return
                }

                index += 1
            }

            emit(from: spanStart, kind: .comment)   // still open at EOL
        }

        // Template-literal text until its backtick or a `${`, spanning from
        // `spanStart` (the opening backtick when it is on this line).
        private mutating func consumeTemplateText(spanStart: Int) {
            while index < line.count {
                let character = line[index]

                if character == "\\" {
                    index += min(2, line.count - index)
                    continue
                }

                if character == "`" {
                    index += 1
                    templateLevels = max(0, templateLevels - 1)
                    mode = templateLevels > 0 ? JavaScriptHighlighter.modeTemplate : JavaScriptHighlighter.modeNormal
                    emit(from: spanStart, kind: .string)
                    regexAllowed = false
                    return
                }

                if character == "$", index + 1 < line.count, line[index + 1] == "{" {
                    index += 2
                    braceDepth = 1   // now lexing the interpolation expression
                    emit(from: spanStart, kind: .string)
                    regexAllowed = true
                    return
                }

                index += 1
            }

            emit(from: spanStart, kind: .string)   // template continues past EOL
        }

        // MARK: - Tokens

        private mutating func lexToken() {
            let character = line[index]

            if character == " " || character == "\t" {
                index += 1
                return
            }

            if character == "/" {
                if peek(1) == "/" {
                    let start = index
                    index = line.count
                    emit(from: start, kind: .comment)
                    return
                }

                if peek(1) == "*" {
                    let start = index
                    index += 2   // past the `/*`, so `/*/` does not self-close
                    mode = JavaScriptHighlighter.modeBlockComment
                    consumeBlockComment(spanStart: start)
                    return
                }

                if regexAllowed {
                    lexRegex()
                    return
                }

                index += 1   // division
                regexAllowed = true
                return
            }

            if character == "\"" || character == "'" {
                lexString(quote: character)
                return
            }

            if character == "`" {
                let start = index
                index += 1
                templateLevels += 1
                mode = JavaScriptHighlighter.modeTemplate
                braceDepth = 0
                consumeTemplateText(spanStart: start)
                return
            }

            if mode == JavaScriptHighlighter.modeTemplate, braceDepth > 0 {
                // Inside `${…}`: braces nest, `}` at depth 1 returns to
                // template text.
                if character == "{" {
                    braceDepth += 1
                    index += 1
                    regexAllowed = true
                    return
                }

                if character == "}" {
                    braceDepth -= 1
                    index += 1

                    if braceDepth == 0 {
                        consumeTemplateText(spanStart: index)
                    }

                    return
                }
            }

            if character.isNumber || (character == "." && (peek(1)?.isNumber ?? false)) {
                lexNumber()
                return
            }

            if character.isLetter || character == "_" || character == "$" {
                lexIdentifier()
                return
            }

            // Punctuation: most of it puts the lexer back at expression
            // position (a regex may follow `(`, `=`, `,`, `{`, `;`, …);
            // closers that end a value do not.
            index += 1
            regexAllowed = !(character == ")" || character == "]")
        }

        private mutating func lexString(quote: Character) {
            let start = index
            index += 1

            while index < line.count {
                let character = line[index]

                if character == "\\" {
                    index += min(2, line.count - index)
                    continue
                }

                index += 1

                if character == quote {
                    break
                }
            }

            emit(from: start, kind: .string)
            regexAllowed = false
        }

        private mutating func lexRegex() {
            let start = index
            index += 1
            var inClass = false

            while index < line.count {
                let character = line[index]

                if character == "\\" {
                    index += min(2, line.count - index)
                    continue
                }

                if character == "[" {
                    inClass = true
                } else if character == "]" {
                    inClass = false
                } else if character == "/", !inClass {
                    index += 1

                    // Flags.
                    while index < line.count, line[index].isLetter {
                        index += 1
                    }

                    break
                }

                index += 1
            }

            emit(from: start, kind: .regex)
            regexAllowed = false
        }

        private mutating func lexNumber() {
            let start = index

            while index < line.count {
                let character = line[index]

                guard character.isHexDigit || character == "." || character == "_"
                        || character == "x" || character == "X" || character == "o" || character == "O"
                        || character == "b" || character == "B" || character == "n"
                        || character == "e" || character == "E"
                        || ((character == "+" || character == "-") && (line[index - 1] == "e" || line[index - 1] == "E")) else {
                    break
                }

                index += 1
            }

            emit(from: start, kind: .number)
            regexAllowed = false
        }

        private mutating func lexIdentifier() {
            let start = index

            while index < line.count {
                let character = line[index]

                guard character.isLetter || character.isNumber || character == "_" || character == "$" else {
                    break
                }

                index += 1
            }

            let word = String(line[start..<index])

            if JavaScriptHighlighter.keywords.contains(word) {
                emit(from: start, kind: .keyword)
                regexAllowed = JavaScriptHighlighter.regexPermittingKeywords.contains(word)
            } else {
                regexAllowed = false   // an identifier ends a value
            }
        }

        private func peek(_ offset: Int) -> Character? {
            let position = index + offset
            return position < line.count ? line[position] : nil
        }
    }
}
