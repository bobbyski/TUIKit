/// The scroll bar as its own control, for driving something else.
///
/// ```text
///   ▴            a vertical scroller beside a view that scrolls itself
///   █
///   █
///   ░
///   ▾
/// ```
///
/// `ScrollView` draws its own bars; this one stands alone — beside a table
/// that manages its own rows, under a timeline, anywhere the app owns the
/// scrolling. Give it a `ScrollSpan` (offset, viewport, content) and it
/// reports `onScroll` with a new offset when the thumb is dragged, the track
/// clicked, an arrow pressed, or the wheel turned over it. Same glyph rules
/// as the framework's other bars, from `ScrollbarRun`.
///
/// ```swift
/// let bar = Scroller(axis: .vertical)
/// bar.span = ScrollSpan(offset: 0, viewport: 20, content: rows.count)
/// bar.onScroll = { offset in table.scrollOffset = offset }
/// ```
@MainActor
public final class Scroller: TUIView {
    /// Down an edge, or along one.
    public let axis: StackView.Axis

    /// What is being scrolled.
    public var span: ScrollSpan {
        didSet {
            if span != oldValue {
                setNeedsDisplay()
            }
        }
    }

    /// Called with the new offset after interaction.
    public var onScroll: (Int) -> Void = { _ in }

    // Thumb grab offset during a drag.
    private var grab: Int?

    /// Creates a scroller.
    ///
    /// - Parameters:
    ///   - axis: Vertical (the default) or horizontal.
    ///   - span: Initial span.
    public init(axis: StackView.Axis = .vertical, span: ScrollSpan = ScrollSpan(offset: 0, viewport: 1, content: 1)) {
        self.axis = axis
        self.span = span
        super.init(frame: .zero)
    }

    /// One cell thick.
    public override var intrinsicContentSize: Size? {
        axis == .vertical ? Size(width: 1, height: 8) : Size(width: 16, height: 1)
    }

    /// Sets the offset programmatically, clamped. Reports nothing.
    ///
    /// - Parameter offset: The new offset.
    public func setOffset(_ offset: Int) {
        span.offset = min(max(0, offset), max(0, span.content - span.viewport))
    }

    private var run: ScrollbarRun {
        ScrollbarRun(start: 0, length: axis == .vertical ? bounds.size.height : bounds.size.width, span: span)
    }

    /// Draws the track, thumb and arrows in the theme's scrollbar slot.
    public override func draw(_ painter: Painter) {
        let theme = effectiveTheme
        let resolved = ScrollView.indicatorStyles(for: theme, focused: isFirstResponder)
        var thumb = theme.scrollbar
        thumb.background = resolved.thumb.background
        var track = theme.scrollbar
        track.background = resolved.track.background
        run.draw(in: painter, vertical: axis == .vertical, at: 0, track: track, thumb: thumb)
    }

    /// Press on the track or arrows, drag the thumb, or turn the wheel.
    public override func mouseEvent(_ mouse: MouseInput) -> Bool {
        let cell = axis == .vertical ? mouse.position.y : mouse.position.x

        switch mouse.action {
        case .press where mouse.button == .left:
            var grabbed: Int?
            let offset = run.offset(forPress: cell, grab: &grabbed)
            grab = grabbed
            scroll(to: offset)
            return true

        case .drag:
            if let grab {
                scroll(to: run.offset(forThumbStart: cell - grab))
            }
            return true

        case .release:
            grab = nil
            return true

        case .scrollUp:
            scroll(to: span.offset - 1)
            return true

        case .scrollDown:
            scroll(to: span.offset + 1)
            return true

        default:
            return false
        }
    }

    private func scroll(to offset: Int) {
        let clamped = min(max(0, offset), max(0, span.content - span.viewport))

        guard clamped != span.offset else {
            return
        }

        span.offset = clamped
        setNeedsDisplay()
        onScroll(clamped)
    }
}
