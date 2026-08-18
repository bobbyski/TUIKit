import Foundation
// Phase 10 — VTG vector chrome (see Docs/VTGChrome.md).
//
// Chrome is a *presentation upgrade*: when the terminal speaks VectorTerminal
// Graphics, views decorate themselves with a few vector shapes — rounded
// titlebars, pill buttons, circular window controls — drawn on the plane
// under the text. Nothing about layout, focus, events, or the public control
// surface changes; a plain terminal renders the same cells it always did.
//
// The model here is deliberately typed and driver-free: views emit
// `ChromeCommand` values through a `ChromeSurface` (the vector sibling of
// `Painter`, riding the same origin/clip derivation), the renderer collects
// them per frame, and a driver translates them to actual VTG escape
// sequences. The headless driver records them instead, so every chrome
// behavior is testable without a terminal.

// MARK: - Color

/// A 32-bit RGBA color for vector chrome.
///
/// Distinct from `TerminalColor` because chrome supports what cells cannot:
/// alpha. Encodes to a CSS-style `#RRGGBB` / `#RRGGBBAA` string in theme
/// files.
public struct ChromeColor: Hashable, Sendable {
    /// Red channel (0–255).
    public var red: UInt8
    /// Green channel (0–255).
    public var green: UInt8
    /// Blue channel (0–255).
    public var blue: UInt8
    /// Alpha channel (0 transparent – 255 opaque).
    public var alpha: UInt8

    /// Creates a color from channels.
    public init(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8 = 255) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// Creates a color from `#RRGGBB` or `#RRGGBBAA`.
    public init?(hex: String) {
        guard hex.hasPrefix("#") else {
            return nil
        }

        let digits = hex.dropFirst()

        func channel(_ offset: Int) -> UInt8? {
            let start = digits.index(digits.startIndex, offsetBy: offset)
            let end = digits.index(start, offsetBy: 2)
            return UInt8(digits[start..<end], radix: 16)
        }

        switch digits.count {
        case 6:
            guard let r = channel(0), let g = channel(2), let b = channel(4) else {
                return nil
            }
            self.init(red: r, green: g, blue: b)

        case 8:
            guard let r = channel(0), let g = channel(2), let b = channel(4), let a = channel(6) else {
                return nil
            }
            self.init(red: r, green: g, blue: b, alpha: a)

        default:
            return nil
        }
    }

    /// The `#RRGGBBAA` spelling (`#RRGGBB` when fully opaque).
    public var hexString: String {
        // Two uppercase hex digits per channel, without Foundation.
        func hex(_ value: UInt8) -> String {
            let digits = Array("0123456789ABCDEF")
            return String([digits[Int(value >> 4)], digits[Int(value & 0xF)]])
        }

        let core = "#" + hex(red) + hex(green) + hex(blue)
        return alpha == 255 ? core : core + hex(alpha)
    }

    /// Linear interpolation between two colors.
    ///
    /// - Parameters:
    ///   - from: Color at `fraction` 0.
    ///   - to: Color at `fraction` 1.
    ///   - fraction: Blend position, clamped to 0…1.
    public static func lerp(_ from: ChromeColor, _ to: ChromeColor, _ fraction: Double) -> ChromeColor {
        let t = min(1, max(0, fraction))

        func mix(_ a: UInt8, _ b: UInt8) -> UInt8 {
            UInt8(clamping: Int((Double(a) + (Double(b) - Double(a)) * t).rounded()))
        }

        return ChromeColor(
            red: mix(from.red, to.red),
            green: mix(from.green, to.green),
            blue: mix(from.blue, to.blue),
            alpha: mix(from.alpha, to.alpha)
        )
    }

    /// The chrome equivalent of a cell color, when it has known RGB.
    ///
    /// `.standard` and palette entries return `nil` — chrome needs real
    /// channel values.
    public init?(_ cellColor: TerminalColor) {
        guard let components = cellColor.rgbComponents else {
            return nil
        }

        self.init(red: components.red, green: components.green, blue: components.blue)
    }
}

extension ChromeColor: Codable {
    /// Decodes from the `#RRGGBB(AA)` theme-file spelling.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)

        guard let color = ChromeColor(hex: string) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unrecognized chrome color \"\(string)\""
            )
        }

        self = color
    }

    /// Encodes as the `#RRGGBB(AA)` theme-file spelling.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hexString)
    }
}

// MARK: - Geometry

/// A point in fractional cell coordinates.
///
/// Chrome geometry is expressed in the cell grid — `x` in cell widths, `y`
/// in cell heights — with fractional precision, so a shape can start halfway
/// through a cell. Drivers convert to canvas pixels with their glyph
/// metrics; the framework never sees a pixel.
public struct ChromePoint: Hashable, Sendable {
    /// Horizontal position in cell widths.
    public var x: Double
    /// Vertical position in cell heights.
    public var y: Double

    /// Creates a point.
    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// A rectangle in fractional cell coordinates (see `ChromePoint`).
public struct ChromeRect: Hashable, Sendable {
    /// Left edge in cell widths.
    public var x: Double
    /// Top edge in cell heights.
    public var y: Double
    /// Width in cell widths.
    public var width: Double
    /// Height in cell heights.
    public var height: Double

    /// Creates a rectangle.
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// The whole-cell rectangle, converted.
    public init(_ rect: Rect) {
        self.init(
            x: Double(rect.origin.x),
            y: Double(rect.origin.y),
            width: Double(rect.size.width),
            height: Double(rect.size.height)
        )
    }

    /// Right edge in cell widths.
    public var maxX: Double { x + width }
    /// Bottom edge in cell heights.
    public var maxY: Double { y + height }

    /// Whether the rectangle covers no area.
    public var isEmpty: Bool { width <= 0 || height <= 0 }

    /// The shared region with another rectangle (empty when disjoint).
    public func intersection(_ other: ChromeRect) -> ChromeRect {
        let minX = Swift.max(x, other.x)
        let minY = Swift.max(y, other.y)
        let maxX = Swift.min(self.maxX, other.maxX)
        let maxY = Swift.min(self.maxY, other.maxY)

        return ChromeRect(
            x: minX,
            y: minY,
            width: Swift.max(0, maxX - minX),
            height: Swift.max(0, maxY - minY)
        )
    }

    /// Whether any area is shared with another rectangle.
    public func intersects(_ other: ChromeRect) -> Bool {
        !intersection(other).isEmpty
    }

    /// The rectangle translated by whole cells.
    func offset(by point: Point) -> ChromeRect {
        ChromeRect(x: x + Double(point.x), y: y + Double(point.y), width: width, height: height)
    }
}

/// Which corners of a chrome rectangle round.
public struct ChromeCorners: OptionSet, Hashable, Sendable {
    /// Raw bitset value.
    public let rawValue: Int

    /// Creates corners from a raw bitset.
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// The top-left corner.
    public static let topLeft = ChromeCorners(rawValue: 1 << 0)
    /// The top-right corner.
    public static let topRight = ChromeCorners(rawValue: 1 << 1)
    /// The bottom-right corner.
    public static let bottomRight = ChromeCorners(rawValue: 1 << 2)
    /// The bottom-left corner.
    public static let bottomLeft = ChromeCorners(rawValue: 1 << 3)

    /// Both top corners (the classic titlebar shape).
    public static let top: ChromeCorners = [.topLeft, .topRight]
    /// Both bottom corners.
    public static let bottom: ChromeCorners = [.bottomLeft, .bottomRight]
    /// All four corners.
    public static let all: ChromeCorners = [.topLeft, .topRight, .bottomRight, .bottomLeft]
}

/// Which VTG plane a chrome shape draws on.
public enum ChromeLayer: Hashable, Sendable {
    /// The plane *under* the terminal text: chrome shows through wherever a
    /// cell keeps the terminal's default background. This is where nearly
    /// all chrome belongs — the text stays crisp native text on top.
    case underText

    /// The default overlay plane *above* the text (reserved for future
    /// effects; overlays cover glyphs).
    case overlay
}

// MARK: - Commands

/// One retained vector shape, in fractional cell coordinates.
///
/// Commands are the currency between views and drivers: views emit them
/// through `ChromeSurface`, `SceneRenderer` collects them per frame, and a
/// driver converts them to VTG escape sequences (or records them, headless).
/// The `id` keys the terminal's retained scene — stable ids update shapes in
/// place; ids absent from a frame are deleted.
public struct ChromeCommand: Hashable, Sendable {
    /// Retained-scene object id (view-scoped; see `ChromeSurface`).
    public var id: String

    /// The plane the shape draws on.
    public var layer: ChromeLayer

    /// The shape itself.
    public var shape: Shape

    /// A chrome shape. Scalar sizes (corner radius, line width) are
    /// fractions of the cell *height* — the taller cell axis — so "0.25"
    /// reads as a quarter of a text row everywhere.
    public enum Shape: Hashable, Sendable {
        /// A filled and/or stroked rectangle, optionally rounded.
        case rect(
            ChromeRect,
            fill: ChromeColor?,
            stroke: ChromeColor?,
            lineWidth: Double,
            radius: Double,
            corners: ChromeCorners
        )

        /// A filled and/or stroked circle.
        case circle(
            center: ChromePoint,
            radius: Double,
            fill: ChromeColor?,
            stroke: ChromeColor?,
            lineWidth: Double
        )

        /// A straight line.
        case line(from: ChromePoint, to: ChromePoint, color: ChromeColor, width: Double)

        /// A raster image, placed and scaled into a rectangle.
        ///
        /// The one shape whose payload is not geometry. It exists because a
        /// toolbar icon wants a real picture on a VTG terminal and a glyph on
        /// a plain one, and VectorTerminalSDK has had `canvas.image` all
        /// along — TUIKit simply never surfaced it.
        case image(ChromeRect, data: Data, format: ImageFormat)
    }

    /// Raster formats VTG accepts.
    public enum ImageFormat: String, Hashable, Sendable {
        case png
        case jpeg
    }

    /// Creates a command.
    public init(id: String, layer: ChromeLayer = .underText, shape: Shape) {
        self.id = id
        self.layer = layer
        self.shape = shape
    }

    /// The shape's bounding rectangle, for clip tests.
    public var boundingRect: ChromeRect {
        switch shape {
        case .rect(let rect, _, _, _, _, _):
            return rect

        case .circle(let center, let radius, _, _, _):
            // Radius is in cell heights; the horizontal reach in cell widths
            // is larger. Without glyph metrics assume up to 2.5× — the clip
            // test only needs to be conservative, never exact.
            let horizontal = radius * 2.5
            return ChromeRect(
                x: center.x - horizontal,
                y: center.y - radius,
                width: horizontal * 2,
                height: radius * 2
            )

        case .image(let rect, _, _):
            return rect

        case .line(let from, let to, _, _):
            let minX = Swift.min(from.x, to.x)
            let minY = Swift.min(from.y, to.y)
            return ChromeRect(
                x: minX,
                y: minY,
                width: Swift.max(from.x, to.x) - minX,
                height: Swift.max(from.y, to.y) - minY
            )
        }
    }
}

// MARK: - Surface

/// The vector sibling of `Painter`: how a view draws chrome.
///
/// A surface exists on a painter only while chrome is enabled (a VTG
/// terminal was detected), so views guard with `if let chrome =
/// painter.chrome`. Coordinates are view-local fractional cells; the surface
/// composes the same translation and clip the painter does, so the Phase 3
/// clipping contract holds for chrome too.
///
/// Object ids are view-scoped: the renderer stamps each view's identity into
/// the surface before `draw(_:)`, and every call takes a short `key` unique
/// within the view (`"titlebar"`, `"pill"`). The full retained-scene id is
/// derived from both, so two buttons never collide and a moved view updates
/// its shapes in place.
@MainActor
public struct ChromeSurface {
    private let target: RenderTarget

    /// Translation from view-local to buffer cells.
    public let origin: Point

    /// Writable region in buffer cells.
    public let clip: Rect

    // The owning view's identity prefix for object ids.
    let ownerID: String

    init(target: RenderTarget, origin: Point, clip: Rect, ownerID: String) {
        self.target = target
        self.origin = origin
        self.clip = clip
        self.ownerID = ownerID
    }

    // The clip in fractional cells.
    private var chromeClip: ChromeRect {
        ChromeRect(clip)
    }

    // Appends a command after translation and clipping. Rectangles clamp to
    // the clip; circles and lines are kept whole when their bounds touch it.
    //
    // VTG identifiers allow only ASCII letters, digits, `-`, and `_` (the
    // terminal drops anything else), so the owner/key join uses `_` — keys
    // must stick to that alphabet too.
    private func append(_ key: String, layer: ChromeLayer, shape: ChromeCommand.Shape) {
        let id = "\(ownerID)_\(key)"

        switch shape {
        case .rect(let rect, let fill, let stroke, let lineWidth, let radius, let corners):
            let translated = rect.offset(by: origin)
            let clipped = translated.intersection(chromeClip)

            guard !clipped.isEmpty else {
                return
            }

            target.appendChrome(ChromeCommand(
                id: id,
                layer: layer,
                shape: .rect(clipped, fill: fill, stroke: stroke, lineWidth: lineWidth, radius: radius, corners: corners)
            ))

        case .circle(let center, let radius, let fill, let stroke, let lineWidth):
            let translated = ChromePoint(x: center.x + Double(origin.x), y: center.y + Double(origin.y))
            let command = ChromeCommand(
                id: id,
                layer: layer,
                shape: .circle(center: translated, radius: radius, fill: fill, stroke: stroke, lineWidth: lineWidth)
            )

            guard command.boundingRect.intersects(chromeClip) else {
                return
            }

            target.appendChrome(command)

        case .image(let rect, let data, let format):
            // Clipped like a rect, and for the same reason: a toolbar icon
            // near a pane edge must not paint over its neighbour.
            let clipped = rect.offset(by: origin).intersection(chromeClip)

            guard !clipped.isEmpty else {
                return
            }

            target.appendChrome(ChromeCommand(
                id: id,
                layer: layer,
                shape: .image(clipped, data: data, format: format)
            ))

        case .line(let from, let to, let color, let width):
            let a = ChromePoint(x: from.x + Double(origin.x), y: from.y + Double(origin.y))
            let b = ChromePoint(x: to.x + Double(origin.x), y: to.y + Double(origin.y))
            let command = ChromeCommand(id: id, layer: layer, shape: .line(from: a, to: b, color: color, width: width))

            guard command.boundingRect.intersects(chromeClip) else {
                return
            }

            target.appendChrome(command)
        }
    }

    /// Draws a rectangle, optionally rounded, filled, and stroked.
    ///
    /// - Parameters:
    ///   - key: Id unique within the drawing view.
    ///   - rect: TUIView-local rectangle in fractional cells.
    ///   - fill: Fill color, or `nil` for outline only.
    ///   - stroke: Outline color, or `nil` for fill only.
    ///   - lineWidth: Outline width in cell heights.
    ///   - radius: Corner radius in cell heights.
    ///   - corners: Which corners round.
    ///   - layer: Drawing plane.
    /// Places a raster image in a rectangle.
    ///
    /// - Parameters:
    ///   - key: Id unique within the drawing view.
    ///   - rect: TUIView-local rectangle in fractional cells.
    ///   - data: PNG or JPEG bytes.
    ///   - format: Which of the two `data` is.
    ///   - layer: Plane to draw on.
    public func image(
        _ key: String,
        _ rect: ChromeRect,
        data: Data,
        format: ChromeCommand.ImageFormat,
        layer: ChromeLayer = .underText
    ) {
        append(key, layer: layer, shape: .image(rect, data: data, format: format))
    }

    public func rect(
        _ key: String,
        _ rect: ChromeRect,
        fill: ChromeColor?,
        stroke: ChromeColor? = nil,
        lineWidth: Double = 0.05,
        radius: Double = 0,
        corners: ChromeCorners = .all,
        layer: ChromeLayer = .underText
    ) {
        append(key, layer: layer, shape: .rect(rect, fill: fill, stroke: stroke, lineWidth: lineWidth, radius: radius, corners: corners))
    }

    /// Draws a vertical gradient as a rounded base plus horizontal strips.
    ///
    /// VTG has no gradient primitive, so the surface builds one: a rounded
    /// rectangle in the mid color underneath, then `steps` full-precision
    /// strips from `top` to `bottom` on top, each inset where it crosses a
    /// rounded corner so no strip paints outside the arc.
    ///
    /// - Parameters:
    ///   - key: Id unique within the drawing view (strips derive from it).
    ///   - rect: TUIView-local rectangle in fractional cells.
    ///   - top: Color at the top edge.
    ///   - bottom: Color at the bottom edge.
    ///   - steps: Number of strips; more is smoother.
    ///   - radius: Corner radius in cell heights.
    ///   - corners: Which corners round.
    ///   - stroke: Optional outline drawn over the gradient.
    ///   - lineWidth: Outline width in cell heights.
    ///   - layer: Drawing plane.
    public func verticalGradient(
        _ key: String,
        _ rect: ChromeRect,
        top: ChromeColor,
        bottom: ChromeColor,
        steps: Int = 8,
        radius: Double = 0,
        corners: ChromeCorners = .all,
        stroke: ChromeColor? = nil,
        lineWidth: Double = 0.05,
        layer: ChromeLayer = .underText
    ) {
        guard !rect.isEmpty else {
            return
        }

        // The base rounded rect owns the corner arcs; strips cover it almost
        // everywhere, so its mid color only peeks through arc slivers.
        append(key + "-base", layer: layer, shape: .rect(
            rect,
            fill: ChromeColor.lerp(top, bottom, 0.5),
            stroke: nil,
            lineWidth: 0,
            radius: radius,
            corners: corners
        ))

        let count = max(1, steps)
        let stripHeight = rect.height / Double(count)

        for index in 0..<count {
            let y0 = rect.y + stripHeight * Double(index)
            let y1 = y0 + stripHeight
            let color = ChromeColor.lerp(top, bottom, (Double(index) + 0.5) / Double(count))

            // Horizontal inset where the strip crosses a rounded corner: the
            // widest the arc cuts into this strip's vertical span, so the
            // strip stays inside the outline.
            func arcInset(depthIntoBand depth: Double) -> Double {
                guard depth < radius else {
                    return 0
                }

                let clamped = max(0, depth)
                let reach = radius - clamped
                return radius - (radius * radius - reach * reach).squareRoot()
            }

            var leftInset = 0.0
            var rightInset = 0.0

            let topDepth = y0 - rect.y
            let bottomDepth = rect.maxY - y1

            if corners.contains(.topLeft) { leftInset = max(leftInset, arcInset(depthIntoBand: topDepth)) }
            if corners.contains(.bottomLeft) { leftInset = max(leftInset, arcInset(depthIntoBand: bottomDepth)) }
            if corners.contains(.topRight) { rightInset = max(rightInset, arcInset(depthIntoBand: topDepth)) }
            if corners.contains(.bottomRight) { rightInset = max(rightInset, arcInset(depthIntoBand: bottomDepth)) }

            let strip = ChromeRect(
                x: rect.x + leftInset,
                y: y0,
                width: rect.width - leftInset - rightInset,
                height: y1 - y0
            )

            guard !strip.isEmpty else {
                continue
            }

            append(key + "-g\(index)", layer: layer, shape: .rect(
                strip, fill: color, stroke: nil, lineWidth: 0, radius: 0, corners: []
            ))
        }

        if let stroke {
            append(key + "-stroke", layer: layer, shape: .rect(
                rect, fill: nil, stroke: stroke, lineWidth: lineWidth, radius: radius, corners: corners
            ))
        }
    }

    /// Draws a circle.
    ///
    /// - Parameters:
    ///   - key: Id unique within the drawing view.
    ///   - center: TUIView-local center in fractional cells.
    ///   - radius: Radius in cell heights.
    ///   - fill: Fill color, or `nil` for outline only.
    ///   - stroke: Outline color, or `nil` for fill only.
    ///   - lineWidth: Outline width in cell heights.
    ///   - layer: Drawing plane.
    public func circle(
        _ key: String,
        center: ChromePoint,
        radius: Double,
        fill: ChromeColor?,
        stroke: ChromeColor? = nil,
        lineWidth: Double = 0.05,
        layer: ChromeLayer = .underText
    ) {
        append(key, layer: layer, shape: .circle(center: center, radius: radius, fill: fill, stroke: stroke, lineWidth: lineWidth))
    }

    /// Draws a line.
    ///
    /// - Parameters:
    ///   - key: Id unique within the drawing view.
    ///   - from: TUIView-local start in fractional cells.
    ///   - to: TUIView-local end in fractional cells.
    ///   - color: Line color.
    ///   - width: Line width in cell heights.
    ///   - layer: Drawing plane.
    public func line(
        _ key: String,
        from: ChromePoint,
        to: ChromePoint,
        color: ChromeColor,
        width: Double = 0.05,
        layer: ChromeLayer = .underText
    ) {
        append(key, layer: layer, shape: .line(from: from, to: to, color: color, width: width))
    }

}
