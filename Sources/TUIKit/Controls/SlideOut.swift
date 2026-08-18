/// Which edge a slide-out is attached to.
///
/// No `.top`: three edges were asked for, and a fourth is API surface with no
/// customer. The enum can grow when something wants one.
public enum SlideOutEdge: Hashable, Sendable, CaseIterable {
    /// The left edge.
    case leading

    /// The right edge.
    case trailing

    /// The bottom edge.
    case bottom

    /// Whether the edge measures in columns (`true`) or rows.
    var isHorizontal: Bool {
        self != .bottom
    }
}

/// A panel that slides over a window's content from one edge, and **costs
/// nothing at all while closed**.
///
/// ```text
///  closed — every cell is document          open — it slides over
/// ┌ proj ─────────────────────────┐        ┌ proj ─────────────────────────┐
/// │  1 │ import Foundation      ▴ │        │┌ Files ──┐mport Foundation  ▴ │
/// │  2 │                        █ │        ││ ▾ Sources│                  █ │
/// │  3 │ struct App {           ▾ │        ││   main.sw│ruct App {        ▾ │
/// └───────────────────────◂ ▸ ────┘        │└─────────┘                    │
///                                          └───────────────────────◂ ▸ ────┘
/// ```
///
/// **Why this rather than a dock.** In a terminal, permanent furniture is
/// measured in columns of text you no longer have. A dock that is open costs
/// its width; a dock that is *closed* still costs a separator or a stub. The
/// only arrangement that costs nothing is one that is not there — so a closed
/// slide-out contributes no frame, no separator, and no reserved cell, and a
/// window with three closed slide-outs lays out identically to one with none.
/// `Docs/SlideOutPlan.md` has the column arithmetic that killed the docking
/// design.
///
/// An OPEN panel pushes the document aside rather than covering it. The first
/// version covered, to keep the document from reflowing; using it settled the
/// question the other way, and obviously so — the file tree and the file are
/// wanted at the same time, which is the whole reason to open the tree. The
/// saving that justifies the design is untouched either way, because it comes
/// entirely from *closed* costing nothing.
///
/// Chrome is one line: the divider on the inner edge, the one with the
/// document on the other side of it. The panel's other three edges are the
/// main window's own frame, so drawing a box there painted a second line
/// beside the window's and cost two columns to say nothing.
///
/// Create them through `Window.addSlideOut(_:title:content:length:)`, which
/// owns the geometry and the focus hand-off.
@MainActor
public final class SlideOut {
    /// The edge it slides from.
    public let edge: SlideOutEdge

    /// A name for the panel.
    ///
    /// **Not drawn.** There is no top border to put it in — that edge is the
    /// window's own frame — and spending a row on a title bar would undo part
    /// of what makes a slide-out cheap. It exists so a host can label the menu
    /// item, shortcut, or status message that opens this panel with the same
    /// string the panel is known by.
    public var title: String

    /// The caller's view.
    public let content: TUIView

    /// The chrome: a background and ONE divider, on the inner edge.
    ///
    /// Bobby, on the first version, which wrapped the content in a full
    /// `Panel`: *"the only frame should be the right one — the others are not
    /// drawn but are virtually the main window's frame."* He is right, and it
    /// is worth three cells: a panel flush against the window's left border
    /// has that border as its own left edge already, and its top and bottom
    /// edges are the window's too. Drawing a box painted a second line beside
    /// the window's and cost two columns of the panel's own width to say
    /// nothing.
    ///
    /// So the only line drawn is the one with the document on the other side
    /// of it — the right edge of a leading panel, the left edge of a trailing
    /// one, the top of the bottom one.
    ///
    /// Hidden while closed, so it draws nothing and takes no part in focus.
    let chrome: SlideOutChrome

    /// Columns (leading/trailing) or rows (bottom).
    ///
    /// Clamped at layout time to what the window can spare — the stored value
    /// is the user's preference, not a promise.
    public var length: Int {
        didSet {
            if length != oldValue {
                owner?.setNeedsLayout()
                onLengthChanged(length)
            }
        }
    }

    /// Smallest useful length; layout will not shrink below it unless the
    /// window itself is smaller than that.
    public var minimumLength: Int

    /// Whether it stays open when something inside it is activated.
    ///
    /// Bobby: *"pin just means doesn't close on action, which is the only way
    /// I envisioned it."* So that is all it means — there is no second
    /// behaviour hiding behind the word.
    ///
    /// Unpinned is the drawer: open it, pick a file, it closes behind you.
    /// Pinned is the sidebar you keep.
    public var isPinned = false

    /// Whether dragging the inner edge resizes it.
    public var isResizable = true

    /// Whether it is showing.
    ///
    /// Read-only here on purpose: opening and closing move the first
    /// responder, which only the window can do. Use `Window.openSlideOut(_:)`
    /// and friends.
    public internal(set) var isOpen = false {
        didSet {
            if isOpen != oldValue {
                chrome.isHidden = !isOpen
                owner?.setNeedsLayout()
                owner?.setNeedsDisplay()
                notifyWindowOfVisibility()
                onVisibilityChanged(isOpen)
            }
        }
    }

    /// Called when it opens or closes — the hook a host uses to persist the
    /// state, since TUIKit does no file I/O.
    public var onVisibilityChanged: (Bool) -> Void = { _ in }

    // Window chrome that has to follow this panel's state: the title-bar
    // toggle glyph, and which side of a trailing panel the scrollbars are on.
    func notifyWindowOfVisibility() {
        guard let floating = owner as? FloatingWindow else {
            return
        }

        floating.refreshSlideOutToggle()
        floating.updateScrollbarOwnership()
    }

    /// Called when the length changes (a drag, or a caller assigning).
    public var onLengthChanged: (Int) -> Void = { _ in }

    // The window that owns the geometry. Weak: the window holds this.
    weak var owner: Window?

    /// Creates a slide-out. Call `Window.addSlideOut` rather than this.
    ///
    /// - Parameters:
    ///   - edge: Which edge it slides from.
    ///   - title: Title for the chrome.
    ///   - content: The caller's view.
    ///   - length: Preferred columns or rows.
    ///   - minimumLength: Smallest useful length.
    init(edge: SlideOutEdge, title: String, content: TUIView, length: Int, minimumLength: Int) {
        self.edge = edge
        self.title = title
        self.content = content
        self.length = length
        self.minimumLength = minimumLength
        self.chrome = SlideOutChrome(edge: edge, content: content)
        chrome.isHidden = true   // closed is the normal state
    }
}

/// A slide-out's chrome: an opaque background and ONE divider line, on the
/// edge the document is on the other side of.
///
/// Not a `Panel`. A panel draws a box, and three of those four sides would
/// land on the main window's own frame — a second line beside the window's,
/// costing two of the panel's columns and one of its rows to say nothing.
/// Bobby: *"the only frame should be the right one — the others are not drawn
/// but are virtually the main window's frame."*
///
/// The background fill is not decoration either: without it the document
/// behind shows through the panel's blank rows and the whole thing reads as
/// corrupted text.
@MainActor
public final class SlideOutChrome: TUIView {
    /// Which edge the panel is attached to; decides where the divider goes.
    public let edge: SlideOutEdge

    /// The caller's view.
    public let content: TUIView

    /// Creates the chrome.
    ///
    /// - Parameters:
    ///   - edge: The panel's edge.
    ///   - content: The caller's view.
    public init(edge: SlideOutEdge, content: TUIView) {
        self.edge = edge
        self.content = content
        super.init(frame: .zero)
        addSubview(content)
    }

    /// Insets the content by the one divider column or row.
    public override func layoutSubviews() {
        let size = bounds.size

        switch edge {
        case .leading:
            content.frame = Rect(x: 0, y: 0, width: max(0, size.width - 1), height: size.height)

        case .trailing:
            content.frame = Rect(x: 1, y: 0, width: max(0, size.width - 1), height: size.height)

        case .bottom:
            content.frame = Rect(x: 0, y: 1, width: size.width, height: max(0, size.height - 1))
        }
    }

    /// Fills the background and draws the divider.
    public override func draw(_ painter: Painter) {
        let theme = effectiveTheme
        painter.fill(bounds, with: .blank)

        let size = bounds.size

        switch edge {
        case .leading where size.width > 0:
            drawLine(painter, style: theme.border, vertical: true, at: size.width - 1)

        case .trailing where size.width > 0:
            drawLine(painter, style: theme.border, vertical: true, at: 0)

        case .bottom where size.height > 0:
            drawLine(painter, style: theme.border, vertical: false, at: 0)

        default:
            break
        }
    }

    private func drawLine(_ painter: Painter, style: CellStyle, vertical: Bool, at offset: Int) {
        let character: Character = vertical ? "│" : "─"
        let count = vertical ? bounds.size.height : bounds.size.width

        for step in 0..<count {
            painter.set(
                TerminalCell(character: character, style: style),
                at: vertical ? Point(x: offset, y: step) : Point(x: step, y: offset)
            )
        }
    }
}

/// Where each open slide-out sits, and what is left for the content.
///
/// Pure arithmetic, deliberately separate from `Window`: this is the part
/// with all the edge cases (a window narrower than its slide-outs, two open
/// at once, pinned mixed with overlaid), and a test for it should not need a
/// window, a driver, or a frame.
public enum SlideOutLayout {
    /// One slide-out's input to the layout.
    public struct Request: Equatable, Sendable {
        /// Which edge.
        public var edge: SlideOutEdge

        /// Preferred length.
        public var length: Int

        /// Smallest useful length.
        public var minimumLength: Int

        /// Whether it is showing at all.
        public var isOpen: Bool

        /// Creates a request.
        public init(
            edge: SlideOutEdge,
            length: Int,
            minimumLength: Int = 1,
            isOpen: Bool = true
        ) {
            self.edge = edge
            self.length = length
            self.minimumLength = minimumLength
            self.isOpen = isOpen
        }
    }

    /// The resolved geometry.
    public struct Result: Equatable, Sendable {
        /// Frame per open edge, in the region's coordinate space. Closed
        /// edges are absent — not zero-sized, absent.
        public var frames: [SlideOutEdge: Rect]

        /// What is left for the content once the open panels have taken
        /// theirs.
        public var content: Rect
    }

    /// Resolves the geometry.
    ///
    /// The corner rule: **the bottom slide-out claims the full width, and the
    /// side slide-outs take what is left above it.** The alternative — sides
    /// full height, bottom between them — makes the bottom panel jump
    /// sideways whenever a side panel opens, which reads as a bug rather than
    /// as a layout.
    ///
    /// - Parameters:
    ///   - region: The area slide-outs may cover (a window's content area).
    ///   - requests: One per slide-out, in any order.
    /// - Returns: Frames for the open ones, and the content rect.
    public static func resolve(region: Rect, requests: [Request]) -> Result {
        var frames: [SlideOutEdge: Rect] = [:]
        var content = region

        let open = requests.filter(\.isOpen)

        // Bottom first: it owns the full width, so the sides measure against
        // what it leaves behind.
        var bodyHeight = region.size.height

        if let bottom = open.first(where: { $0.edge == .bottom }) {
            // Never take the last row: a content area of zero height is a
            // window with nothing in it.
            let rows = clamp(bottom.length, minimum: bottom.minimumLength, available: region.size.height - 1)

            if rows > 0 {
                frames[.bottom] = Rect(
                    x: region.minX,
                    y: region.minY + region.size.height - rows,
                    width: region.size.width,
                    height: rows
                )

                bodyHeight = region.size.height - rows

                content.size.height -= rows
            }
        }

        // Sides share the width, leading first — it is the primary panel in
        // every app that has asked for one, and a deterministic loser is
        // better than two panels each shrinking the other.
        // Two counters, not one: the shared budget decides how WIDE each may
        // be, but each edge is positioned from its own side. Adding the
        // leading width into the trailing panel's offset put it in the middle
        // of the window — which is what the first run of these tests caught.
        var takenLeading = 0
        var takenTrailing = 0

        for edge in [SlideOutEdge.leading, .trailing] {
            guard let request = open.first(where: { $0.edge == edge }) else {
                continue
            }

            let columns = clamp(
                request.length,
                minimum: request.minimumLength,
                available: region.size.width - takenLeading - takenTrailing - 1
            )

            guard columns > 0 else {
                continue
            }

            frames[edge] = Rect(
                x: edge == .leading
                    ? region.minX + takenLeading
                    : region.minX + region.size.width - takenTrailing - columns,
                y: region.minY,
                width: columns,
                height: bodyHeight
            )

            if edge == .leading {
                takenLeading += columns
            } else {
                takenTrailing += columns
            }

            content.size.width -= columns

            if edge == .leading {
                content.origin.x += columns
            }
        }

        return Result(frames: frames, content: content)
    }

    // A length the region can actually give: the preference, floored at the
    // minimum, then capped by what is available — and the cap wins, because a
    // minimum that does not fit is a preference too.
    private static func clamp(_ length: Int, minimum: Int, available: Int) -> Int {
        guard available > 0 else {
            return 0
        }

        return min(max(length, max(0, minimum)), available)
    }
}

// MARK: - Window API

public extension Window {
    /// Adds a slide-out to an edge, closed.
    ///
    /// The content view becomes a subview of the WINDOW rather than of its
    /// content area, for two reasons that both bite in practice: it must draw
    /// over whatever the app put in the window (later subviews draw last), and
    /// `TUIView.setContent` removes every subview of the view it is called on
    /// — an app rebuilding its content would otherwise take the slide-outs
    /// with it.
    ///
    /// - Parameters:
    ///   - edge: Which edge it slides from. One per edge; adding a second
    ///     replaces the first.
    ///   - title: Title for the chrome.
    ///   - content: The caller's view.
    ///   - length: Preferred columns (leading/trailing) or rows (bottom).
    ///   - minimumLength: Smallest useful length.
    /// - Returns: The slide-out, for wiring callbacks and pinning.
    @discardableResult
    func addSlideOut(
        _ edge: SlideOutEdge,
        title: String = "",
        content: TUIView,
        length: Int,
        minimumLength: Int = 4
    ) -> SlideOut {
        if let existing = slideOut(at: edge) {
            existing.chrome.removeFromSuperview()
            slideOuts.removeAll { $0 === existing }
        }

        let slideOut = SlideOut(
            edge: edge,
            title: title,
            content: content,
            length: length,
            minimumLength: minimumLength
        )
        slideOut.owner = self
        slideOuts.append(slideOut)
        addSubview(slideOut.chrome)
        setNeedsLayout()
        slideOut.notifyWindowOfVisibility()   // the toggle glyph starts correct
        return slideOut
    }

    /// The slide-out on an edge, when one was added.
    func slideOut(at edge: SlideOutEdge) -> SlideOut? {
        slideOuts.first { $0.edge == edge }
    }

    /// Opens a slide-out and moves focus into it.
    ///
    /// Focus is not decoration: a keyboard user who opens a panel they cannot
    /// reach has an open panel and no way to use it.
    func openSlideOut(_ edge: SlideOutEdge) {
        guard let slideOut = slideOut(at: edge), !slideOut.isOpen else {
            return
        }

        // Remembered before the open, so closing returns focus to whatever
        // the user was actually working in.
        responderBeforeSlideOut = firstResponder
        slideOut.isOpen = true
        layoutIfNeeded()

        if let target = slideOut.chrome.firstFocusableDescendant() {
            makeFirstResponder(target)
        }
    }

    /// Closes a slide-out and restores focus to whatever had it before.
    func closeSlideOut(_ edge: SlideOutEdge) {
        guard let slideOut = slideOut(at: edge), slideOut.isOpen else {
            return
        }

        // Read BEFORE closing: closing hides the content, and a hidden view
        // must never be left holding the first responder.
        let wasFocused = firstResponder.map { slideOut.chrome.contains($0) } ?? false
        slideOut.isOpen = false

        if wasFocused {
            makeFirstResponder(responderBeforeSlideOut)
            responderBeforeSlideOut = nil
        }
    }

    /// Opens a closed slide-out, closes an open one.
    func toggleSlideOut(_ edge: SlideOutEdge) {
        guard let slideOut = slideOut(at: edge) else {
            return
        }

        if slideOut.isOpen {
            closeSlideOut(edge)
        } else {
            openSlideOut(edge)
        }
    }

    /// Closes every open slide-out that is not pinned.
    ///
    /// Call it when a row inside one is activated: open the drawer, pick a
    /// file, and it closes behind you. A pinned panel stays.
    func closeTransientSlideOuts() {
        for slideOut in slideOuts where slideOut.isOpen && !slideOut.isPinned {
            closeSlideOut(slideOut.edge)
        }
    }

    /// Places the open slide-outs over the content.
    ///
    /// Called from `layoutSubviews`; a caller should not need this.
    func layoutSlideOuts() {
        guard !slideOuts.isEmpty else {
            // No panels, but a toolbar still shortens the document.
            if windowToolbar != nil {
                applySlideOutContent(slideOutContentRegion)
            }

            return   // otherwise the common case, and it must cost nothing
        }

        let result = SlideOutLayout.resolve(
            region: slideOutContentRegion,
            requests: slideOuts.map {
                SlideOutLayout.Request(
                    edge: $0.edge,
                    length: $0.length,
                    minimumLength: $0.minimumLength,
                    isOpen: $0.isOpen
                )
            }
        )

        for slideOut in slideOuts {
            guard let frame = result.frames[slideOut.edge] else {
                continue   // closed: no frame, and the view is hidden anyway
            }

            slideOut.chrome.frame = frame
            slideOut.chrome.layoutIfNeeded()
        }

        // Pinned panels shrink the document; overlaid ones do not, and then
        // this is the whole region, which is what the default no-op wants.
        applySlideOutContent(result.content)
    }
}

extension TUIView {
    /// Whether a view is this view or somewhere beneath it.
    func contains(_ view: TUIView) -> Bool {
        var candidate: TUIView? = view

        while let current = candidate {
            if current === self {
                return true
            }

            candidate = current.superview
        }

        return false
    }

    /// The first view in this subtree that can take focus, self included.
    func firstFocusableDescendant() -> TUIView? {
        var found: TUIView?

        traverseVisible { view in
            if view.acceptsFirstResponder {
                found = view
                return true
            }

            return false
        }

        return found
    }
}

// MARK: - Resizing

extension Window {
    /// Handles a mouse event that is dragging a slide-out's inner edge.
    ///
    /// The grab/clamp shape is `SplitView`'s — press on the edge, follow
    /// drags, release lets go — deliberately, so the two read the same. What
    /// differs is which edge: a slide-out's draggable border is the one the
    /// document is on the other side of, which is the RIGHT border of a
    /// leading panel and the LEFT border of a trailing one.
    ///
    /// - Returns: Whether the event was consumed.
    func resizeSlideOut(with mouse: MouseInput) -> Bool {
        switch mouse.action {
        case .press where mouse.button == .left:
            guard let slideOut = resizableSlideOut(under: mouse.position) else {
                return false
            }

            resizingSlideOut = slideOut
            return true

        case .drag:
            guard let slideOut = resizingSlideOut else {
                return false
            }

            // Measured from the FIXED edge — the one the panel is anchored
            // to — because the panel's own frame moves as it resizes and a
            // length measured against a moving edge chases the pointer.
            let region = slideOutContentRegion

            switch slideOut.edge {
            case .leading:
                slideOut.length = max(1, mouse.position.x - region.minX + 1)

            case .trailing:
                slideOut.length = max(1, region.minX + region.size.width - mouse.position.x)

            case .bottom:
                slideOut.length = max(1, region.minY + region.size.height - mouse.position.y)
            }

            return true

        case .release:
            guard resizingSlideOut != nil else {
                return false
            }

            resizingSlideOut = nil
            return true

        default:
            return false
        }
    }

    // The open, resizable slide-out whose inner border is under a point.
    private func resizableSlideOut(under point: Point) -> SlideOut? {
        slideOuts.first { slideOut in
            guard slideOut.isOpen, slideOut.isResizable else {
                return false
            }

            let frame = slideOut.chrome.frame

            guard frame.contains(point) else {
                return false
            }

            switch slideOut.edge {
            case .leading: return point.x == frame.minX + frame.size.width - 1
            case .trailing: return point.x == frame.minX
            case .bottom: return point.y == frame.minY
            }
        }
    }
}
