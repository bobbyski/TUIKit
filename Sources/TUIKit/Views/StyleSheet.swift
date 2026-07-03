/// A logical style sheet: CSS-shaped selectors over the semantic theme.
///
/// The stylesheet layer stays *logical* by construction. Selectors address
/// what a view **is** (type, `#identifier`, `.styleClasses`, `:focused`),
/// never where it sits on screen; properties write into the semantic
/// `Theme` slots and text attributes, never layout — geometry remains the
/// business of anchors, stacks, and grids.
///
/// ```swift
/// window.styleSheet = StyleSheet("""
///     Button          { color: brightWhite; bold: true; }
///     .warning        { color: brightYellow; }
///     #save           { accent: green; }
///     ListView.sidebar { selection-background: #4477aa; }
///     TextField:focused { underline: true; }
///     Panel Label     { color: cyan; }          /* descendant */
/// """)
/// ```
///
/// **Selectors.** A compound is `Type`, `#id`, `.class` (repeatable), and
/// `:focused` in any combination; whitespace between compounds means
/// descendant. Comma separates alternatives. Type names are the Swift
/// class names (`Button`, `ListView`, `FloatingWindow`).
///
/// **Properties** (all optional-valued; unknown ones are ignored):
///
/// | Property                                     | Writes to              |
/// |----------------------------------------------|------------------------|
/// | `color`, `background`                        | `theme.base`           |
/// | `bold`, `dim`, `italic`, `underline`         | `theme.base.flags`     |
/// | `accent`                                     | `theme.accent`         |
/// | `selection-color`, `selection-background`    | `theme.selection`      |
/// | `header-color`, `border-color`, `placeholder-color` | those slots' foregrounds |
///
/// Color values: the 16 ANSI names (`red`, `brightBlue`, …), `#rrggbb`,
/// `palette(n)`, or `standard`. Flag values: `true` / `false`.
///
/// **Cascade.** Assign sheets to any view; outer sheets apply first, then
/// inner ones, then specificity (`#id` = 100, `.class`/`:focused` = 10,
/// type = 1, summed over the chain), then source order. The resolved
/// result *is* the view's `effectiveTheme`, so themed controls need no
/// stylesheet awareness of their own.
///
/// Parsing is tolerant: malformed rules and unknown properties are
/// skipped, never fatal.
public struct StyleSheet: Hashable, Sendable {
    /// Parsed rules in source order.
    public private(set) var rules: [StyleRule]

    /// Parses a stylesheet from source text.
    ///
    /// - Parameter source: Rules in the `selector { property: value; }`
    ///   form; `/* comments */` allowed.
    public init(_ source: String) {
        self.rules = Self.parse(source)
    }

    /// Applies every rule matching a view onto a theme, honoring the
    /// cascade (specificity, then source order).
    ///
    /// - Parameters:
    ///   - view: View being resolved.
    ///   - theme: Theme the declarations write into.
    @MainActor
    func apply(to view: View, theme: inout Theme) {
        var matched: [(specificity: Int, order: Int, rule: StyleRule)] = []

        for (order, rule) in rules.enumerated() {
            let best = rule.selectors
                .filter { $0.matches(view) }
                .map(\.specificity)
                .max()

            if let best {
                matched.append((best, order, rule))
            }
        }

        matched.sort {
            ($0.specificity, $0.order) < ($1.specificity, $1.order)
        }

        for entry in matched {
            entry.rule.apply(to: &theme)
        }
    }

    // MARK: - Parsing

    private static func parse(_ source: String) -> [StyleRule] {
        // Strip comments.
        var text = ""
        var rest = Substring(source)

        while let start = rest.range(of: "/*") {
            text += rest[..<start.lowerBound]

            if let end = rest.range(of: "*/", range: start.upperBound..<rest.endIndex) {
                rest = rest[end.upperBound...]
            } else {
                rest = ""
            }
        }

        text += rest

        var rules: [StyleRule] = []
        var remaining = Substring(text)

        while let open = remaining.firstIndex(of: "{") {
            let selectorText = String(remaining[..<open])

            guard let close = remaining[open...].firstIndex(of: "}") else {
                break
            }

            let body = String(remaining[remaining.index(after: open)..<close])
            remaining = remaining[remaining.index(after: close)...]

            let selectors = selectorText
                .split(separator: ",")
                .compactMap { StyleSelector(parsing: String($0)) }

            let declarations = Self.parseDeclarations(body)

            if !selectors.isEmpty, !declarations.isEmpty {
                rules.append(StyleRule(selectors: selectors, declarations: declarations))
            }
        }

        return rules
    }

    private static func parseDeclarations(_ body: String) -> [StyleDeclaration] {
        body.split(separator: ";").compactMap { entry in
            let parts = entry.split(separator: ":", maxSplits: 1)

            guard parts.count == 2 else {
                return nil
            }

            let name = parts[0].trimmed.lowercased()
            let value = parts[1].trimmed

            guard let property = StyleDeclaration.Property(rawValue: name) else {
                return nil
            }

            switch property.kind {
            case .color:
                guard let color = TerminalColor(styleValue: value) else {
                    return nil
                }

                return StyleDeclaration(property: property, value: .color(color))

            case .flag:
                guard let flag = Bool(value.lowercased()) else {
                    return nil
                }

                return StyleDeclaration(property: property, value: .flag(flag))

            case .border:
                guard let style = BorderStyle(rawValue: value.lowercased()) else {
                    return nil
                }

                return StyleDeclaration(property: property, value: .border(style))
            }
        }
    }
}

/// One stylesheet rule: selectors and the declarations they apply.
public struct StyleRule: Hashable, Sendable {
    /// Alternative selectors (comma-separated in source).
    public var selectors: [StyleSelector]

    /// Property assignments in source order.
    public var declarations: [StyleDeclaration]

    // Writes the declarations into a theme.
    func apply(to theme: inout Theme) {
        for declaration in declarations {
            declaration.apply(to: &theme)
        }
    }
}

/// One property assignment.
public struct StyleDeclaration: Hashable, Sendable {
    /// The logical properties the stylesheet layer understands.
    public enum Property: String, Hashable, Sendable {
        case color
        case background
        case accent
        case selectionColor = "selection-color"
        case selectionBackground = "selection-background"
        case headerColor = "header-color"
        case headerBackground = "header-background"
        case borderColor = "border-color"
        case borderBackground = "border-background"
        case placeholderColor = "placeholder-color"
        case placeholderBackground = "placeholder-background"
        case scrollbarColor = "scrollbar-color"
        case scrollbarBackground = "scrollbar-background"
        case border
        case bold
        case dim
        case italic
        case underline

        /// What value form the property takes.
        var kind: Kind {
            switch self {
            case .bold, .dim, .italic, .underline:
                return .flag

            case .border:
                return .border

            default:
                return .color
            }
        }

        enum Kind {
            case color
            case flag
            case border
        }
    }

    /// A property's value.
    public enum Value: Hashable, Sendable {
        case color(TerminalColor)
        case flag(Bool)
        case border(BorderStyle)
    }

    /// Property being assigned.
    public var property: Property

    /// Assigned value.
    public var value: Value

    // Writes one assignment into a theme.
    func apply(to theme: inout Theme) {
        switch (property, value) {
        case (.color, .color(let color)):
            theme.base.foreground = color

        case (.background, .color(let color)):
            theme.base.background = color

        case (.accent, .color(let color)):
            theme.accent = color

        case (.selectionColor, .color(let color)):
            theme.selection.foreground = color

        case (.selectionBackground, .color(let color)):
            theme.selection.background = color

        case (.headerColor, .color(let color)):
            theme.header.foreground = color

        case (.headerBackground, .color(let color)):
            theme.header.background = color

        case (.borderColor, .color(let color)):
            theme.border.foreground = color

        case (.borderBackground, .color(let color)):
            theme.border.background = color

        case (.placeholderColor, .color(let color)):
            theme.placeholder.foreground = color

        case (.placeholderBackground, .color(let color)):
            theme.placeholder.background = color

        case (.scrollbarColor, .color(let color)):
            theme.scrollbar.foreground = color

        case (.scrollbarBackground, .color(let color)):
            theme.scrollbar.background = color

        case (.border, .border(let style)):
            theme.borderStyle = style

        case (.bold, .flag(let on)):
            Self.setFlag(.bold, to: on, in: &theme)

        case (.dim, .flag(let on)):
            Self.setFlag(.dim, to: on, in: &theme)

        case (.italic, .flag(let on)):
            Self.setFlag(.italic, to: on, in: &theme)

        case (.underline, .flag(let on)):
            Self.setFlag(.underline, to: on, in: &theme)

        default:
            break
        }
    }

    private static func setFlag(_ flag: CellFlags, to on: Bool, in theme: inout Theme) {
        if on {
            theme.base.flags.insert(flag)
        } else {
            theme.base.flags.remove(flag)
        }
    }
}

/// A selector: a descendant chain of compounds.
public struct StyleSelector: Hashable, Sendable {
    /// One `Type#id.class:focused` unit.
    public struct Compound: Hashable, Sendable {
        /// Swift class name to match, when present.
        public var type: String?

        /// `#identifier` to match, when present.
        public var id: String?

        /// `.class` names that must all be present.
        public var classes: Set<String> = []

        /// Whether the view must be first responder.
        public var focused = false

        @MainActor
        func matches(_ view: View) -> Bool {
            if let type, String(describing: Swift.type(of: view)) != type {
                return false
            }

            if let id, view.identifier != id {
                return false
            }

            if !classes.isSubset(of: view.styleClasses) {
                return false
            }

            if focused, !view.isFirstResponder {
                return false
            }

            return true
        }

        var specificity: Int {
            (id != nil ? 100 : 0)
                + (classes.count + (focused ? 1 : 0)) * 10
                + (type != nil ? 1 : 0)
        }
    }

    /// Compounds from outermost ancestor to the subject view.
    public var chain: [Compound]

    /// Parses one selector (no commas), or `nil` when empty/invalid.
    ///
    /// - Parameter text: Selector text, like `"Panel ListView.sidebar"`.
    public init?(parsing text: String) {
        let compounds = text
            .split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
            .compactMap { Self.parseCompound(String($0)) }

        guard !compounds.isEmpty else {
            return nil
        }

        self.chain = compounds
    }

    /// Selector weight for cascade ordering.
    public var specificity: Int {
        chain.reduce(0) { $0 + $1.specificity }
    }

    /// Whether the selector matches a view (walking ancestors for
    /// descendant compounds).
    @MainActor
    public func matches(_ view: View) -> Bool {
        var compounds = chain

        guard let last = compounds.popLast(), last.matches(view) else {
            return false
        }

        // Remaining compounds must match ancestors, innermost outward.
        var ancestor = view.superview

        while let compound = compounds.last {
            while let candidate = ancestor, !compound.matches(candidate) {
                ancestor = candidate.superview
            }

            guard ancestor != nil else {
                return false
            }

            ancestor = ancestor?.superview
            compounds.removeLast()
        }

        return true
    }

    // Parses "Type#id.a.b:focused".
    private static func parseCompound(_ text: String) -> Compound? {
        var compound = Compound()
        var index = text.startIndex

        // Leading type name.
        var type = ""

        while index < text.endIndex, text[index] != "." && text[index] != "#" && text[index] != ":" {
            type.append(text[index])
            index = text.index(after: index)
        }

        if !type.isEmpty {
            compound.type = type
        }

        // Marker-led segments.
        while index < text.endIndex {
            let marker = text[index]
            index = text.index(after: index)
            var name = ""

            while index < text.endIndex, text[index] != "." && text[index] != "#" && text[index] != ":" {
                name.append(text[index])
                index = text.index(after: index)
            }

            switch marker {
            case ".":
                guard !name.isEmpty else {
                    return nil
                }

                compound.classes.insert(name)

            case "#":
                guard !name.isEmpty else {
                    return nil
                }

                compound.id = name

            case ":":
                guard name == "focused" else {
                    return nil
                }

                compound.focused = true

            default:
                return nil
            }
        }

        guard compound.type != nil || compound.id != nil || !compound.classes.isEmpty || compound.focused else {
            return nil
        }

        return compound
    }
}

// MARK: - Value parsing helpers

extension TerminalColor {
    /// Parses a stylesheet color value: an ANSI name, `#rrggbb`,
    /// `palette(n)`, or `standard`.
    init?(styleValue: String) {
        let text = styleValue.trimmed

        if text.lowercased() == "standard" {
            self = .standard
            return
        }

        if text.hasPrefix("#"), text.count == 7,
           let value = UInt32(text.dropFirst(), radix: 16) {
            self = .rgb(
                red: UInt8((value >> 16) & 0xff),
                green: UInt8((value >> 8) & 0xff),
                blue: UInt8(value & 0xff)
            )
            return
        }

        if text.lowercased().hasPrefix("palette("), text.hasSuffix(")"),
           let index = UInt8(text.dropFirst(8).dropLast()) {
            self = .palette(index)
            return
        }

        let lowered = text.lowercased()

        if let named = NamedColor.allCases.first(where: { $0.rawValue.lowercased() == lowered }) {
            self = .named(named)
            return
        }

        return nil
    }
}

extension Substring {
    var trimmed: String {
        var slice = self

        while let first = slice.first, first == " " || first == "\n" || first == "\t" {
            slice = slice.dropFirst()
        }

        while let last = slice.last, last == " " || last == "\n" || last == "\t" {
            slice = slice.dropLast()
        }

        return String(slice)
    }
}

extension String {
    var trimmed: String {
        Substring(self).trimmed
    }
}
