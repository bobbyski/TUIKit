// `PieChart` — parts of a whole, the ActiveUI `AUISectorMark` shape on the
// TUI side, donut included.
//
// Honesty first: a disc built from character cells is coarse (and at small
// sizes, frankly comic). So the LEGEND carries the truth — every slice's
// name and exact percentage — and the disc is the shape that makes shares
// scannable. On a VTG terminal the disc becomes real vector sectors and
// stops being funny.

import Foundation

/// Slices of a whole — pie, or donut via ``innerRadiusFraction``.
///
/// ```text
///          ▄▄██▀▀▀▄▄        █ rent      42%
///        ██████▀    ▀▄      █ food      33%
///       ███████       █     █ transit   17%
///        ██████▄    ▄▀      █ misc       8%
///          ▀▀██▄▄▄▀▀
/// ```
///
/// Slices draw **in the order given**, clockwise from 12 o'clock —
/// reordering a reader's categories to flatter the chart is the app's
/// decision, never the chart's (the ActiveUI rule). Values are magnitudes:
/// negatives fold to their absolute value, because a negative share of a
/// whole means nothing. Use ``BarChart`` when the question is "which is
/// biggest"; a pie only answers "what share of the whole".
@MainActor
public final class PieChart: TUIView {
    /// One slice.
    public struct Slice: Sendable {
        /// Name shown in the legend.
        public var label: String

        /// The slice's magnitude (negatives fold to absolute).
        public var value: Double

        /// Colour override; `nil` takes the theme's ``ResolvedTheme/chartData(_:)``.
        public var style: CellStyle?

        /// Creates a slice.
        public init(label: String, value: Double, style: CellStyle? = nil) {
            self.label = label
            self.value = value
            self.style = style
        }
    }

    /// The slices, drawn in order, clockwise from 12 o'clock.
    public var slices: [Slice] {
        didSet {
            setNeedsDisplay()
        }
    }

    /// The hole in the middle, as a fraction of the outer radius. 0 (the
    /// default) draws a pie; 0.5–0.6 a donut. Clamped to 0…0.9.
    public var innerRadiusFraction: Double = 0 {
        didSet {
            if innerRadiusFraction != oldValue {
                setNeedsDisplay()
            }
        }
    }

    /// Whether the legend (names + exact percentages — the part that is
    /// never laughable) draws beside the disc. On by default.
    public var showsLegend = true {
        didSet {
            if showsLegend != oldValue {
                setNeedsDisplay()
            }
        }
    }

    /// Glyph alphabet for the cell disc: `.blocks` (default) or `.ascii`.
    public var fidelity: ChartFidelity = .blocks {
        didSet {
            if fidelity != oldValue {
                setNeedsDisplay()
            }
        }
    }

    /// Creates a pie chart.
    public init(slices: [Slice] = []) {
        self.slices = slices
        super.init(frame: .zero)
    }

    /// A natural minimum; hosts normally size a chart with anchors.
    public override var intrinsicContentSize: Size? {
        Size(width: 30, height: 7)
    }

    // MARK: - Drawing

    public override func draw(_ painter: Painter) {
        painter.fill(bounds, with: .blank)

        let theme = effectiveTheme
        let magnitudes = slices.map { abs($0.value) }
        let total = magnitudes.reduce(0, +)

        guard total > 0, bounds.size.height >= 3 else {
            return
        }

        let inks = slices.enumerated().map { index, slice in
            slice.style ?? CellStyle(foreground: theme.chartData(index))
        }

        // Cumulative fractions → each slice's [start, end) angle share.
        // The last boundary is FORCED to exactly 1: summed floating-point
        // fractions land a hair under, and that hair is a visible dark
        // sliver at 12 o'clock once angles round to pixels.
        var boundaries: [Double] = [0]
        var running = 0.0

        for magnitude in magnitudes {
            running += magnitude / total
            boundaries.append(running)
        }

        boundaries[boundaries.count - 1] = 1

        // Disc geometry: the largest circle the left region allows. Cells
        // are ~half as wide as tall, so the x radius doubles.
        let height = bounds.size.height
        let radiusY = Double(height) / 2 - 0.1
        let radiusX = radiusY * 2
        let centerX = radiusX + 0.5
        let centerY = Double(height) / 2
        let inner = min(0.9, max(0, innerRadiusFraction))

        let discWidth = Int((radiusX * 2).rounded()) + 1

        if showsLegend {
            drawLegend(painter, theme: theme, inks: inks, magnitudes: magnitudes, total: total, x: discWidth + 2)
        }

        // Vector mode: real sectors, all-or-nothing like every chart here.
        if let chrome = painter.chrome, chrome.covers(bounds),
           let backing = ChromeColor(theme.background),
           inks.allSatisfy({ ChromeColor($0.foreground) != nil }) {
            chrome.rect(
                "backing",
                ChromeRect(x: 0, y: 0, width: Double(discWidth) + 1, height: Double(height)),
                fill: backing
            )

            let transparent = painter.withBase(CellStyle())
            transparent.fill(Rect(x: 0, y: 0, width: discWidth + 1, height: height), with: .blank)

            // Full pie slices, with the donut hole as ONE surface-colored
            // circle on top — not per-slice inner arcs. A ring path (outer
            // arc, reversed inner arc) leans on the renderer's winding
            // rules; slices-plus-hole is winding-proof and closes cleanly.
            //
            // Each slice overdraws its end by a hair: two fills sharing an
            // edge let a hairline of background through the antialiasing,
            // so every boundary is COVERED by the next slice instead of
            // abutted — and the last slice wraps just past 12 o'clock to
            // cover the first boundary the same way.
            let overlap = 0.012

            for (index, _) in slices.enumerated() where magnitudes[index] > 0 {
                chrome.sector(
                    "slice-\(index)",
                    center: ChromePoint(x: centerX, y: centerY),
                    radius: radiusY,
                    start: boundaries[index] * 2 * Double.pi,
                    end: boundaries[index + 1] * 2 * Double.pi + overlap,
                    fill: ChromeColor(inks[index].foreground)!
                )
            }

            if inner > 0 {
                chrome.circle(
                    "hole",
                    center: ChromePoint(x: centerX, y: centerY),
                    radius: radiusY * inner,
                    fill: backing
                )
            }

            return
        }

        // The cell disc: every cell inside the (elliptical, because cells)
        // ring gets the block glyph of whichever slice owns its angle.
        let glyph: Character = fidelity == .ascii ? "#" : "█"

        for y in 0..<height {
            for x in 0..<discWidth {
                let dx = (Double(x) + 0.5 - centerX) / radiusX
                let dy = (Double(y) + 0.5 - centerY) / radiusY
                let distance = (dx * dx + dy * dy).squareRoot()

                guard distance <= 1, distance >= inner else {
                    continue
                }

                // Angle of this cell, 0 at 12 o'clock, clockwise.
                var angle = atan2(dx, -dy)
                if angle < 0 {
                    angle += 2 * Double.pi
                }

                let fraction = angle / (2 * Double.pi)
                let slice = boundaries.dropLast().lastIndex { $0 <= fraction } ?? 0
                painter.set(TerminalCell(character: glyph, style: inks[min(slice, inks.count - 1)]), at: Point(x: x, y: y))
            }
        }
    }

    // Names and exact percentages — the data's authoritative rendering.
    private func drawLegend(
        _ painter: Painter,
        theme: ResolvedTheme,
        inks: [CellStyle],
        magnitudes: [Double],
        total: Double,
        x: Int
    ) {
        let marker: Character = fidelity == .ascii ? "#" : "█"
        let widest = slices.map { DisplayWidth.of($0.label) }.max() ?? 0

        for (index, slice) in slices.enumerated() where index < bounds.size.height {
            let percent = Int((magnitudes[index] / total * 100).rounded())
            let label = slice.label.padding(toLength: widest, withPad: " ", startingAt: 0)
            painter.set(TerminalCell(character: marker, style: inks[index]), at: Point(x: x, y: index))
            painter.write("\(label) \(String(percent).leftPadded(to: 3))%", at: Point(x: x + 2, y: index))
        }
    }
}

private extension String {
    func leftPadded(to width: Int) -> String {
        count >= width ? self : String(repeating: " ", count: width - count) + self
    }
}
