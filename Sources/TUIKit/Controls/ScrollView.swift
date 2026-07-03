/// Viewport onto a document view larger than the visible area.
///
/// The scroll view owns the offset, the scroll keys, the wheel, and the
/// indicator bars; the document view is an ordinary `View` laid out at its
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
/// jump to the top/bottom; the wheel scrolls vertically without focus.
@MainActor
public final class ScrollView: View {
    /// The scrolled content, laid out at its full content size.
    ///
    /// Setting a new document replaces the previous one and resets the
    /// offset to zero.
    public var documentView: View? {
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

    // Clip container for the document; its frame is the visible viewport,
    // excluding any indicator bars.
    private let viewport = View()

    // Current scroll offset in cells (top-left of the visible region).
    private var offset: Point = .zero

    /// Creates a scroll view.
    ///
    /// - Parameter document: The content view to scroll, when already known.
    public init(document: View? = nil) {
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
        var needsVBar = false
        var needsHBar = false

        if showsIndicators {
            for _ in 0..<2 {
                needsVBar = content.height > bounds.size.height - (needsHBar ? 1 : 0)
                needsHBar = content.width > bounds.size.width - (needsVBar ? 1 : 0)
            }
        }

        viewport.frame = Rect(
            x: 0,
            y: 0,
            width: max(0, bounds.size.width - (needsVBar ? 1 : 0)),
            height: max(0, bounds.size.height - (needsHBar ? 1 : 0))
        )

        offset = clampedOffset(offset)
        documentView?.frame = Rect(origin: .zero - offset, size: content)
    }

    /// Draws the indicator bars in the reserved column and row.
    public override func draw(_ painter: Painter) {
        guard showsIndicators else {
            return
        }

        let content = contentSize
        let visible = viewport.frame.size

        if content.height > visible.height, bounds.size.width > visible.width {
            drawBar(
                painter,
                along: visible.height,
                content: content.height,
                offset: offset.y,
                at: { position in Point(x: bounds.size.width - 1, y: position) }
            )
        }

        if content.width > visible.width, bounds.size.height > visible.height {
            drawBar(
                painter,
                along: visible.width,
                content: content.width,
                offset: offset.x,
                at: { position in Point(x: position, y: bounds.size.height - 1) }
            )
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

    /// The wheel scrolls vertically, focused or not.
    public override func mouseEvent(_ mouse: MouseInput) -> Bool {
        switch mouse.action {
        case .scrollUp:
            return scroll(by: Point(x: 0, y: -1))

        case .scrollDown:
            return scroll(by: Point(x: 0, y: 1))

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

    private func clampedOffset(_ candidate: Point) -> Point {
        let content = contentSize
        let visible = viewport.frame.size

        return Point(
            x: max(0, min(candidate.x, max(0, content.width - visible.width))),
            y: max(0, min(candidate.y, max(0, content.height - visible.height)))
        )
    }

    // Draws one indicator bar: a track of ░ with a proportional █ thumb.
    private func drawBar(
        _ painter: Painter,
        along length: Int,
        content: Int,
        offset: Int,
        at position: (Int) -> Point
    ) {
        guard length > 0, content > length else {
            return
        }

        let thumbLength = max(1, length * length / content)
        let maxOffset = content - length
        let maxThumbStart = length - thumbLength
        let thumbStart = maxOffset > 0 ? offset * maxThumbStart / maxOffset : 0
        let style = CellStyle(flags: isFirstResponder ? .bold : [])

        for cell in 0..<length {
            let inThumb = cell >= thumbStart && cell < thumbStart + thumbLength
            let character: Character = inThumb ? "█" : "░"
            painter.set(TerminalCell(character: character, style: style), at: position(cell))
        }
    }
}
