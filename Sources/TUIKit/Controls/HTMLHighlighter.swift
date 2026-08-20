// R8a — the HTML highlighting lexer: tags, attribute names and values,
// comments, doctype, entities, text — and the two embedded islands that
// matter, `<style>` and `<script>`, handed to the CSS and JavaScript
// highlighters with their own state carried across lines.
//
// Deliberately a lexer, not HTMLCore: colouring needs source ranges, error
// tolerance, and restartability from any line — not spec-conformant tree
// construction (see REQUESTS.md R8 for the full argument).

/// A lean line-at-a-time HTML lexer for ``SyntaxTextView``.
///
/// State packing: bits 0–3 the mode (text, comment, tag, doctype, script
/// body, style body), bits 4–5 which island a just-lexed `<script>`/`<style>`
/// open tag leads into, bits 6–7 an attribute-value quote continuing across
/// lines, bits 8+ the embedded island highlighter's own packed state.
public struct HTMLHighlighter: SyntaxHighlighting {
    /// Creates an HTML highlighter.
    public init() {}

    // Modes.
    private static let modeText = 0
    private static let modeComment = 1
    private static let modeTag = 2
    private static let modeDoctype = 3
    private static let modeScript = 4
    private static let modeStyle = 5

    // Pending islands (which body a closing `>` enters).
    private static let islandNone = 0
    private static let islandScript = 1
    private static let islandStyle = 2

    static func packed(mode: Int, island: Int, quote: Int, sub: Int) -> Int {
        (mode & 0xF) | ((island & 0x3) << 4) | ((quote & 0x3) << 6) | (sub << 8)
    }

    static func unpack(_ raw: Int) -> (mode: Int, island: Int, quote: Int, sub: Int) {
        (raw & 0xF, (raw >> 4) & 0x3, (raw >> 6) & 0x3, raw >> 8)
    }

    /// Lexes one line. See ``SyntaxHighlighting/highlight(line:state:)``.
    public func highlight(line: String, state: inout HighlightState) -> [HighlightSpan] {
        let characters = Array(line)
        var (mode, island, quote, sub) = Self.unpack(state.rawValue)
        var spans: [HighlightSpan] = []
        var index = 0

        func emit(from start: Int, kind: HighlightKind) {
            if index > start, kind != .plain {
                spans.append(HighlightSpan(start: start, length: index - start, kind: kind))
            }
        }

        // The island bodies delegate: everything up to the closing tag is
        // handed to the embedded highlighter, offset back into this line.
        func lexIsland(_ closer: String, with highlighter: any SyntaxHighlighting) {
            let remainder = String(characters[index...])
            let closerRange = remainder.lowercased().range(of: closer)
            let bodyLength: Int

            if let closerRange {
                bodyLength = remainder.distance(from: remainder.startIndex, to: closerRange.lowerBound)
            } else {
                bodyLength = characters.count - index
            }

            if bodyLength > 0 {
                let body = String(characters[index..<(index + bodyLength)])
                var subState = HighlightState(rawValue: sub)

                for span in highlighter.highlight(line: body, state: &subState) {
                    spans.append(HighlightSpan(start: index + span.start, length: span.length, kind: span.kind))
                }

                sub = subState.rawValue
                index += bodyLength
            }

            if closerRange != nil {
                // The `</script`/`</style` itself lexes as an ordinary tag.
                mode = Self.modeTag
                island = Self.islandNone
                sub = 0
                let start = index
                index += closer.count
                emit(from: start, kind: .tag)
            }
        }

        while index < characters.count {
            switch mode {
            case Self.modeComment:
                let start = index

                while index < characters.count {
                    if characters[index] == "-", index + 2 < characters.count,
                       characters[index + 1] == "-", characters[index + 2] == ">" {
                        index += 3
                        mode = Self.modeText
                        break
                    }

                    index += 1
                }

                emit(from: start, kind: .comment)

            case Self.modeDoctype:
                let start = index

                while index < characters.count, characters[index] != ">" {
                    index += 1
                }

                if index < characters.count {
                    index += 1   // the `>`
                    mode = Self.modeText
                }

                emit(from: start, kind: .doctype)

            case Self.modeScript:
                lexIsland("</script", with: JavaScriptHighlighter())

            case Self.modeStyle:
                lexIsland("</style", with: CSSHighlighter())

            case Self.modeTag:
                lexInsideTag(characters, &index, &mode, &island, &quote, &spans)

            default:   // text
                lexText(characters, &index, &mode, &island, &spans)
            }
        }

        state = HighlightState(rawValue: Self.packed(mode: mode, island: island, quote: quote, sub: sub))
        return spans
    }

    // MARK: - Text between tags

    private func lexText(
        _ characters: [Character],
        _ index: inout Int,
        _ mode: inout Int,
        _ island: inout Int,
        _ spans: inout [HighlightSpan]
    ) {
        let character = characters[index]

        if character == "<" {
            // Comment, doctype, or tag?
            if matches(characters, at: index, "<!--") {
                mode = Self.modeComment
                return   // the comment consumer emits from here, `<!--` included
            }

            if index + 1 < characters.count, characters[index + 1] == "!" {
                mode = Self.modeDoctype
                return   // ditto for `<!doctype …>`
            }

            let nameStart = index + (index + 1 < characters.count && characters[index + 1] == "/" ? 2 : 1)

            guard nameStart < characters.count, characters[nameStart].isLetter else {
                index += 1   // a bare `<` is just text
                return
            }

            // `<`, optional `/`, and the element name lex as one tag span.
            var nameEnd = nameStart

            while nameEnd < characters.count,
                  characters[nameEnd].isLetter || characters[nameEnd].isNumber || characters[nameEnd] == "-" {
                nameEnd += 1
            }

            let name = String(characters[nameStart..<nameEnd]).lowercased()
            let isClosing = characters[index + 1] == "/"

            spans.append(HighlightSpan(start: index, length: nameEnd - index, kind: .tag))
            index = nameEnd
            mode = Self.modeTag

            // An OPENING script/style tag leads into its island once the
            // tag's `>` arrives (attributes may intervene, and the tag may
            // even span lines).
            if !isClosing, name == "script" {
                island = Self.islandScript
            } else if !isClosing, name == "style" {
                island = Self.islandStyle
            } else {
                island = Self.islandNone
            }

            return
        }

        if character == "&" {
            // An entity: `&` through `;`, bounded so text full of stray
            // ampersands does not flicker.
            var end = index + 1
            var sawSemicolon = false

            while end < characters.count, end - index <= 10 {
                if characters[end] == ";" {
                    sawSemicolon = true
                    end += 1
                    break
                }

                guard characters[end].isLetter || characters[end].isNumber || characters[end] == "#" else {
                    break
                }

                end += 1
            }

            if sawSemicolon {
                spans.append(HighlightSpan(start: index, length: end - index, kind: .entity))
                index = end
                return
            }
        }

        index += 1   // ordinary text
    }

    // MARK: - Inside a tag

    private func lexInsideTag(
        _ characters: [Character],
        _ index: inout Int,
        _ mode: inout Int,
        _ island: inout Int,
        _ quote: inout Int,
        _ spans: inout [HighlightSpan]
    ) {
        func emit(from start: Int, kind: HighlightKind) {
            if index > start {
                spans.append(HighlightSpan(start: start, length: index - start, kind: kind))
            }
        }

        // An attribute value's quote continuing from the previous line.
        if quote != 0 {
            let closer: Character = quote == 1 ? "\"" : "'"
            let start = index

            while index < characters.count, characters[index] != closer {
                index += 1
            }

            if index < characters.count {
                index += 1
                quote = 0
            }

            emit(from: start, kind: .attributeValue)
            return
        }

        guard index < characters.count else {
            return
        }

        let character = characters[index]

        if character == ">" {
            spans.append(HighlightSpan(start: index, length: 1, kind: .tag))
            index += 1

            // The tag closed: enter a pending island (a self-closed
            // `<script/>` has no body — `/` cancelled it below).
            switch island {
            case Self.islandScript:
                mode = Self.modeScript

            case Self.islandStyle:
                mode = Self.modeStyle

            default:
                mode = Self.modeText
            }

            island = Self.islandNone
            return
        }

        if character == "/" {
            island = Self.islandNone   // self-closing: no island body
            spans.append(HighlightSpan(start: index, length: 1, kind: .tag))
            index += 1
            return
        }

        if character == "\"" || character == "'" {
            let start = index
            index += 1

            while index < characters.count, characters[index] != character {
                index += 1
            }

            if index < characters.count {
                index += 1
            } else {
                quote = character == "\"" ? 1 : 2   // continues next line
            }

            emit(from: start, kind: .attributeValue)
            return
        }

        if character.isLetter || character == "-" || character == ":" {
            let start = index

            while index < characters.count,
                  characters[index].isLetter || characters[index].isNumber
                    || characters[index] == "-" || characters[index] == ":" || characters[index] == "_" {
                index += 1
            }

            emit(from: start, kind: .attributeName)
            return
        }

        if character == "=" {
            // An unquoted value follows: `width=320`.
            index += 1
            var lookahead = index

            while lookahead < characters.count, characters[lookahead] == " " {
                lookahead += 1
            }

            guard lookahead < characters.count,
                  characters[lookahead] != "\"", characters[lookahead] != "'",
                  characters[lookahead] != ">", characters[lookahead] != " " else {
                return
            }

            index = lookahead
            let start = index

            while index < characters.count,
                  characters[index] != " ", characters[index] != ">", characters[index] != "/" {
                index += 1
            }

            emit(from: start, kind: .attributeValue)
            return
        }

        index += 1   // whitespace and anything unexpected
    }

    private func matches(_ characters: [Character], at index: Int, _ needle: String) -> Bool {
        let pattern = Array(needle)

        guard index + pattern.count <= characters.count else {
            return false
        }

        for (offset, expected) in pattern.enumerated() where characters[index + offset] != expected {
            return false
        }

        return true
    }
}
