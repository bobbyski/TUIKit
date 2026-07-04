/// Lays out children in rows and columns with spans.
///
/// Columns are declared up front; rows grow automatically as children are
/// placed. Each track (column or row) sizes one of three ways:
///
/// ```text
///   .fixed(n)     exactly n cells
///   .fitContent   the largest natural size of its single-span children
///   .flexible(w)  shares leftover space proportionally to weight w
/// ```
///
/// Children are placed explicitly with `place(_:column:row:columnSpan:rowSpan:)`
/// and fill their spanned cell area. The grid owns its children's frames;
/// child `anchors` are ignored.
@MainActor
public final class GridView: TUIView {
    /// Sizing behavior for one column or row.
    public enum Track: Hashable, Sendable {
        /// Exactly this many cells.
        case fixed(Int)

        /// Shares leftover space proportionally to its weight.
        case flexible(Int = 1)

        /// Sized to the largest natural size of its single-span children.
        case fitContent
    }

    // One placed child.
    private struct Placement {
        let view: TUIView
        let column: Int
        let row: Int
        let columnSpan: Int
        let rowSpan: Int
    }

    /// Column tracks, leading to trailing.
    public var columns: [Track] {
        didSet {
            setNeedsLayout()
        }
    }

    /// Row tracks, top to bottom. Grows automatically when placements need
    /// more rows; added rows are `.fitContent`.
    public private(set) var rows: [Track] = []

    /// Cells between adjacent columns.
    public var columnSpacing: Int {
        didSet {
            if columnSpacing != oldValue {
                setNeedsLayout()
            }
        }
    }

    /// Cells between adjacent rows.
    public var rowSpacing: Int {
        didSet {
            if rowSpacing != oldValue {
                setNeedsLayout()
            }
        }
    }

    /// Padding inside the grid's bounds.
    public var insets: EdgeInsets {
        didSet {
            if insets != oldValue {
                setNeedsLayout()
            }
        }
    }

    private var placements: [Placement] = []

    /// Creates a grid.
    ///
    /// - Parameters:
    ///   - columns: Column tracks, leading to trailing.
    ///   - frame: Position and size in the parent's coordinate space.
    ///   - columnSpacing: Cells between adjacent columns.
    ///   - rowSpacing: Cells between adjacent rows.
    ///   - insets: Padding inside the grid's bounds.
    public init(
        columns: [Track],
        frame: Rect = .zero,
        columnSpacing: Int = 0,
        rowSpacing: Int = 0,
        insets: EdgeInsets = .zero
    ) {
        self.columns = columns
        self.columnSpacing = columnSpacing
        self.rowSpacing = rowSpacing
        self.insets = insets
        super.init(frame: frame)
    }

    /// Overrides the sizing of one row.
    ///
    /// - Parameters:
    ///   - row: Row index; the row list grows to include it.
    ///   - track: Sizing behavior for the row.
    public func setRow(_ row: Int, _ track: Track) {
        growRows(through: row)
        rows[row] = track
        setNeedsLayout()
    }

    /// Places a child in the grid.
    ///
    /// - Parameters:
    ///   - view: Child to add and place.
    ///   - column: Leading column index.
    ///   - row: Top row index; rows grow as needed.
    ///   - columnSpan: Number of columns covered.
    ///   - rowSpan: Number of rows covered.
    public func place(
        _ view: TUIView,
        column: Int,
        row: Int,
        columnSpan: Int = 1,
        rowSpan: Int = 1
    ) {
        addSubview(view)
        growRows(through: row + rowSpan - 1)
        placements.append(
            Placement(view: view, column: column, row: row, columnSpan: columnSpan, rowSpan: rowSpan)
        )
        setNeedsLayout()
    }

    /// Positions every placed child in its spanned cell area.
    public override func layoutSubviews() {
        // Drop placements whose views were removed from the tree.
        placements.removeAll { $0.view.superview !== self }

        let content = insets.inset(bounds)

        let columnLengths = Self.resolveTracks(
            columns,
            available: content.size.width,
            spacing: columnSpacing,
            fitLength: { index in
                self.fitLength(column: index)
            }
        )

        let rowLengths = Self.resolveTracks(
            rows,
            available: content.size.height,
            spacing: rowSpacing,
            fitLength: { index in
                self.fitLength(row: index)
            }
        )

        let columnStarts = Self.trackStarts(columnLengths, from: content.minX, spacing: columnSpacing)
        let rowStarts = Self.trackStarts(rowLengths, from: content.minY, spacing: rowSpacing)

        for placement in placements {
            guard placement.column < columnLengths.count, placement.row < rowLengths.count else {
                continue
            }

            let lastColumn = min(placement.column + placement.columnSpan, columnLengths.count) - 1
            let lastRow = min(placement.row + placement.rowSpan, rowLengths.count) - 1

            let x = columnStarts[placement.column]
            let y = rowStarts[placement.row]
            let width = (columnStarts[lastColumn] + columnLengths[lastColumn]) - x
            let height = (rowStarts[lastRow] + rowLengths[lastRow]) - y

            placement.view.frame = Rect(x: x, y: y, width: width, height: height)
        }
    }

    // MARK: - Track Resolution

    // The natural width of a column: its widest single-span child.
    private func fitLength(column index: Int) -> Int {
        placements
            .filter { $0.column == index && $0.columnSpan == 1 }
            .compactMap { $0.view.intrinsicContentSize?.width }
            .max() ?? 0
    }

    // The natural height of a row: its tallest single-span child.
    private func fitLength(row index: Int) -> Int {
        placements
            .filter { $0.row == index && $0.rowSpan == 1 }
            .compactMap { $0.view.intrinsicContentSize?.height }
            .max() ?? 0
    }

    private func growRows(through index: Int) {
        while rows.count <= index {
            rows.append(.fitContent)
        }
    }

    // Resolves track lengths: fixed and fit first, then flexibles share the
    // leftover by weight (earliest tracks absorb rounding remainders).
    private static func resolveTracks(
        _ tracks: [Track],
        available: Int,
        spacing: Int,
        fitLength: (Int) -> Int
    ) -> [Int] {
        guard !tracks.isEmpty else {
            return []
        }

        let spacingTotal = spacing * (tracks.count - 1)
        var lengths = [Int](repeating: 0, count: tracks.count)
        var weights = [Int](repeating: 0, count: tracks.count)
        var reserved = 0
        var totalWeight = 0

        for (index, track) in tracks.enumerated() {
            switch track {
            case .fixed(let length):
                lengths[index] = max(0, length)
                reserved += lengths[index]

            case .fitContent:
                lengths[index] = fitLength(index)
                reserved += lengths[index]

            case .flexible(let weight):
                weights[index] = max(1, weight)
                totalWeight += weights[index]
            }
        }

        guard totalWeight > 0 else {
            return lengths
        }

        let leftover = max(0, available - spacingTotal - reserved)
        var distributed = 0

        for index in tracks.indices where weights[index] > 0 {
            lengths[index] = leftover * weights[index] / totalWeight
            distributed += lengths[index]
        }

        // Hand rounding remainders to the earliest flexible tracks.
        var remainder = leftover - distributed
        for index in tracks.indices where weights[index] > 0 && remainder > 0 {
            lengths[index] += 1
            remainder -= 1
        }

        return lengths
    }

    // Cumulative start positions for resolved tracks.
    private static func trackStarts(_ lengths: [Int], from start: Int, spacing: Int) -> [Int] {
        var starts: [Int] = []
        var offset = start

        for length in lengths {
            starts.append(offset)
            offset += length + spacing
        }

        return starts
    }
}
