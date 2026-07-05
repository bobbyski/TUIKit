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
