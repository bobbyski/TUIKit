/// Border-embedded scrollbars — the Borland/Turbo trick of drawing a window's
/// scrollbars *into its chrome*: the vertical bar rides the right border and
/// the horizontal bar rides the bottom border, so the content area never
/// spends an interior column/row on an indicator.
///
/// A scrollable view opts in by conforming to `BorderScrollable`; the window
/// chrome (`Panel`, via `FloatingWindow.embedScrollbars`) reads the view's
/// `ScrollSpan`s each frame to draw the bars and drives the view's offsets
/// from clicks and drags on the border.

/// One axis of scroll state: what's visible out of how much.
public struct ScrollSpan: Equatable, Sendable {
    /// First visible unit (line or column).
    public var offset: Int

    /// Units visible at once.
    public var viewport: Int

    /// Total units.
    public var content: Int

    /// Creates a span.
    public init(offset: Int, viewport: Int, content: Int) {
        self.offset = offset
        self.viewport = viewport
        self.content = content
    }

    /// The largest valid `offset`.
    public var maxOffset: Int {
        max(0, content - viewport)
    }
}

/// How far an embedded bar runs along its border edge.
public enum BorderScrollbarExtent: Sendable {
    /// The whole border run between the corners.
    case fullEdge

    /// Only the client view's span along that edge — e.g. the editor pane's
    /// width, so the bottom bar doesn't run under a sidebar tree.
    case underClient
}

/// A view whose scrolling window chrome can surface as border-embedded bars.
///
/// Conformers keep answering with live values (the chrome re-reads them every
/// frame) and clamp offsets they're handed. `showsOwnScrollbars` is switched
/// off by the chrome when it embeds the view, so the interior column/row the
/// view would spend on its own indicator returns to the content.
@MainActor
public protocol BorderScrollable: TUIView {
    /// Vertical scroll state, or `nil` to draw no bar for the axis.
    ///
    /// Embedded bars are permanent chrome (the Borland look): report a span
    /// even when the content fits — the thumb fills the track — so the bar
    /// doesn't pop in and out as the window resizes past the content.
    var verticalScrollSpan: ScrollSpan? { get }

    /// Horizontal scroll state, or `nil` to draw no bar for the axis.
    var horizontalScrollSpan: ScrollSpan? { get }

    /// Whether the view draws its own interior scrollbars.
    var showsOwnScrollbars: Bool { get set }

    /// Scrolls to a first-visible line (the view clamps).
    func setScrollOffset(vertical offset: Int)

    /// Scrolls to a first-visible column (the view clamps).
    func setScrollOffset(horizontal offset: Int)
}

/// One scrollbar's geometry along an edge: where it starts, how long it is,
/// what it is scrolling, and whether it wears end arrows.
///
/// Shared on purpose. `Panel` draws the border-embedded bars and a view like
/// `CodeEditorView` draws its own interior ones, and for a while those were
/// two implementations — which is how the interior pair ended up with no
/// arrows and no drag handling while the embedded pair had both. The maths is
/// the same maths; only where it is painted differs.
public struct ScrollbarRun {
    /// First cell of the run along its edge.
    public var start: Int

    /// Cells the run occupies.
    public var length: Int

    /// What is being scrolled.
    public var span: ScrollSpan

    /// Whether the ends are `▴`/`▾` (or `◂`/`▸`) step buttons.
    public var hasArrows: Bool

    /// Whether a run of this length is long enough to be worth arrows.
    ///
    /// Six: an arrow at each end plus four cells of track. Below that the
    /// arrows eat the track — a four-cell bar becomes arrow, two cells, arrow,
    /// and the two-cell minimum thumb fills it with no travel left, which is
    /// a scrollbar that cannot scroll. The rule lives here rather than at each
    /// call site so every bar in the framework agrees about it.
    public static func wantsArrows(forLength length: Int) -> Bool {
        length >= 6
    }

    /// Creates a run.
    ///
    /// - Parameter hasArrows: Defaults to ``wantsArrows(forLength:)``.
    public init(start: Int, length: Int, span: ScrollSpan, hasArrows: Bool? = nil) {
        self.start = start
        self.length = length
        self.span = span
        self.hasArrows = hasArrows ?? Self.wantsArrows(forLength: length)
    }

    /// Track region (between the arrows, or the whole run without them).
    public var trackStart: Int { start + (hasArrows ? 1 : 0) }

    /// Cells of track.
    public var trackLength: Int { length - (hasArrows ? 2 : 0) }

    /// Thumb start/length within the track — proportional to the viewport.
    ///
    /// The ROUNDED, two-cell-minimum rule, taken from `ScrollView`, which had
    /// the best of the six implementations: a thumb thinner than two cells is
    /// hard to grab, and truncating instead of rounding makes a long document
    /// report a thumb one cell short of honest. Never the whole track, so it
    /// always has travel room.
    public var thumb: (start: Int, length: Int) {
        let n = trackLength

        guard n > 0 else {
            return (trackStart, 0)
        }

        let proportional = (n * span.viewport + span.content / 2) / max(1, span.content)
        let minimum = n > 2 ? 2 : 1
        let length = min(max(minimum, proportional), max(1, n - 1))
        let maxStart = max(0, n - length)
        let start = span.maxOffset > 0
            ? min(maxStart, span.offset * maxStart / max(1, span.maxOffset))
            : 0

        return (trackStart + start, length)
    }

    /// Maps a track cell back to a scroll offset (for thumb drags).
    public func offset(forThumbStart start: Int) -> Int {
        let maxStart = max(0, trackLength - thumb.length)
        let clamped = min(max(0, start - trackStart), maxStart)
        return maxStart > 0 ? clamped * span.maxOffset / maxStart : 0
    }

    /// What a press at a cell should scroll to: an arrow steps by one, the
    /// track pages toward the press, and the thumb starts a drag.
    ///
    /// - Parameters:
    ///   - cell: The pressed cell along this edge.
    ///   - grab: Set to the pointer's offset within the thumb when the thumb
    ///     was hit, so a drag does not jump the thumb under the cursor.
    /// - Returns: The offset to scroll to.
    public func offset(forPress cell: Int, grab: inout Int?) -> Int {
        let (thumbStart, thumbLength) = thumb

        if hasArrows, cell == start {
            return span.offset - 1
        }

        if hasArrows, cell == start + length - 1 {
            return span.offset + 1
        }

        if cell >= thumbStart, cell < thumbStart + thumbLength {
            grab = cell - thumbStart
            return span.offset
        }

        // A page keeps ONE line of context, so you can see where you were —
        // `viewport`, not `viewport - 1`, was an off-by-one the existing
        // border-scrollbar tests caught the moment this maths was shared.
        let page = max(1, span.viewport - 1)

        grab = nil
        return cell < thumbStart ? span.offset - page : span.offset + page
    }
}

public extension ScrollbarRun {
    /// Draws this run: track, thumb, and end arrows when it has them.
    ///
    /// **The** scrollbar painter. Before this there were six — `Panel`,
    /// `ScrollView`, `ListView`, `TextView`, `SyntaxTextView`,
    /// `MarkdownView`, plus `CodeEditorView` — each with its own thumb maths
    /// and its own idea of whether a bar wears arrows. They drifted exactly
    /// as you would expect: the border-embedded pair grew arrows, paging and
    /// drag handling, and the interior ones stayed a bare proportional block,
    /// so a Find results list beside an editor looked like a different app.
    ///
    /// - Parameters:
    ///   - painter: Where to draw.
    ///   - vertical: `true` for a bar down an edge, `false` for one across.
    ///   - position: The fixed coordinate — the column for a vertical bar,
    ///     the row for a horizontal one.
    ///   - track: Style for the groove.
    ///   - thumb: Style for the thumb.
    @MainActor
    func draw(
        in painter: Painter,
        vertical: Bool,
        at position: Int,
        track: CellStyle,
        thumb: CellStyle
    ) {
        guard length > 0 else {
            return
        }

        let (thumbStart, thumbLength) = self.thumb

        for cell in start..<(start + length) {
            let inThumb = cell >= thumbStart && cell < thumbStart + thumbLength
            let point = vertical ? Point(x: position, y: cell) : Point(x: cell, y: position)
            painter.set(TerminalCell(character: " ", style: inThumb ? thumb : track), at: point)
        }

        guard hasArrows else {
            return
        }

        // Arrow glyphs read against the track: the thumb's colour on the
        // track's ground, so they stay legible whichever end the thumb is at.
        var arrow = track
        arrow.foreground = thumb.background == .standard ? track.foreground : thumb.background

        let first = vertical ? Point(x: position, y: start) : Point(x: start, y: position)
        let last = vertical
            ? Point(x: position, y: start + length - 1)
            : Point(x: start + length - 1, y: position)

        painter.set(TerminalCell(character: vertical ? "▴" : "◂", style: arrow), at: first)
        painter.set(TerminalCell(character: vertical ? "▾" : "▸", style: arrow), at: last)
    }
}
