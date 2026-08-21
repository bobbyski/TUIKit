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

    /// Border variant to draw, overriding the theme's `borderStyle`.
    ///
    /// `nil` (the default) follows the theme by the house rule: a panel
    /// that IS a window's chrome draws the theme's `borderStyle` (Turbo's
    /// double frame), while a panel nested inside a window — a group box —
    /// draws its `inner` weight (single). Set it to pin a specific look.
    public var borderStyleOverride: BorderStyle? {
        didSet {
            if borderStyleOverride != oldValue {
                setNeedsDisplay()
            }
        }
    }

    /// Container for application content, inset by the border.
    public let content = TUIView()

    // Whether this panel is a window's chrome (set by FloatingWindow and
    // Dialog). Only window chrome wears the Phase 10 vector titlebar —
    // inner panels (group boxes) keep their cell borders even on a VTG
    // terminal.
    var isWindowChrome = false

    // The border weight actually drawn: the override, else the theme's
    // frame for a panel that IS a window's frame — declared chrome, or
    // sitting directly in a Window — and its inner weight for panels nested
    // anywhere deeper (group boxes).
    func frameStyle(_ theme: ResolvedTheme) -> BorderStyle {
        if let borderStyleOverride {
            return borderStyleOverride
        }

        let isWindowFrame = isWindowChrome || superview is Window
        return isWindowFrame ? theme.borderStyle : theme.borderStyle.inner
    }

    // Whether the last draw rendered the vector titlebar, and with which
    // button side — cached so hit-testing agrees with what is on screen.
    private var chromeTitleBarActive = false
    private var chromeButtonsLeading = false

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

    /// A small button drawn immediately after the title, or nil for none.
    ///
    /// Three cells like the others (`[<]`, `[>]`), and in the same border
    /// style, so a panel can carry one affordance of its own without an app
    /// having to reimplement a title bar. `FloatingWindow` uses it for the
    /// slide-out toggle; the right-hand `[+]`/`[x]` zone is untouched.
    public var titleButton: String? {
        didSet {
            if titleButton != oldValue {
                setNeedsDisplay()
            }
        }
    }

    /// Called when ``titleButton`` is clicked.
    public var onTitleButton: () -> Void = {}

    // Where the title button sits: after the title text, which starts at
    // column 2 with a space either side.
    var titleButtonX: Int {
        title.isEmpty ? 2 : 2 + min(title.count, max(0, bounds.size.width - reservedButtonWidth)) + 2
    }

    // Cells the right-hand button zone reserves — shared by the title
    // truncation and the button positions so they cannot disagree.
    var reservedButtonWidth: Int {
        showsMaximizeButton ? 10 : 6
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
    /// The content area for a panel of a given size, WITHOUT needing a layout
    /// pass to have run.
    ///
    /// `layoutSubviews` uses it, so the two cannot drift — and anything that
    /// must know the content area before layout (a window placing slide-outs,
    /// which are positioned in the same pass that sizes this panel) can ask
    /// without depending on ordering.
    ///
    /// - Parameter bounds: The panel's bounds.
    /// - Returns: The content rect in panel coordinates.
    public static func contentRect(forBounds bounds: Rect) -> Rect {
        Rect(
            x: 1,
            y: 1,
            width: max(0, bounds.size.width - 2),
            height: max(0, bounds.size.height - 2)
        )
    }

    public override func layoutSubviews() {
        content.frame = Self.contentRect(forBounds: bounds)
    }

    /// Draws the background, border, title, and close button.
    ///
    /// On a VTG terminal, window chrome swaps the cell-drawn top border for
    /// the theme's vector titlebar: a gradient bar with rounded top corners,
    /// a centered title, and circular close/maximize buttons (Phase 10).
    /// Everything else — side and bottom borders, junctions, embedded
    /// scrollbars — is unchanged, as is the whole panel on plain terminals.
    public override func draw(_ painter: Painter) {
        let theme = effectiveTheme

        painter.fill(bounds, with: .blank)
        painter.drawBox(bounds, style: theme.border, border: frameStyle(theme))

        let width = bounds.size.width

        if let chrome = painter.chrome, isWindowChrome, width >= 4,
           let titleBar = theme.vector?.titleBar {
            chromeTitleBarActive = true
            chromeButtonsLeading = (titleBar.buttonPlacement ?? .trailing) == .leading
            drawVectorTitleBar(painter, chrome: chrome, theme: theme, style: titleBar)
        } else {
            chromeTitleBarActive = false

            // Reserve the right-hand border for the buttons: [x] alone, or
            // the maximize box plus [x].
            let reserved = reservedButtonWidth

            if !title.isEmpty, width > reserved {
                let text = " " + Label.truncated(title, width: width - reserved) + " "
                painter.write(text, at: Point(x: 2, y: 0), style: theme.header)
            }

            if let titleButton, width > reserved + titleButtonX {
                painter.write(titleButton, at: Point(x: titleButtonX, y: 0), style: theme.border)
            }

            if showsMaximizeButton, width >= 11 {
                painter.write(isMaximized ? "[=]" : "[+]", at: Point(x: maximizeButtonX, y: 0), style: theme.border)
            }

            if showsCloseButton, width >= 7 {
                painter.write("[x]", at: Point(x: closeButtonX, y: 0), style: theme.border)
            }
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

    // The vector titlebar (Phase 10): the whole top row's cells go
    // terminal-default so the under-text bar shows through; the title and
    // button glyphs stay native text on top of it.
    private func drawVectorTitleBar(
        _ painter: Painter,
        chrome: ChromeSurface,
        theme: ResolvedTheme,
        style: VectorChrome.TitleBar
    ) {
        let width = bounds.size.width

        // A neutral base defeats the painter's theme substitution, so these
        // cells keep the terminal's default (transparent) background.
        let transparent = painter.withBase(CellStyle())
        transparent.fill(Rect(x: 0, y: 0, width: width, height: 1), with: .blank)

        chrome.verticalGradient(
            "titlebar",
            ChromeRect(x: 0, y: 0, width: Double(width), height: 1),
            top: style.topColor,
            bottom: style.bottomColor,
            steps: 6,
            radius: style.cornerRadius ?? 0.35,
            corners: .top,
            stroke: style.strokeColor
        )

        // Centered title, clear of the button zone on both sides so it stays
        // centered whichever side the buttons sit on.
        let buttonZone = 6

        if !title.isEmpty, width > buttonZone * 2 {
            let text = Label.truncated(title, width: width - buttonZone * 2)
            let textStyle = CellStyle(
                foreground: style.textColor ?? theme.headerForeground,
                flags: theme.headerAttributes
            )
            transparent.write(text, at: Point(x: (width - text.count) / 2, y: 0), style: textStyle)
        }

        if showsCloseButton {
            drawTitleButton(
                chrome, transparent,
                key: "close-button",
                x: closeButtonX,
                fill: style.closeButtonColor,
                symbol: "×",
                symbolColor: style.closeSymbolColor ?? style.textColor ?? theme.headerForeground
            )
        }

        if showsMaximizeButton, width >= 8 {
            drawTitleButton(
                chrome, transparent,
                key: "maximize-button",
                x: maximizeButtonX,
                fill: style.auxiliaryButtonColor ?? ChromeColor.lerp(style.topColor, style.bottomColor, 0.5),
                symbol: isMaximized ? "◦" : "+",
                symbolColor: style.auxiliarySymbolColor ?? style.textColor ?? theme.headerForeground
            )
        }
    }

    // One circular titlebar button: a filled dot behind a one-cell glyph.
    private func drawTitleButton(
        _ chrome: ChromeSurface,
        _ transparent: Painter,
        key: String,
        x: Int,
        fill: ChromeColor,
        symbol: Character,
        symbolColor: TerminalColor
    ) {
        chrome.circle(
            key,
            center: ChromePoint(x: Double(x) + 0.5, y: 0.5),
            radius: 0.36,
            fill: fill
        )

        transparent.set(
            TerminalCell(character: symbol, style: CellStyle(foreground: symbolColor, flags: [.bold])),
            at: Point(x: x, y: 0)
        )
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
        let frame = frameStyle(theme)
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
    private func verticalScrollbarRun() -> ScrollbarRun? {
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

        return ScrollbarRun(start: start, length: length, span: span)
    }

    // The bottom-border bar's run, or nil when the client has no horizontal
    // axis. Permanent chrome, like the vertical bar.
    private func horizontalScrollbarRun() -> ScrollbarRun? {
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

        return ScrollbarRun(start: start, length: length, span: span)
    }

    // Paints both embedded bars over the border (after junctions, so a bar
    // owns its cells). Solid track/thumb colors; small triangle endpoints
    // scroll by one line/column.
    private func drawEmbeddedScrollbars(_ painter: Painter, theme: ResolvedTheme) {
        let focused = (scrollClient as TUIView?)?.isFirstResponder ?? false
        let (track, thumb) = ScrollView.indicatorStyles(for: theme, focused: focused)

        var arrow = track
        arrow.foreground = thumb.background == .standard ? track.foreground : thumb.background

        if let run = verticalScrollbarRun() {
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

        if let run = horizontalScrollbarRun() {
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
        if point.x == bounds.size.width - 1, let run = verticalScrollbarRun(),
           point.y >= run.start, point.y < run.start + run.length {
            scrollVertically(to: run.offset(forPress: point.y, grab: &verticalBarGrab))
            return true
        }

        if point.y == bounds.size.height - 1, let run = horizontalScrollbarRun(),
           point.x >= run.start, point.x < run.start + run.length {
            scrollHorizontally(to: run.offset(forPress: point.x, grab: &horizontalBarGrab))
            return true
        }

        return false
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
                if showsCloseButton, mouse.position.x >= closeButtonX, mouse.position.x < closeButtonX + titleButtonSpan {
                    onClose()
                    return true
                }

                if titleButton != nil, mouse.position.x >= titleButtonX, mouse.position.x < titleButtonX + titleButtonSpan {
                    onTitleButton()
                    return true
                }

                if showsMaximizeButton, mouse.position.x >= maximizeButtonX, mouse.position.x < maximizeButtonX + titleButtonSpan {
                    onMaximize()
                    return true
                }

                return false   // the title row is the window's (drag-to-move)
            }

            return pressEmbeddedBar(at: mouse.position)

        case .drag:
            if let grab = verticalBarGrab, let run = verticalScrollbarRun() {
                scrollVertically(to: run.offset(forThumbStart: mouse.position.y - grab))
                return true
            }

            if let grab = horizontalBarGrab, let run = horizontalScrollbarRun() {
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

    // Title-button geometry follows the presentation: the cell-drawn `[x]`
    // boxes are 3 cells wide at the right edge; the vector titlebar's round
    // buttons are single cells, on the side the theme chose.

    // Cells a title button's hit area spans.
    private var titleButtonSpan: Int {
        chromeTitleBarActive ? 1 : 3
    }

    // Leading cell of the close affordance in the top border.
    private var closeButtonX: Int {
        guard chromeTitleBarActive else {
            return bounds.size.width - 4
        }

        return chromeButtonsLeading ? 1 : bounds.size.width - 2
    }

    // Leading cell of the maximize affordance, one gap from close.
    private var maximizeButtonX: Int {
        guard chromeTitleBarActive else {
            return bounds.size.width - 8
        }

        return chromeButtonsLeading ? 3 : bounds.size.width - 4
    }
}
