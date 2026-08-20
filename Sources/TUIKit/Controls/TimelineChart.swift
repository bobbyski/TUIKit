// R10 — `TimelineChart`: rows of horizontal bars against one shared time
// axis, each bar divided into labelled segments. A waterfall — the control
// that answers "why was that page slow".

import Foundation

/// One waterfall row: a label and its segments on the shared axis.
public struct TimelineRow: Sendable {
    /// What a segment of time *was*, mapped to theme slots so a failed
    /// request reads red and a waiting one reads dim without the caller
    /// naming colours.
    public enum SegmentKind: Hashable, Sendable {
        /// Work happening — accent. (`━` / `=`)
        case active

        /// Time spent waiting — de-emphasized. (`┈` / `-`)
        case waiting

        /// Work that finished suspicious — the warning accent.
        case warning

        /// Work that failed — the error accent.
        case failed
    }

    /// One span of time within the row.
    public struct Segment: Sendable {
        /// Where the span begins, in domain units.
        public var start: Double

        /// How long it lasts, in domain units.
        public var duration: Double

        /// What the span was.
        public var kind: SegmentKind

        /// Colour override. `nil` (the default) maps ``kind`` onto a theme
        /// slot; set it when the app owns the colour story — a waterfall
        /// colouring by MIME type, a build chart matching CI's palette. The
        /// same override convention as ``Sparkline/style`` and
        /// ``LineChart/Series/style``.
        public var style: CellStyle?

        /// Creates a segment.
        public init(start: Double, duration: Double, kind: SegmentKind = .active, style: CellStyle? = nil) {
            self.start = start
            self.duration = duration
            self.kind = kind
            self.style = style
        }
    }

    /// Name shown in the left gutter.
    public var label: String

    /// The row's spans, in any order; rendering sorts by start.
    public var segments: [Segment]

    /// Creates a row.
    public init(label: String, segments: [Segment]) {
        self.label = label
        self.segments = segments
    }
}

/// Segmented bars on one shared time axis — a network waterfall, an engine
/// timeline, a build's steps.
///
/// ```text
///                 0ms      200ms     400ms     600ms     800ms
///    index.html   ━━━━━━━━━━━━╸
///    style.css        ┈┈┈┈┈┈━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━╸
///    logo.png              ┈┈┈━━━━━╸
/// ```
///
/// The chart scrolls when there are more rows than lines (300 subresources
/// is a normal page): ↑/↓ move the selection and keep it visible, the wheel
/// scrolls without selecting, a click selects the row under the pointer.
/// Sub-cell spans stay honest — a 30 ms segment on an 800 ms axis still
/// paints (dropping it would make a fast request look like it never
/// happened) and never rounds up into overlapping its neighbour.
@MainActor
public final class TimelineChart: TUIView {
    /// The rows, top to bottom.
    public var rows: [TimelineRow] {
        didSet {
            superview?.setNeedsLayout()
            setNeedsDisplay()
        }
    }

    /// The time span the axis covers. `nil` (the default) fits the rows.
    public var domain: ClosedRange<Double>? {
        didSet {
            if domain != oldValue {
                setNeedsDisplay()
            }
        }
    }

    /// Glyph alphabet: `.blocks` (default) or `.ascii` (`.braille` draws as
    /// `.blocks` — braille bars read worse than block bars).
    public var fidelity: ChartFidelity = .blocks {
        didSet {
            if fidelity != oldValue {
                setNeedsDisplay()
            }
        }
    }

    /// Whether the tick row renders above the bars.
    public var showsAxis = true {
        didSet {
            if showsAxis != oldValue {
                setNeedsDisplay()
            }
        }
    }

    /// Formats a tick value for the axis row. Defaults to a bare trimmed
    /// number; a network waterfall sets `{ "\(Int($0))ms" }`.
    public var tickFormatter: (Double) -> String = { value in
        value == value.rounded() ? String(Int(value)) : String(value)
    } {
        didSet {
            setNeedsDisplay()
        }
    }

    /// Called when interaction selects a row.
    public var onSelectRow: (Int) -> Void = { _ in }

    /// The selected row index, or nil. Set programmatically it is silent
    /// (the TUIKit convention); interaction fires ``onSelectRow``.
    public var selectedRow: Int? {
        didSet {
            if selectedRow != oldValue {
                scrollSelectionIntoView()
                setNeedsDisplay()
            }
        }
    }

    // Topmost visible row (culling: only visible rows are replayed).
    private var firstVisibleRow = 0

    /// Creates a timeline chart.
    ///
    /// - Parameter rows: The rows, top to bottom.
    public init(rows: [TimelineRow] = []) {
        self.rows = rows
        super.init(frame: .zero)
    }

    /// Charts take focus to own ↑/↓ row selection.
    public override var acceptsFirstResponder: Bool {
        true
    }

    /// A natural minimum: the label gutter plus room for the bars. Hosts
    /// normally size a chart with anchors instead.
    public override var intrinsicContentSize: Size? {
        Size(width: labelGutterWidth + 24, height: rows.count + (showsAxis ? 1 : 0))
    }

    // MARK: - Geometry

    // Left gutter: the widest label plus one separating space, capped to a
    // third of the width so labels cannot squeeze the chart out.
    private var labelGutterWidth: Int {
        let widest = rows.map { DisplayWidth.of($0.label) }.max() ?? 0
        return widest + 1
    }

    private func gutterWidth(in width: Int) -> Int {
        min(labelGutterWidth, max(0, width / 3))
    }

    // The resolved time domain: explicit, else fitted to the rows.
    private var resolvedDomain: ClosedRange<Double> {
        if let domain {
            return domain
        }

        var low = Double.greatestFiniteMagnitude
        var high = -Double.greatestFiniteMagnitude

        for row in rows {
            for segment in row.segments {
                low = min(low, segment.start)
                high = max(high, segment.start + segment.duration)
            }
        }

        guard low <= high else {
            return 0...1
        }

        return low...(high > low ? high : low + 1)
    }

    // Lines available for rows (under the axis).
    private var rowLines: Int {
        max(0, bounds.size.height - (showsAxis ? 1 : 0))
    }

    // MARK: - Drawing

    /// Draws the axis, the visible rows' labels, and their bars.
    public override func draw(_ painter: Painter) {
        painter.fill(bounds, with: .blank)

        let width = bounds.size.width
        let gutter = gutterWidth(in: width)
        let plotWidth = width - gutter

        guard width > 0, plotWidth > 1 else {
            return
        }

        let theme = effectiveTheme
        let domain = resolvedDomain
        let axisRow = showsAxis ? 0 : -1

        if showsAxis {
            drawAxis(painter, gutter: gutter, plotWidth: plotWidth, domain: domain, theme: theme)
        }

        clampScroll()

        // The vector rendering (VTG terminals): bars become rounded
        // sub-cell-precise blocks on a backing in the surface colour, while
        // labels and the axis stay native text. Only when the theme's
        // colours have real RGB; `suppressesVectorChrome` pins glyphs.
        let chrome: ChromeSurface?

        if let surface = painter.chrome, ChromeColor(theme.background) != nil {
            chrome = surface
            surface.rect(
                "backing",
                ChromeRect(Rect(x: gutter, y: axisRow + 1, width: plotWidth, height: rowLines)),
                fill: ChromeColor(theme.background)
            )
        } else {
            chrome = nil
        }

        for line in 0..<rowLines {
            let index = firstVisibleRow + line

            guard index < rows.count else {
                break
            }

            let y = axisRow + 1 + line
            let row = rows[index]

            // The label, selection-highlighted; bars keep their own colours
            // because the colours are the data.
            let labelStyle = index == selectedRow ? theme.selection : theme.base
            let label = Label.truncated(row.label, width: max(0, gutter - 1))
            painter.write(label, at: Point(x: 0, y: y), style: labelStyle)

            if let chrome {
                drawVectorBar(
                    row, rowIndex: index, at: y, gutter: gutter, plotWidth: plotWidth,
                    domain: domain, theme: theme, chrome: chrome, painter: painter
                )
            } else {
                drawBar(row, at: y, gutter: gutter, plotWidth: plotWidth, domain: domain, theme: theme, painter: painter)
            }
        }
    }

    // One row's bar as vector chrome: rounded blocks at true fractional
    // positions (a 30ms segment is 1.5 real cells wide, not a rounded
    // column count), same honesty rules — a minimum visible width, never
    // overlapping the previous segment.
    private func drawVectorBar(
        _ row: TimelineRow,
        rowIndex: Int,
        at y: Int,
        gutter: Int,
        plotWidth: Int,
        domain: ClosedRange<Double>,
        theme: ResolvedTheme,
        chrome: ChromeSurface,
        painter: Painter
    ) {
        let span = domain.upperBound - domain.lowerBound

        guard span > 0 else {
            return
        }

        // The bar cells go transparent so the under-text blocks show.
        let transparent = painter.withBase(CellStyle())
        transparent.fill(Rect(x: gutter, y: y, width: plotWidth, height: 1), with: .blank)

        func position(_ value: Double) -> Double {
            (min(max(value, domain.lowerBound), domain.upperBound) - domain.lowerBound)
                / span * Double(plotWidth)
        }

        var previousEnd = 0.0
        let minimumWidth = 0.2

        for (index, segment) in row.segments.sorted(by: { $0.start < $1.start }).enumerated() {
            var begin = position(segment.start)
            var end = position(segment.start + segment.duration)

            if end - begin < minimumWidth {
                end = begin + minimumWidth
            }

            if begin < previousEnd {
                begin = previousEnd
                end = max(end, begin + minimumWidth)
            }

            guard begin < Double(plotWidth) else {
                continue
            }

            end = min(end, Double(plotWidth))

            guard begin < end else {
                continue
            }

            // The style override (or the kind's slot) supplies the ink; a
            // colourless ink drops just this segment to nothing rather than
            // the whole chart to glyphs — the theme check above already
            // guaranteed the common slots.
            let ink = (segment.style ?? style(for: segment.kind, theme: theme)).foreground

            guard let fill = ChromeColor(ink) else {
                continue
            }

            // Work reads as a solid block, waiting as a thin channel.
            let thin = segment.kind == .waiting && segment.style == nil
            let height = thin ? 0.24 : 0.62
            let top = Double(y) + (1 - height) / 2

            chrome.rect(
                "bar-\(rowIndex)-\(index)",
                ChromeRect(x: Double(gutter) + begin, y: top, width: end - begin, height: height),
                fill: fill,
                radius: thin ? 0.1 : 0.26
            )

            previousEnd = end
        }
    }

    // Round tick steps: 1/2/5 × 10^k, spaced at least eight columns apart so
    // labels breathe at any width.
    private func drawAxis(
        _ painter: Painter,
        gutter: Int,
        plotWidth: Int,
        domain: ClosedRange<Double>,
        theme: ResolvedTheme
    ) {
        let span = domain.upperBound - domain.lowerBound

        guard span > 0 else {
            return
        }

        let minimumTickSpacing = 8.0
        let roughStep = span * minimumTickSpacing / Double(plotWidth)
        let magnitude = pow10(Int(Foundation.floor(Foundation.log10(max(roughStep, .leastNormalMagnitude)))))
        var step = magnitude

        for multiplier in [1.0, 2.0, 5.0, 10.0] {
            if magnitude * multiplier >= roughStep {
                step = magnitude * multiplier
                break
            }
        }

        let style = theme.chartDeemphasis
        var tick = (domain.lowerBound / step).rounded(.up) * step
        var lastLabelEnd = -1

        while tick <= domain.upperBound {
            let column = gutter + Int(((tick - domain.lowerBound) / span * Double(plotWidth - 1)).rounded())
            let text = tickFormatter(tick)

            // Skip a label that would collide with the previous one — an
            // axis that overwrites itself reads as garbage.
            if column > lastLabelEnd, column + text.count <= bounds.size.width {
                painter.write(text, at: Point(x: column, y: 0), style: style)
                lastLabelEnd = column + text.count
            }

            tick += step
        }
    }

    private func pow10(_ exponent: Int) -> Double {
        var result = 1.0

        if exponent >= 0 {
            for _ in 0..<exponent { result *= 10 }
        } else {
            for _ in 0..<(-exponent) { result /= 10 }
        }

        return result
    }

    // One row's bar: segments sorted by start, each guaranteed at least one
    // cell (sub-cell honesty) and never overlapping the previous segment's
    // cells (a fast request must be visible without stealing its neighbour's
    // columns).
    private func drawBar(
        _ row: TimelineRow,
        at y: Int,
        gutter: Int,
        plotWidth: Int,
        domain: ClosedRange<Double>,
        theme: ResolvedTheme,
        painter: Painter
    ) {
        let span = domain.upperBound - domain.lowerBound

        guard span > 0 else {
            return
        }

        func column(_ value: Double) -> Int {
            Int(((min(max(value, domain.lowerBound), domain.upperBound) - domain.lowerBound)
                / span * Double(plotWidth)).rounded())
        }

        var previousEnd = 0   // in plot columns

        for segment in row.segments.sorted(by: { $0.start < $1.start }) {
            var begin = column(segment.start)
            var end = column(segment.start + segment.duration)

            // Sub-cell spans still paint one cell…
            if end <= begin {
                end = begin + 1
            }

            // …but never by taking a neighbour's: shift right of what is
            // already drawn instead of rounding up over it.
            if begin < previousEnd {
                begin = previousEnd
                end = max(end, begin + 1)
            }

            guard begin < plotWidth else {
                continue
            }

            end = min(end, plotWidth)

            guard begin < end else {
                continue
            }

            let (body, cap) = glyphs(for: segment.kind)
            let style = segment.style ?? style(for: segment.kind, theme: theme)

            for x in begin..<end {
                let isCap = x == end - 1 && segment.kind != .waiting
                painter.set(
                    TerminalCell(character: isCap ? cap : body, style: style),
                    at: Point(x: gutter + x, y: y)
                )
            }

            previousEnd = end
        }
    }

    // Body and end-cap glyph per kind and fidelity. `.waiting` has no cap:
    // it flows into the work it was waiting for.
    private func glyphs(for kind: TimelineRow.SegmentKind) -> (body: Character, cap: Character) {
        switch (fidelity, kind) {
        case (.ascii, .waiting):
            return ("-", "-")

        case (.ascii, _):
            return ("=", "=")

        case (_, .waiting):
            return ("┈", "┈")

        case (_, _):
            return ("━", "╸")
        }
    }

    private func style(for kind: TimelineRow.SegmentKind, theme: ResolvedTheme) -> CellStyle {
        switch kind {
        case .active:
            return CellStyle(foreground: theme.chartAccent)

        case .waiting:
            return theme.chartDeemphasis

        case .warning:
            return CellStyle(foreground: theme.warningAccent)

        case .failed:
            return CellStyle(foreground: theme.errorAccent)
        }
    }

    // MARK: - Interaction

    /// ↑/↓ move the selection (and scroll it into view); Home/End jump.
    public override func keyDown(_ key: KeyInput) -> Bool {
        guard key.modifiers.isEmpty, !rows.isEmpty else {
            return false
        }

        switch key.key {
        case .up:
            select(max(0, (selectedRow ?? rows.count) - 1))
            return true

        case .down:
            select(min(rows.count - 1, (selectedRow ?? -1) + 1))
            return true

        case .home:
            select(0)
            return true

        case .end:
            select(rows.count - 1)
            return true

        default:
            return false
        }
    }

    /// Click selects the row under the pointer; the wheel scrolls.
    public override func mouseEvent(_ mouse: MouseInput) -> Bool {
        switch mouse.action {
        case .press where mouse.button == .left:
            let line = mouse.position.y - (showsAxis ? 1 : 0)
            let index = firstVisibleRow + line

            guard line >= 0, rows.indices.contains(index) else {
                return false
            }

            select(index)
            return true

        case .scrollUp:
            firstVisibleRow = max(0, firstVisibleRow - 1)
            setNeedsDisplay()
            return true

        case .scrollDown:
            firstVisibleRow = min(max(0, rows.count - rowLines), firstVisibleRow + 1)
            setNeedsDisplay()
            return true

        default:
            return false
        }
    }

    private func select(_ index: Int) {
        let changed = selectedRow != index
        selectedRow = index

        if changed {
            onSelectRow(index)
        }
    }

    private func scrollSelectionIntoView() {
        guard let selectedRow, rowLines > 0 else {
            return
        }

        if selectedRow < firstVisibleRow {
            firstVisibleRow = selectedRow
        } else if selectedRow >= firstVisibleRow + rowLines {
            firstVisibleRow = selectedRow - rowLines + 1
        }
    }

    private func clampScroll() {
        firstVisibleRow = min(max(0, rows.count - rowLines), max(0, firstVisibleRow))
    }
}
