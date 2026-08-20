// R8a — the CSS highlighting lexer, kept lean: it exists first as the
// `<style>` island inside ``HTMLHighlighter``, and secondarily as
// `language = "css"` on its own.

/// A lean line-at-a-time CSS lexer for ``SyntaxTextView``.
///
/// State packing: bit 0 is "inside a block comment"; bits 1–8 are the brace
/// depth (inside a rule block, identifiers before `:` are property names).
public struct CSSHighlighter: SyntaxHighlighting {
    /// Creates a CSS highlighter.
    public init() {}

    static func packed(inComment: Bool, braces: Int) -> Int {
        (inComment ? 1 : 0) | (min(braces, 255) << 1)
    }

    static func unpack(_ raw: Int) -> (inComment: Bool, braces: Int) {
        (raw & 1 == 1, (raw >> 1) & 0xFF)
    }

    /// Lexes one line. See ``SyntaxHighlighting/highlight(line:state:)``.
    public func highlight(line: String, state: inout HighlightState) -> [HighlightSpan] {
        let characters = Array(line)
        var (inComment, braces) = Self.unpack(state.rawValue)
        var spans: [HighlightSpan] = []
        var index = 0

        func emit(from start: Int, kind: HighlightKind) {
            if index > start, kind != .plain {
                spans.append(HighlightSpan(start: start, length: index - start, kind: kind))
            }
        }

        // Comment text until `*/` (or EOL, leaving the state open), spanning
        // from `spanStart` so an opener on this line includes its `/*`.
        func consumeComment(from spanStart: Int) {
            while index < characters.count {
                if characters[index] == "*", index + 1 < characters.count, characters[index + 1] == "/" {
                    index += 2
                    inComment = false
                    break
                }

                index += 1
            }

            emit(from: spanStart, kind: .comment)
        }

        while index < characters.count {
            if inComment {
                consumeComment(from: index)
                continue
            }

            let character = characters[index]

            if character == "/", index + 1 < characters.count, characters[index + 1] == "*" {
                inComment = true
                let start = index
                index += 2   // past the `/*`, so `/*/` does not self-close
                consumeComment(from: start)
                continue
            }

            if character == "\"" || character == "'" {
                let start = index
                index += 1

                while index < characters.count {
                    if characters[index] == "\\" {
                        index += min(2, characters.count - index)
                        continue
                    }

                    let current = characters[index]
                    index += 1

                    if current == character {
                        break
                    }
                }

                emit(from: start, kind: .string)
                continue
            }

            if character == "{" {
                braces += 1
                index += 1
                continue
            }

            if character == "}" {
                braces = max(0, braces - 1)
                index += 1
                continue
            }

            if character == "@" {
                // An at-rule (`@media`, `@import`) reads as a keyword.
                let start = index
                index += 1

                while index < characters.count, characters[index].isLetter || characters[index] == "-" {
                    index += 1
                }

                emit(from: start, kind: .keyword)
                continue
            }

            if character == "#" || character.isNumber
                || (character == "." && index + 1 < characters.count && characters[index + 1].isNumber) {
                // Hex colours and numeric values (with their units).
                let start = index
                index += 1

                while index < characters.count,
                      characters[index].isHexDigit || characters[index].isLetter
                        || characters[index] == "." || characters[index] == "%" {
                    index += 1
                }

                emit(from: start, kind: .number)
                continue
            }

            if character.isLetter || character == "-" {
                let start = index

                while index < characters.count,
                      characters[index].isLetter || characters[index].isNumber
                        || characters[index] == "-" || characters[index] == "_" {
                    index += 1
                }

                // Inside a rule block, an identifier followed by `:` is a
                // property name; everything else (selectors, values) stays
                // plain.
                var lookahead = index

                while lookahead < characters.count, characters[lookahead] == " " {
                    lookahead += 1
                }

                if braces > 0, lookahead < characters.count, characters[lookahead] == ":" {
                    emit(from: start, kind: .attributeName)
                }

                continue
            }

            index += 1
        }

        state = HighlightState(rawValue: Self.packed(inComment: inComment, braces: braces))
        return spans
    }
}
