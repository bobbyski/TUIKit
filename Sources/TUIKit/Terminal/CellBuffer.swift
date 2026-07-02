/// Two-dimensional buffer of terminal cells.
///
/// The buffer is the rendering currency of TUIKit: views draw into buffers,
/// drivers present buffers, and tests assert on buffers (usually through
/// `textLines()`). It is a value type, so snapshots and comparisons are
/// cheap and safe to pass across concurrency domains.
///
/// All writes are clipped to the buffer bounds; drawing outside the buffer
/// is silently ignored rather than an error, matching the framework's
/// clipping contract.
public struct CellBuffer: Equatable, Sendable {
    /// Buffer extent in cells.
    public let size: Size

    /// Row-major cell storage; `storage[y * size.width + x]`.
    private var storage: [TerminalCell]

    /// Creates a buffer filled with a cell.
    ///
    /// - Parameters:
    ///   - size: Buffer extent in cells.
    ///   - fill: Cell used to fill the buffer. Defaults to blank.
    public init(size: Size, fill: TerminalCell = .blank) {
        self.size = size
        self.storage = Array(repeating: fill, count: size.cellCount)
    }

    /// Accesses the cell at a position.
    ///
    /// Reading outside the bounds returns a blank cell; writing outside the
    /// bounds is ignored.
    ///
    /// - Parameter position: Cell position.
    public subscript(position: Point) -> TerminalCell {
        get {
            guard bounds.contains(position) else {
                return .blank
            }

            return storage[position.y * size.width + position.x]
        }
        set {
            guard bounds.contains(position) else {
                return
            }

            storage[position.y * size.width + position.x] = newValue
        }
    }

    /// The buffer's bounds rectangle at origin zero.
    public var bounds: Rect {
        Rect(origin: .zero, size: size)
    }

    /// Fills a rectangle with a cell, clipped to the buffer.
    ///
    /// - Parameters:
    ///   - rect: Rectangle to fill.
    ///   - cell: Cell to fill with.
    public mutating func fill(_ rect: Rect, with cell: TerminalCell) {
        let clipped = bounds.intersection(rect)

        for y in clipped.minY..<clipped.maxY {
            for x in clipped.minX..<clipped.maxX {
                storage[y * size.width + x] = cell
            }
        }
    }

    /// Writes text starting at a position, clipped to the buffer.
    ///
    /// Text never wraps; characters past the right edge are dropped.
    ///
    /// - Parameters:
    ///   - text: Text to write.
    ///   - position: Position of the first character.
    ///   - style: Style applied to every written cell.
    public mutating func write(_ text: String, at position: Point, style: CellStyle = .default) {
        var x = position.x

        for character in text {
            self[Point(x: x, y: position.y)] = TerminalCell(character: character, style: style)
            x += 1
        }
    }

    /// Projects one row as plain text, ignoring styles.
    ///
    /// - Parameter row: Row index.
    /// - Returns: The row's characters, or an empty string out of bounds.
    public func text(row: Int) -> String {
        guard row >= 0, row < size.height else {
            return ""
        }

        let start = row * size.width
        return String(storage[start..<(start + size.width)].map(\.character))
    }

    /// Projects the whole buffer as plain text lines, ignoring styles.
    ///
    /// This is the primary assertion surface for rendering tests.
    ///
    /// - Returns: One string per row.
    public func textLines() -> [String] {
        (0..<size.height).map { text(row: $0) }
    }
}
