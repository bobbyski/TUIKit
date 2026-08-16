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

    /// Creates a run.
    public init(start: Int, length: Int, span: ScrollSpan, hasArrows: Bool) {
        self.start = start
        self.length = length
        self.span = span
        self.hasArrows = hasArrows
    }

    /// Track region (between the arrows, or the whole run without them).
    public var trackStart: Int { start + (hasArrows ? 1 : 0) }

    /// Cells of track.
    public var trackLength: Int { length - (hasArrows ? 2 : 0) }

    /// Thumb start/length within the track — proportional, always ≥ 1.
    public var thumb: (start: Int, length: Int) {
        let n = trackLength
        let length = max(1, min(n, n * span.viewport / max(1, span.content)))
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
