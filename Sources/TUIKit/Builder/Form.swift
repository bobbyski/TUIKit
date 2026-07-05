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

/// Collects `Field`s inside a `Form`.
@MainActor
@resultBuilder
public enum FormBuilder {
    /// Collects a single field.
    public static func buildExpression(_ field: Field) -> [Field] { [field] }
    /// Flattens the block's parts.
    public static func buildBlock(_ parts: [Field]...) -> [Field] { parts.flatMap { $0 } }
    /// Keeps the `if` branch's parts (or none).
    public static func buildOptional(_ part: [Field]?) -> [Field] { part ?? [] }
    /// Keeps the `if` branch's parts.
    public static func buildEither(first: [Field]) -> [Field] { first }
    /// Keeps the `else` branch's parts.
    public static func buildEither(second: [Field]) -> [Field] { second }
    /// Flattens a `for` loop's parts.
    public static func buildArray(_ parts: [[Field]]) -> [Field] { parts.flatMap { $0 } }
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
    public init(labelWidth: Int? = nil, spacing: Int = 1, @FormBuilder _ fields: () -> [Field]) {
        let rows = fields()
        let labelColumn = labelWidth ?? (rows.map { $0.title.count + 1 }.max() ?? 0)

        let controls = rows.map { $0.control.makeView() }
        let rowHeights = controls.map { $0.intrinsicContentSize?.height ?? 1 }
        let widestControl = controls.map { $0.intrinsicContentSize?.width ?? 12 }.max() ?? 12

        naturalHeight = rowHeights.reduce(0, +) + spacing * max(0, rows.count - 1)
        naturalWidth = labelColumn + 1 + widestControl

        let grid = GridView(
            columns: [.fixed(labelColumn), .flexible(1)],
            columnSpacing: 1,
            rowSpacing: spacing
        )

        super.init(frame: .zero)

        for (index, field) in rows.enumerated() {
            let label = Label("\(field.title):")
            label.style.flags.insert(.bold)
            label.alignment = .trailing

            grid.place(label, column: 0, row: index)
            grid.place(controls[index], column: 1, row: index)
            grid.setRow(index, .fixed(rowHeights[index]))
        }

        grid.anchors = .fill()
        addSubview(grid)
    }

    /// The form's natural size: the label column, the widest control, and the
    /// stacked row heights — so a parent stack sizes it correctly.
    public override var intrinsicContentSize: Size? {
        Size(width: naturalWidth, height: naturalHeight)
    }
}
