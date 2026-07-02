/// Integer point in terminal cell coordinates.
///
/// TUIKit uses its own geometry types so the framework builds identically on
/// macOS and Linux with no AppKit or CoreGraphics dependency. Coordinates
/// are cell-based: x grows rightward, y grows downward, and (0, 0) is the
/// top-left cell.
public struct Point: Hashable, Codable, Sendable {
    /// Horizontal cell coordinate.
    public var x: Int

    /// Vertical cell coordinate.
    public var y: Int

    /// The origin point (0, 0).
    public static let zero = Point(x: 0, y: 0)

    /// Creates a point.
    ///
    /// - Parameters:
    ///   - x: Horizontal cell coordinate.
    ///   - y: Vertical cell coordinate.
    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }

    /// Returns the point offset by another point.
    ///
    /// - Parameters:
    ///   - lhs: Base point.
    ///   - rhs: Offset to add.
    /// - Returns: The translated point.
    public static func + (lhs: Point, rhs: Point) -> Point {
        Point(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }

    /// Returns the point offset by the negation of another point.
    ///
    /// - Parameters:
    ///   - lhs: Base point.
    ///   - rhs: Offset to subtract.
    /// - Returns: The translated point.
    public static func - (lhs: Point, rhs: Point) -> Point {
        Point(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }
}

/// Integer size in terminal cells.
public struct Size: Hashable, Codable, Sendable {
    /// Width in cells.
    public var width: Int

    /// Height in cells.
    public var height: Int

    /// The zero size.
    public static let zero = Size(width: 0, height: 0)

    /// Creates a size. Negative components are clamped to zero.
    ///
    /// - Parameters:
    ///   - width: Width in cells.
    ///   - height: Height in cells.
    public init(width: Int, height: Int) {
        self.width = max(0, width)
        self.height = max(0, height)
    }

    /// Whether the size covers no cells.
    public var isEmpty: Bool {
        width == 0 || height == 0
    }

    /// Total number of cells covered.
    public var cellCount: Int {
        width * height
    }
}

/// Integer rectangle in terminal cell coordinates.
public struct Rect: Hashable, Codable, Sendable {
    /// Top-left corner.
    public var origin: Point

    /// Extent in cells.
    public var size: Size

    /// The zero rectangle.
    public static let zero = Rect(origin: .zero, size: .zero)

    /// Creates a rectangle from an origin and size.
    ///
    /// - Parameters:
    ///   - origin: Top-left corner.
    ///   - size: Extent in cells.
    public init(origin: Point, size: Size) {
        self.origin = origin
        self.size = size
    }

    /// Creates a rectangle from components.
    ///
    /// - Parameters:
    ///   - x: Left edge.
    ///   - y: Top edge.
    ///   - width: Width in cells.
    ///   - height: Height in cells.
    public init(x: Int, y: Int, width: Int, height: Int) {
        self.init(origin: Point(x: x, y: y), size: Size(width: width, height: height))
    }

    /// Left edge.
    public var minX: Int { origin.x }

    /// Top edge.
    public var minY: Int { origin.y }

    /// One past the right edge.
    public var maxX: Int { origin.x + size.width }

    /// One past the bottom edge.
    public var maxY: Int { origin.y + size.height }

    /// Whether the rectangle covers no cells.
    public var isEmpty: Bool { size.isEmpty }

    /// Whether a point lies inside the rectangle.
    ///
    /// - Parameter point: Point to test.
    /// - Returns: `true` when the point is inside.
    public func contains(_ point: Point) -> Bool {
        point.x >= minX && point.x < maxX && point.y >= minY && point.y < maxY
    }

    /// The overlapping region of two rectangles.
    ///
    /// - Parameter other: Rectangle to intersect with.
    /// - Returns: The intersection, or `Rect.zero` when they do not overlap.
    public func intersection(_ other: Rect) -> Rect {
        let x0 = max(minX, other.minX)
        let y0 = max(minY, other.minY)
        let x1 = min(maxX, other.maxX)
        let y1 = min(maxY, other.maxY)

        guard x1 > x0, y1 > y0 else {
            return .zero
        }

        return Rect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }
}
