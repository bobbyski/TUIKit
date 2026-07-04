/// Bordered, titled container — the standard TUIKit chrome.
///
/// A panel draws a single-line box with its title in the top border and
/// keeps application content inside `content`, which is inset by the
/// border. Add subviews to `content`, never to the panel itself:
///
/// ```swift
/// let panel = Panel("Inspector")
/// panel.content.addSubview(form)      // form fills inside the border
/// ```
///
/// ```text
///   ┌ Inspector ─────────[x]┐
///   │ (content view area)   │
///   └───────────────────────┘
/// ```
///
/// The optional close button emits `onClose`; the panel never removes
/// itself — the application decides what closing means.
@MainActor
public final class Panel: TUIView {
    /// Title shown in the top border.
    public var title: String {
        didSet {
            if title != oldValue {
                setNeedsDisplay()
            }
        }
    }

    /// Whether `[x]` appears in the top-right border.
    public var showsCloseButton = false {
        didSet {
            if showsCloseButton != oldValue {
                setNeedsDisplay()
            }
        }
    }

    /// Called when the close button is clicked.
    public var onClose: () -> Void = {}

    /// Whether a maximize/restore box appears in the top border, left of `[x]`.
    public var showsMaximizeButton = false {
        didSet {
            if showsMaximizeButton != oldValue {
                setNeedsDisplay()
            }
        }
    }

    /// Drives the maximize box glyph: `[+]` when normal, `[=]` when maximized.
    public var isMaximized = false {
        didSet {
            if isMaximized != oldValue {
                setNeedsDisplay()
            }
        }
    }

    /// Called when the maximize/restore box is clicked.
    public var onMaximize: () -> Void = {}

    /// Whether the bottom-right corner renders as a resize handle (`◢`).
    ///
    /// Visual only — `FloatingWindow` owns the actual resize interaction.
    public var showsResizeHandle = false {
        didSet {
            if showsResizeHandle != oldValue {
                setNeedsDisplay()
            }
        }
    }

    /// Container for application content, inset by the border.
    public let content = TUIView()

    // MARK: - Border-embedded scrollbars (Borland-style)

    /// The view whose scrolling the border mirrors, when any.
    public private(set) weak var scrollClient: BorderScrollable?

    // How far each embedded bar runs along its edge.
    private var verticalBarExtent: BorderScrollbarExtent = .fullEdge
    private var horizontalBarExtent: BorderScrollbarExtent = .underClient

    // In-flight thumb drags: pointer offset within the thumb at the grab.
    private var verticalBarGrab: Int?
    private var horizontalBarGrab: Int?

    /// Embeds a view's scrollbars into this panel's border: the vertical bar
    /// rides the right border, the horizontal bar the bottom border, and the
    /// view stops drawing its own interior indicators. Pass `nil` to return
    /// the border to plain chrome (the previous client draws its own again).
    ///
    /// - Parameters:
    ///   - client: The scrollable view (a `content` descendant), or `nil`.
    ///   - vertical: Run of the right-border bar. Defaults to the full edge.
    ///   - horizontal: Run of the bottom bar. Defaults to the client's own
    ///     width, so it sits under the text and not a sidebar.
    public func embedScrollbars(
        for client: BorderScrollable?,
        vertical: BorderScrollbarExtent = .fullEdge,
        horizontal: BorderScrollbarExtent = .underClient
    ) {
        if let previous = scrollClient, previous !== client {
            previous.showsOwnScrollbars = true
        }

        scrollClient = client
        client?.showsOwnScrollbars = false
        verticalBarExtent = vertical
        horizontalBarExtent = horizontal
        setNeedsDisplay()
    }

    /// Creates a panel.
    ///
    /// - Parameter title: Title shown in the top border.
    public init(_ title: String = "") {
        self.title = title
        super.init(frame: .zero)
        addSubview(content)
    }

    /// Positions the content view inside the border.
    public override func layoutSubviews() {
        content.frame = Rect(
            x: 1,
            y: 1,
            width: max(0, bounds.size.width - 2),
            height: max(0, bounds.size.height - 2)
        )
    }

    /// Draws the background, border, title, and close button.
    public override func draw(_ painter: Painter) {
        let theme = effectiveTheme

        painter.fill(bounds, with: .blank)
        painter.drawBox(bounds, style: theme.border, border: theme.borderStyle)

        let width = bounds.size.width

        // Reserve the right-hand border for the buttons: [x] alone, or the
        // maximize box plus [x].
        let reserved = showsMaximizeButton ? 10 : 6

        if !title.isEmpty, width > reserved {
            let text = " " + Label.truncated(title, width: width - reserved) + " "
            painter.write(text, at: Point(x: 2, y: 0), style: theme.header)
        }

        if showsMaximizeButton, width >= 11 {
            painter.write(isMaximized ? "[=]" : "[+]", at: Point(x: maximizeButtonX, y: 0), style: theme.border)
        }

        if showsCloseButton, width >= 7 {
            painter.write("[x]", at: Point(x: closeButtonX, y: 0), style: theme.border)
        }

        if showsResizeHandle, width >= 2, bounds.size.height >= 2 {
            painter.write(
                "◢",
                at: Point(x: width - 1, y: bounds.size.height - 1),
                style: theme.border
            )
        }

        drawDividerJunctions(painter, theme: theme)
        drawEmbeddedScrollbars(painter, theme: theme)
    }

    // Joins connected dividers anywhere in the content subtree that reach
    // the content edges into this panel's border with tee junctions, so
    // divided layouts read as one piece of chrome.
    private func drawDividerJunctions(_ painter: Painter, theme: ResolvedTheme) {
        // Only weld when the theme asks for it.
        guard theme.dividerConnection == .welded else {
            return
        }

        // The tee welds the interior line (`dividerStyle` — the nub) into the
        // frame (`borderStyle`), e.g. a single divider into a double frame → ╟.
        let frame = theme.borderStyle
        let nub = theme.dividerStyle
        let contentSize = content.frame.size

        func visit(_ view: TUIView, offset: Point) {
            for subview in view.subviews where !subview.isHidden {
                if let divider = subview as? Divider, divider.isConnected {
                    join(divider, at: offset + divider.frame.origin)
                } else {
                    visit(subview, offset: offset + subview.frame.origin)
                }
            }
        }

        // `origin` is the divider's position in content coordinates.
        func join(_ divider: Divider, at origin: Point) {
            switch divider.axis {
            case .horizontal:
                let y = origin.y + 1   // content is inset by 1

                if origin.x <= 0, let glyph = frame.tee(.left, nub: nub) {
                    painter.set(TerminalCell(character: glyph, style: theme.border), at: Point(x: 0, y: y))
                }

                if origin.x + divider.frame.size.width >= contentSize.width, let glyph = frame.tee(.right, nub: nub) {
                    painter.set(TerminalCell(character: glyph, style: theme.border), at: Point(x: bounds.size.width - 1, y: y))
                }

            case .vertical:
                let x = origin.x + 1

                if origin.y <= 0, let glyph = frame.tee(.top, nub: nub) {
                    painter.set(TerminalCell(character: glyph, style: theme.border), at: Point(x: x, y: 0))
                }

                if origin.y + divider.frame.size.height >= contentSize.height, let glyph = frame.tee(.bottom, nub: nub) {
                    painter.set(TerminalCell(character: glyph, style: theme.border), at: Point(x: x, y: bounds.size.height - 1))
                }
            }
        }

        visit(content, offset: .zero)
    }

    // MARK: - Embedded scrollbar geometry & drawing

    // One embedded bar, in border cells: `start..<start+length` along its edge
    // (rows for vertical, columns for horizontal), with arrow endpoints when
    // the run is long enough, and the thumb inside the track between them.
    private struct BarRun {
        var start: Int
        var length: Int
        var span: ScrollSpan
        var hasArrows: Bool

        // Track region (between the arrows, or the whole run without them).
        var trackStart: Int { start + (hasArrows ? 1 : 0) }
        var trackLength: Int { length - (hasArrows ? 2 : 0) }

        // Thumb start/length within the track — proportional, always ≥ 1.
        var thumb: (start: Int, length: Int) {
            let n = trackLength
            let length = max(1, min(n, n * span.viewport / max(1, span.content)))
            let maxStart = max(0, n - length)
            let start = span.maxOffset > 0
                ? min(maxStart, span.offset * maxStart / max(1, span.maxOffset))
                : 0
            return (trackStart + start, length)
        }

        // Maps a track cell back to a scroll offset (for thumb drags).
        func offset(forThumbStart start: Int) -> Int {
            let maxStart = max(0, trackLength - thumb.length)
            let clamped = min(max(0, start - trackStart), maxStart)
            return maxStart > 0 ? clamped * span.maxOffset / maxStart : 0
        }
    }

    // The client's frame in panel coordinates, or nil when it isn't a visible
    // descendant of `content` (e.g. it sits in a hidden tab).
    private func clientFrameInPanel() -> Rect? {
        guard let client = scrollClient else {
            return nil
        }

        var origin = Point.zero
        var current: TUIView? = client

        while let view = current, view !== self {
            if view.isHidden {
                return nil
            }

            origin = origin + view.frame.origin
            current = view.superview
        }

        guard current === self else {
            return nil
        }

        return Rect(origin: origin, size: client.frame.size)
    }

    // The right-border bar's run, or nil when the client has no vertical axis.
    // A span that *fits* still gets a bar — embedded bars are permanent chrome
    // (the Borland look); the thumb just fills the track.
    private func verticalBarRun() -> BarRun? {
        guard let span = scrollClient?.verticalScrollSpan, span.viewport > 0 else {
            return nil
        }

        // The full edge between the corners.
        var start = 1
        var end = bounds.size.height - 1

        if verticalBarExtent == .underClient, let frame = clientFrameInPanel() {
            start = max(start, frame.origin.y)
            end = min(end, frame.origin.y + frame.size.height)
        }

        let length = end - start

        guard length >= 2 else {
            return nil
        }

        return BarRun(start: start, length: length, span: span, hasArrows: length >= 4)
    }

    // The bottom-border bar's run, or nil when the client has no horizontal
    // axis. Permanent chrome, like the vertical bar.
    private func horizontalBarRun() -> BarRun? {
        guard let span = scrollClient?.horizontalScrollSpan, span.viewport > 0 else {
            return nil
        }

        var start = 1
        var end = bounds.size.width - 1

        if horizontalBarExtent == .underClient, let frame = clientFrameInPanel() {
            start = max(start, frame.origin.x)
            end = min(end, frame.origin.x + frame.size.width)
        }

        let length = end - start

        guard length >= 2 else {
            return nil
        }

        return BarRun(start: start, length: length, span: span, hasArrows: length >= 4)
    }

    // Paints both embedded bars over the border (after junctions, so a bar
    // owns its cells). Solid track/thumb colors; small triangle endpoints
    // scroll by one line/column.
    private func drawEmbeddedScrollbars(_ painter: Painter, theme: ResolvedTheme) {
        let focused = (scrollClient as TUIView?)?.isFirstResponder ?? false
        let (track, thumb) = ScrollView.indicatorStyles(for: theme, focused: focused)

        var arrow = track
        arrow.foreground = thumb.background == .standard ? track.foreground : thumb.background

        if let run = verticalBarRun() {
            let column = bounds.size.width - 1
            let (thumbStart, thumbLength) = run.thumb

            for y in run.start..<(run.start + run.length) {
                let inThumb = y >= thumbStart && y < thumbStart + thumbLength
                painter.set(TerminalCell(character: " ", style: inThumb ? thumb : track), at: Point(x: column, y: y))
            }

            if run.hasArrows {
                painter.set(TerminalCell(character: "▴", style: arrow), at: Point(x: column, y: run.start))
                painter.set(TerminalCell(character: "▾", style: arrow), at: Point(x: column, y: run.start + run.length - 1))
            }
        }

        if let run = horizontalBarRun() {
            let row = bounds.size.height - 1
            let (thumbStart, thumbLength) = run.thumb

            for x in run.start..<(run.start + run.length) {
                let inThumb = x >= thumbStart && x < thumbStart + thumbLength
                painter.set(TerminalCell(character: " ", style: inThumb ? thumb : track), at: Point(x: x, y: row))
            }

            if run.hasArrows {
                painter.set(TerminalCell(character: "◂", style: arrow), at: Point(x: run.start, y: row))
                painter.set(TerminalCell(character: "▸", style: arrow), at: Point(x: run.start + run.length - 1, y: row))
            }
        }
    }

    // A press on an embedded bar: arrows step by one, the track pages toward
    // the press, the thumb starts a drag.
    private func pressEmbeddedBar(at point: Point) -> Bool {
        if point.x == bounds.size.width - 1, let run = verticalBarRun(),
           point.y >= run.start, point.y < run.start + run.length {
            scrollVertically(to: targetOffset(for: point.y, in: run, grab: &verticalBarGrab))
            return true
        }

        if point.y == bounds.size.height - 1, let run = horizontalBarRun(),
           point.x >= run.start, point.x < run.start + run.length {
            scrollHorizontally(to: targetOffset(for: point.x, in: run, grab: &horizontalBarGrab))
            return true
        }

        return false
    }

    // Shared press logic for one axis; sets `grab` when the thumb was hit.
    private func targetOffset(for cell: Int, in run: BarRun, grab: inout Int?) -> Int {
        let (thumbStart, thumbLength) = run.thumb

        if run.hasArrows, cell == run.start {
            return run.span.offset - 1
        }

        if run.hasArrows, cell == run.start + run.length - 1 {
            return run.span.offset + 1
        }

        if cell >= thumbStart, cell < thumbStart + thumbLength {
            grab = cell - thumbStart
            return run.span.offset
        }

        let page = max(1, run.span.viewport - 1)
        return run.span.offset + (cell < thumbStart ? -page : page)
    }

    private func scrollVertically(to offset: Int) {
        guard let client = scrollClient, let span = client.verticalScrollSpan else {
            return
        }

        client.setScrollOffset(vertical: min(span.maxOffset, max(0, offset)))
        setNeedsDisplay()
    }

    private func scrollHorizontally(to offset: Int) {
        guard let client = scrollClient, let span = client.horizontalScrollSpan else {
            return
        }

        client.setScrollOffset(horizontal: min(span.maxOffset, max(0, offset)))
        setNeedsDisplay()
    }

    /// Click on `[x]` closes; click on `[+]`/`[=]` maximizes/restores; presses
    /// and drags on an embedded border scrollbar scroll its client.
    public override func mouseEvent(_ mouse: MouseInput) -> Bool {
        switch mouse.action {
        case .press where mouse.button == .left:
            if mouse.position.y == 0 {
                if showsCloseButton, mouse.position.x >= closeButtonX, mouse.position.x < closeButtonX + 3 {
                    onClose()
                    return true
                }

                if showsMaximizeButton, mouse.position.x >= maximizeButtonX, mouse.position.x < maximizeButtonX + 3 {
                    onMaximize()
                    return true
                }

                return false   // the title row is the window's (drag-to-move)
            }

            return pressEmbeddedBar(at: mouse.position)

        case .drag:
            if let grab = verticalBarGrab, let run = verticalBarRun() {
                scrollVertically(to: run.offset(forThumbStart: mouse.position.y - grab))
                return true
            }

            if let grab = horizontalBarGrab, let run = horizontalBarRun() {
                scrollHorizontally(to: run.offset(forThumbStart: mouse.position.x - grab))
                return true
            }

            return false

        case .release where verticalBarGrab != nil || horizontalBarGrab != nil:
            verticalBarGrab = nil
            horizontalBarGrab = nil
            return true

        default:
            return false
        }
    }

    // Leading cell of the [x] affordance in the top border.
    private var closeButtonX: Int {
        bounds.size.width - 4
    }

    // Leading cell of the maximize box, one gap left of [x].
    private var maximizeButtonX: Int {
        bounds.size.width - 8
    }
}
