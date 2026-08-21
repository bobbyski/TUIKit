/// One labeled row in a `Form`: a title and the control beside it.
///
/// ```swift
/// Field("Name") { TextField(placeholder: "your name") }
/// ```
@MainActor
public struct Field {
    let title: String
    let control: any Component

    /// Creates a field.
    ///
    /// - Parameters:
    ///   - title: The row's label (a trailing `:` is added).
    ///   - content: The control (the first component is used).
    public init(_ title: String, @NodeBuilder _ content: () -> [any Component]) {
        self.title = title
        self.control = content().first ?? Spacer()
    }
}

/// A titled group of fields inside a `Form`: a header row, then its fields.
///
/// ```swift
/// Section("Account") {
///     Field("Name")  { TextField() }
///     Field("Email") { TextField() }
/// }
/// ```
@MainActor
public struct Section {
    let title: String
    let fields: [Field]

    /// Creates a section.
    ///
    /// - Parameters:
    ///   - title: The header text.
    ///   - content: The fields under it.
    public init(_ title: String, @FormBuilder _ content: () -> [FormEntry]) {
        self.title = title
        self.fields = content().compactMap { entry in
            if case .field(let field) = entry {
                return field
            }

            return nil   // nested sections flatten to their fields' level
        }
    }
}

/// One row of a `Form`: a field, or a section header.
@MainActor
public enum FormEntry {
    /// A labelled control.
    case field(Field)

    /// A header spanning both columns.
    case header(String)
}

/// Collects `Field`s and `Section`s inside a `Form`.
@MainActor
@resultBuilder
public enum FormBuilder {
    /// Collects a single field.
    public static func buildExpression(_ field: Field) -> [FormEntry] { [.field(field)] }
    /// Collects a section: its header, then its fields.
    public static func buildExpression(_ section: Section) -> [FormEntry] {
        [.header(section.title)] + section.fields.map { .field($0) }
    }
    /// Flattens the block's parts.
    public static func buildBlock(_ parts: [FormEntry]...) -> [FormEntry] { parts.flatMap { $0 } }
    /// Keeps the `if` branch's parts (or none).
    public static func buildOptional(_ part: [FormEntry]?) -> [FormEntry] { part ?? [] }
    /// Keeps the `if` branch's parts.
    public static func buildEither(first: [FormEntry]) -> [FormEntry] { first }
    /// Keeps the `else` branch's parts.
    public static func buildEither(second: [FormEntry]) -> [FormEntry] { second }
    /// Flattens a `for` loop's parts.
    public static func buildArray(_ parts: [[FormEntry]]) -> [FormEntry] { parts.flatMap { $0 } }
}

/// A column of labeled controls whose fields all line up — the aligned form,
/// with zero layout code.
///
/// ```text
///     Name:  ┃your name            ┃
///    Email:  ┃you@host             ┃
///    Theme:   Standard ▾
/// ```
///
/// `Form` measures the label column (fit-content, right-aligned to the colon)
/// and gives the control column the rest, so every row aligns automatically.
/// This is principle #2 of `Docs/TUIBuilder.md` — you declare *what* each row
/// is, and the container decides *where* everything goes.
///
/// ```swift
/// Form {
///     Field("Name")  { TextField(placeholder: "your name") }
///     Field("Theme") { PopUpButton(items: Theme.builtIn.map(\.name)) }
/// }
/// ```
@MainActor
public final class Form: TUIView {
    private let naturalWidth: Int
    private let naturalHeight: Int

    /// Builds a form.
    ///
    /// - Parameters:
    ///   - labelWidth: Fixed width for the label column, or `nil` to size it
    ///     to the widest label.
    ///   - spacing: Blank rows between fields.
    ///   - fields: The rows.
    public init(labelWidth: Int? = nil, spacing: Int = 1, @FormBuilder _ fields: () -> [FormEntry]) {
        let entries = fields()
        let fieldRows = entries.compactMap { entry -> Field? in
            if case .field(let field) = entry { return field } else { return nil }
        }
        let labelColumn = labelWidth ?? (fieldRows.map { $0.title.count + 1 }.max() ?? 0)

        // One grid row per entry: a header spans both columns; a field is a
        // label beside its control. The label column is shared across
        // sections, so every field in the form still lines up.
        let views: [TUIView?] = entries.map { entry in
            if case .field(let field) = entry { return field.control.makeView() } else { return nil }
        }
        let rowHeights = views.map { $0?.intrinsicContentSize?.height ?? 1 }
        let widestControl = views.compactMap { $0?.intrinsicContentSize?.width }.max() ?? 12

        naturalHeight = rowHeights.reduce(0, +) + spacing * max(0, entries.count - 1)
        naturalWidth = labelColumn + 1 + widestControl

        let grid = GridView(
            columns: [.fixed(labelColumn), .flexible(1)],
            columnSpacing: 1,
            rowSpacing: spacing
        )

        super.init(frame: .zero)

        for (index, entry) in entries.enumerated() {
            switch entry {
            case .field(let field):
                let label = Label("\(field.title):")
                label.style.flags.insert(.bold)
                label.alignment = .trailing
                grid.place(label, column: 0, row: index)

                if let control = views[index] {
                    grid.place(control, column: 1, row: index)
                }

            case .header(let title):
                let header = SectionHeader(title)
                grid.place(header, column: 0, row: index, columnSpan: 2)
            }

            grid.setRow(index, .fixed(rowHeights[index]))
        }

        grid.anchors = .fill()
        addSubview(grid)
    }

    // A section header row: the title in the theme's header style, with a
    // rule filling the rest of the row.
    private final class SectionHeader: TUIView {
        let title: String

        init(_ title: String) {
            self.title = title
            super.init(frame: .zero)
        }

        override var intrinsicContentSize: Size? {
            Size(width: title.count + 2, height: 1)
        }

        override func draw(_ painter: Painter) {
            let theme = effectiveTheme
            let width = bounds.size.width
            let text = Label.truncated(title, width: max(0, width - 1))
            var style = theme.base
            style.flags.insert(.bold)
            painter.write(text, at: .zero, style: style)

            if let line = theme.dividerStyle.characters?.horizontal, width > text.count + 1 {
                painter.write(String(repeating: line, count: width - text.count - 1), at: Point(x: text.count + 1, y: 0), style: theme.border)
            }
        }
    }

    /// The form's natural size: the label column, the widest control, and the
    /// stacked row heights — so a parent stack sizes it correctly.
    public override var intrinsicContentSize: Size? {
        Size(width: naturalWidth, height: naturalHeight)
    }
}
