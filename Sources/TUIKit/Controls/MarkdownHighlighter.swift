/// The Markdown highlighting lexer — what `MarkdownView` shows in its edit
/// mode, and `language = "markdown"` on its own.
///
/// Line-oriented, like Markdown itself: `#` headings, `>` quotes, list
/// bullets, fenced code (state carries across lines), and inline `code`,
/// **strong** / *emphasis*, and [links](url). Good enough to see the
/// structure while typing over SSH; not a CommonMark parser.
public struct MarkdownHighlighter: SyntaxHighlighting {
    /// Creates the lexer.
    public init() {}

    public func highlight(line: String, state: inout HighlightState) -> [HighlightSpan] {
        let characters = Array(line)
        var spans: [HighlightSpan] = []
        let trimmed = line.drop { $0 == " " }

        // Fenced code: the whole line is a string until the closing fence.
        if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
            state = HighlightState(rawValue: state.rawValue == 1 ? 0 : 1)
            return [HighlightSpan(start: 0, length: characters.count, kind: .comment)]
        }

        if state.rawValue == 1 {
            return characters.isEmpty ? [] : [HighlightSpan(start: 0, length: characters.count, kind: .string)]
        }

        // Headings: the whole line is a keyword.
        if trimmed.hasPrefix("#") {
            return [HighlightSpan(start: 0, length: characters.count, kind: .keyword)]
        }

        var index = 0

        // Block prefixes: quote marker, list bullets, ordered numbers.
        while index < characters.count, characters[index] == " " {
            index += 1
        }

        if index < characters.count, characters[index] == ">" {
            spans.append(HighlightSpan(start: index, length: 1, kind: .doctype))
            index += 1
        } else if index < characters.count, "-*+".contains(characters[index]),
                  index + 1 < characters.count, characters[index + 1] == " " {
            spans.append(HighlightSpan(start: index, length: 1, kind: .tag))
            index += 2
        } else {
            var digits = index
            while digits < characters.count, characters[digits].isNumber {
                digits += 1
            }
            if digits > index, digits < characters.count, characters[digits] == ".",
               digits + 1 < characters.count, characters[digits + 1] == " " {
                spans.append(HighlightSpan(start: index, length: digits - index + 1, kind: .number))
                index = digits + 2
            }
        }

        // Inline: `code`, **strong**, *emphasis*, [text](url).
        while index < characters.count {
            let character = characters[index]

            if character == "`" {
                if let close = characters[(index + 1)...].firstIndex(of: "`") {
                    spans.append(HighlightSpan(start: index, length: close - index + 1, kind: .string))
                    index = close + 1
                    continue
                }
            }

            if character == "*" || character == "_" {
                let doubled = index + 1 < characters.count && characters[index + 1] == character
                let marker = doubled ? 2 : 1
                let search = index + marker

                if search < characters.count,
                   let close = Self.find(String(repeating: character, count: marker), in: characters, from: search) {
                    spans.append(HighlightSpan(start: index, length: close + marker - index, kind: doubled ? .attributeName : .attributeValue))
                    index = close + marker
                    continue
                }
            }

            if character == "[" {
                if let closeBracket = characters[(index + 1)...].firstIndex(of: "]"),
                   closeBracket + 1 < characters.count, characters[closeBracket + 1] == "(",
                   let closeParen = characters[(closeBracket + 1)...].firstIndex(of: ")") {
                    spans.append(HighlightSpan(start: index, length: closeBracket - index + 1, kind: .entity))
                    spans.append(HighlightSpan(start: closeBracket + 1, length: closeParen - closeBracket, kind: .regex))
                    index = closeParen + 1
                    continue
                }
            }

            index += 1
        }

        return spans
    }

    private static func find(_ needle: String, in characters: [Character], from start: Int) -> Int? {
        let pattern = Array(needle)
        var index = start

        while index + pattern.count <= characters.count {
            if Array(characters[index..<(index + pattern.count)]) == pattern {
                return index
            }

            index += 1
        }

        return nil
    }
}
