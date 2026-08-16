/// Viewport onto a document view larger than the visible area.
///
/// The scroll view owns the offset, the scroll keys, the wheel, and the
/// indicator bars; the document view is an ordinary `TUIView` laid out at its
/// full content size and translated by the offset. Clipping needs no special
/// handling — the painter's clipping contract already guarantees the
/// document cannot draw outside the viewport.
///
/// ```text
///   ┌ScrollView────────────┬─┐
///   │ visible part of the  │█│  ← vertical indicator
///   │ document view        │░│
///   ├──────────────────────┼─┤
///   │ ██████░░░░░░░░░░░░░░ │ │  ← horizontal indicator
///   └──────────────────────┴─┘
/// ```
///
/// ```swift
/// let scroll = ScrollView(document: longForm)
/// scroll.onOffsetChanged = { offset in statusBar.show(offset) }
/// ```
///
/// Arrows scroll by one cell, PageUp/PageDown by a viewport page, Home/End
/// jump to the top/bottom; the wheel scrolls vertically without focus. The
/// indicator bars are live: clicking the track pages toward the click, and
/// the thumb drags (the window's mouse capture keeps the drag alive even
/// when the pointer leaves the one-cell bar).
@MainActor
public final class ScrollView: TUIView {
    /// The scrolled content, laid out at its full content size.
    ///
    /// Setting a new document replaces the previous one and resets the
    /// offset to zero.
    public var documentView: TUIView? {
        didSet {
            oldValue?.removeFromSuperview()

            if let documentView {
                viewport.addSubview(documentView)
            }

            offset = .zero
            setNeedsLayout()
        }
    }

    /// Called when the offset changes through interaction or
    /// `setOffset(_:notify:)`.
    public var onOffsetChanged: (Point) -> Void = { _ in }

    /// Whether indicator bars appear when the document overflows.
    public var showsIndicators = true {
        didSet {
            if showsIndicators != oldValue {
                setNeedsLayout()
            }
        }
    }

    /// Sizes the document's width to the viewport (vertical-only
    /// scrolling) — the right mode for forms and text that should reflow
    /// to the screen instead of scrolling sideways.
    public var fitsDocumentWidth = false {
        didSet {
            if fitsDocumentWidth != oldValue {
                setNeedsLayout()
            }
        }
    }

    // Clip container for the document; its frame is the visible viewport,
    // excluding any indicator bars.
    private let viewport = TUIView()

    // Current scroll offset in cells (top-left of the visible region).
    private var offset: Point = .zero

    // In-flight thumb drag, when any: which bar, and where inside the thumb
    // the press landed (so the thumb doesn't jump under the pointer).
    private enum BarDrag {
        case vertical(grabOffset: Int)
        case horizontal(grabOffset: Int)
    }

    private var activeDrag: BarDrag?

    /// Creates a scroll view.
    ///
    /// - Parameter document: The content view to scroll, when already known.
    public init(document: TUIView? = nil) {
        super.init(frame: .zero)
        addSubview(viewport)

        if let document {
            documentView = document
            viewport.addSubview(document)
        }
    }

    /// Current scroll offset in cells.
    public var contentOffset: Point {
        offset
    }

    /// The document's resolved size in cells.
    public var contentSize: Size {
        guard let documentView else {
            return .zero
        }

        return documentView.intrinsicContentSize ?? documentView.frame.size
    }

    /// Scroll views take keyboard focus to own the scroll keys.
    public override var acceptsFirstResponder: Bool {
        true
    }

    /// Sets the offset programmatically, clamped to the scrollable range.
    ///
    /// - Parameters:
    ///   - newOffset: Desired offset in cells.
    ///   - notify: Whether `onOffsetChanged` fires. Defaults to silent.
    public func setOffset(_ newOffset: Point, notify: Bool = false) {
        let clamped = clampedOffset(newOffset)

        guard clamped != offset else {
            return
        }

        offset = clamped
        setNeedsLayout()

        if notify {
            onOffsetChanged(offset)
        }
    }

    /// Positions the viewport and document, reserving indicator bars.
    public override func layoutSubviews() {
        let content = contentSize

        // An overflowing axis reserves a bar, which shrinks the viewport,
        // which can make the other axis overflow — resolve in two passes.
        // (Width-fitted documents never overflow horizontally.)
        var needsVBar = false
        var needsHBar = false

        if showsIndicators {
            if fitsDocumentWidth {
                needsVBar = content.height > bounds.size.height
            } else {
                for _ in 0..<2 {
                    needsVBar = content.height > bounds.size.height - (needsHBar ? 1 : 0)
                    needsHBar = content.width > bounds.size.width - (needsVBar ? 1 : 0)
                }
            }
        }

        viewport.frame = Rect(
            x: 0,
            y: 0,
            width: max(0, bounds.size.width - (needsVBar ? 1 : 0)),
            height: max(0, bounds.size.height - (needsHBar ? 1 : 0))
        )

        offset = clampedOffset(offset)
        documentView?.frame = Rect(origin: .zero - offset, size: resolvedContentSize)
    }

    /// Draws the indicator bars in the reserved column and row.
    public override func draw(_ painter: Painter) {
        if let bar = verticalBar {
            drawBar(painter, bar, vertical: true, at: bounds.size.width - 1)
        }

        if let bar = horizontalBar {
            drawBar(painter, bar, vertical: false, at: bounds.size.height - 1)
        }
    }

    /// Scroll keys: arrows, PageUp/PageDown, Home/End.
    public override func keyDown(_ key: KeyInput) -> Bool {
        guard key.modifiers.isEmpty else {
            return false
        }

        let page = max(1, viewport.frame.size.height - 1)

        switch key.key {
        case .up:
            return scroll(by: Point(x: 0, y: -1))

        case .down:
            return scroll(by: Point(x: 0, y: 1))

        case .left:
            return scroll(by: Point(x: -1, y: 0))

        case .right:
            return scroll(by: Point(x: 1, y: 0))

        case .pageUp:
            return scroll(by: Point(x: 0, y: -page))

        case .pageDown:
            return scroll(by: Point(x: 0, y: page))

        case .home:
            return scroll(to: Point(x: offset.x, y: 0))

        case .end:
            return scroll(to: Point(x: offset.x, y: contentSize.height))

        default:
            return false
        }
    }

    /// The wheel scrolls vertically; presses and drags operate the bars.
    public override func mouseEvent(_ mouse: MouseInput) -> Bool {
        switch mouse.action {
        case .scrollUp:
            return scroll(by: Point(x: 0, y: -1))

        case .scrollDown:
            return scroll(by: Point(x: 0, y: 1))

        case .press where mouse.button == .left:
            return beginBarGesture(at: mouse.position)

        case .drag:
            return continueBarDrag(to: mouse.position)

        case .release:
            guard activeDrag != nil else {
                return false
            }

            activeDrag = nil
            return true

        default:
            return false
        }
    }

    // MARK: - Scrolling internals

    // Scrolls by a delta; reports whether the event was consumed (scroll
    // keys are consumed even at the edge so they never leak upward as
    // navigation).
    @discardableResult
    private func scroll(by delta: Point) -> Bool {
        scroll(to: offset + delta)
    }

    @discardableResult
    private func scroll(to target: Point) -> Bool {
        let clamped = clampedOffset(target)

        if clamped != offset {
            offset = clamped
            setNeedsLayout()
            onOffsetChanged(offset)
        }

        return true
    }

    // Content size after width fitting.
    private var resolvedContentSize: Size {
        var size = contentSize

        if fitsDocumentWidth {
            size.width = viewport.frame.size.width
        }

        return size
    }

    private func clampedOffset(_ candidate: Point) -> Point {
        let content = resolvedContentSize
        let visible = viewport.frame.size

        return Point(
            x: max(0, min(candidate.x, max(0, content.width - visible.width))),
            y: max(0, min(candidate.y, max(0, content.height - visible.height)))
        )
    }

    // MARK: - Indicator bars

    // `ScrollbarRun` carries the geometry now — including the rounded,
    // two-cell-minimum thumb rule that started here and was the best of the
    // six implementations, so it became the shared one.

    // The vertical bar's geometry, when it is visible.
    private var verticalBar: ScrollbarRun? {
        let visible = viewport.frame.size

        guard showsIndicators,
              visible.height > 0,
              contentSize.height > visible.height,
              bounds.size.width > visible.width else {
            return nil
        }

        return ScrollbarRun(
            start: 0,
            length: visible.height,
            span: ScrollSpan(offset: offset.y, viewport: visible.height, content: contentSize.height)
        )
    }

    // The horizontal bar's geometry, when it is visible.
    private var horizontalBar: ScrollbarRun? {
        let visible = viewport.frame.size

        guard showsIndicators,
              visible.width > 0,
              resolvedContentSize.width > visible.width,
              bounds.size.height > visible.height else {
            return nil
        }

        return ScrollbarRun(
            start: 0,
            length: visible.width,
            span: ScrollSpan(offset: offset.x, viewport: visible.width, content: resolvedContentSize.width)
        )
    }

    // Draws one indicator bar through the shared painter.
    private func drawBar(_ painter: Painter, _ bar: ScrollbarRun, vertical: Bool, at position: Int) {
        let (trackStyle, thumbStyle) = ScrollView.indicatorStyles(
            for: effectiveTheme,
            focused: isFirstResponder
        )

        bar.draw(in: painter, vertical: vertical, at: position, track: trackStyle, thumb: thumbStyle)
    }

    // Solid indicator cells from the theme's scrollbar slot: track from its
    // background, thumb from its foreground (accent while focused). A
    // colorless slot falls back to video-attribute blocks.
    static func indicatorStyles(for theme: ResolvedTheme, focused: Bool) -> (track: CellStyle, thumb: CellStyle) {
        let slot = theme.scrollbar

        guard slot.foreground != .standard, slot.background != .standard else {
            var track = theme.border
            track.flags.insert(.inverse)
            track.flags.insert(.dim)

            var thumb = theme.border
            thumb.flags.insert(.inverse)

            if focused {
                thumb.flags.insert(.bold)
            }

            return (track, thumb)
        }

        let track = CellStyle(background: slot.background)
        let thumb = CellStyle(background: focused ? theme.accent : slot.foreground)
        return (track, thumb)
    }

    // A press on a bar either grabs the thumb (starting a drag) or pages
    // toward the click. Presses anywhere else are not the scroll view's.
    private func beginBarGesture(at position: Point) -> Bool {
        if let bar = verticalBar, position.x == bounds.size.width - 1, position.y < bar.length {
            var grab: Int?
            let target = bar.offset(forPress: position.y, grab: &grab)
            activeDrag = grab.map { .vertical(grabOffset: $0) }
            scroll(by: Point(x: 0, y: target - offset.y))
            return true
        }

        if let bar = horizontalBar, position.y == bounds.size.height - 1, position.x < bar.length {
            var grab: Int?
            let target = bar.offset(forPress: position.x, grab: &grab)
            activeDrag = grab.map { .horizontal(grabOffset: $0) }
            scroll(by: Point(x: target - offset.x, y: 0))
            return true
        }

        return false
    }

    // Moves the thumb with the pointer, mapping its cell back to an offset.
    private func continueBarDrag(to position: Point) -> Bool {
        switch activeDrag {
        case .vertical(let grabOffset):
            guard let bar = verticalBar else {
                return false
            }

            return scroll(to: Point(x: offset.x, y: bar.offset(forThumbStart: position.y - grabOffset)))

        case .horizontal(let grabOffset):
            guard let bar = horizontalBar else {
                return false
            }

            return scroll(to: Point(x: bar.offset(forThumbStart: position.x - grabOffset), y: offset.y))

        case nil:
            return false
        }
    }
}
