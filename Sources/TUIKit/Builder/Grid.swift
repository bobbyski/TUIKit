/// One cell in a `GridRow`: a component and how many columns/rows it spans.
@MainActor
public struct GridCell {
    let component: any Component
    var columnSpan: Int = 1
    var rowSpan: Int = 1
}

public extension Component {
    /// Makes this component span multiple grid columns and/or rows.
    ///
    /// ```swift
    /// GridRow { Label("Full-width header").gridSpan(columns: 3) }
    /// ```
    ///
    /// - Parameters:
    ///   - columns: Columns to span.
    ///   - rows: Rows to span.
    /// - Returns: A spanning grid cell.
    func gridSpan(columns: Int = 1, rows: Int = 1) -> GridCell {
        GridCell(component: self, columnSpan: max(1, columns), rowSpan: max(1, rows))
    }
}

/// Collects the cells of one `GridRow`. A bare component becomes a
/// single-cell; `.gridSpan(...)` supplies a spanning cell.
@MainActor
@resultBuilder
public enum GridRowBuilder {
    /// Wraps a bare component in a single-span cell.
    public static func buildExpression(_ component: any Component) -> [GridCell] { [GridCell(component: component)] }
    /// Collects an explicit (spanning) cell.
    public static func buildExpression(_ cell: GridCell) -> [GridCell] { [cell] }
    /// Flattens the block's parts.
    public static func buildBlock(_ parts: [GridCell]...) -> [GridCell] { parts.flatMap { $0 } }
    /// Keeps the `if` branch's parts (or none).
    public static func buildOptional(_ part: [GridCell]?) -> [GridCell] { part ?? [] }
    /// Keeps the `if` branch's parts.
    public static func buildEither(first: [GridCell]) -> [GridCell] { first }
    /// Keeps the `else` branch's parts.
    public static func buildEither(second: [GridCell]) -> [GridCell] { second }
    /// Flattens a `for` loop's parts.
    public static func buildArray(_ parts: [[GridCell]]) -> [GridCell] { parts.flatMap { $0 } }
}

/// A row of cells in a `Grid`. Cells fill columns left to right; spans advance
/// the column cursor accordingly.
@MainActor
public struct GridRow {
    let cells: [GridCell]

    /// Creates a grid row.
    ///
    /// - Parameter content: The row's cells.
    public init(@GridRowBuilder _ content: () -> [GridCell]) {
        self.cells = content()
    }
}

/// Collects the `GridRow`s of a `Grid`.
@MainActor
@resultBuilder
public enum GridBuilder {
    /// Collects a single row.
    public static func buildExpression(_ row: GridRow) -> [GridRow] { [row] }
    /// Flattens the block's parts.
    public static func buildBlock(_ parts: [GridRow]...) -> [GridRow] { parts.flatMap { $0 } }
    /// Keeps the `if` branch's parts (or none).
    public static func buildOptional(_ part: [GridRow]?) -> [GridRow] { part ?? [] }
    /// Keeps the `if` branch's parts.
    public static func buildEither(first: [GridRow]) -> [GridRow] { first }
    /// Keeps the `else` branch's parts.
    public static func buildEither(second: [GridRow]) -> [GridRow] { second }
    /// Flattens a `for` loop's parts.
    public static func buildArray(_ parts: [[GridRow]]) -> [GridRow] { parts.flatMap { $0 } }
}

/// SwiftUI-familiar spelling of `GridView` for the builder.
public typealias Grid = GridView

public extension GridView {
    /// Builds a grid from `GridRow`s, placing each row's cells into the
    /// columns left to right.
    ///
    /// ```swift
    /// Grid(columns: [.fitContent, .flexible(1)], columnSpacing: 1) {
    ///     GridRow { Label("Name").bold(); TextField() }
    ///     GridRow { Label("Notes").bold(); TextField() }
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - columns: Column tracks (`.fixed`/`.fitContent`/`.flexible`).
    ///   - columnSpacing: Cells between columns.
    ///   - rowSpacing: Cells between rows.
    ///   - insets: Padding inside the grid.
    ///   - content: The rows.
    convenience init(
        columns: [Track],
        columnSpacing: Int = 0,
        rowSpacing: Int = 0,
        insets: EdgeInsets = .zero,
        @GridBuilder _ content: () -> [GridRow]
    ) {
        self.init(columns: columns, columnSpacing: columnSpacing, rowSpacing: rowSpacing, insets: insets)

        for (rowIndex, row) in content().enumerated() {
            var column = 0

            for cell in row.cells {
                place(
                    cell.component.makeView(),
                    column: column,
                    row: rowIndex,
                    columnSpan: cell.columnSpan,
                    rowSpan: cell.rowSpan
                )
                column += cell.columnSpan
            }
        }
    }
}
