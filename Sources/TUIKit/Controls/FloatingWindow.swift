/// Non-modal window with full desktop chrome: title, border, close box,
/// drag-to-move, and drag-to-resize.
///
/// ```text
///   ┌─ Inspector ────────[x]┐   ← drag the title row to move
///   │                       │
///   │   (content view)      │
///   │                       │
///   └───────────────────────◢   ← drag the corner to resize
/// ```
///
/// Present floating windows with `app.present(_:)`; because they are
/// non-modal, clicking any visible part of another window raises and keys
/// it (see `Window.isModal`). The close box and Esc emit `onCloseRequest`
/// — the window never removes itself; the application decides what closing
/// means (usually `app.dismiss(window)`).
///
/// ```swift
/// let inspector = FloatingWindow(title: "Inspector",
///                                frame: Rect(x: 8, y: 3, width: 40, height: 12))
/// inspector.content.addSubview(form)
/// inspector.onCloseRequest = { [weak app, weak inspector] in
///     if let inspector { app?.dismiss(inspector) }
/// }
/// app.present(inspector)
/// ```
@MainActor
open class FloatingWindow: Window {
    /// Title shown in the top border.
    public var title: String {
        get {
            panel.title
        }
        set {
            panel.title = newValue
        }
    }

    /// Called when the close box or Esc asks to close.
    public var onCloseRequest: () -> Void = {}

    /// Container for application content, inset by the chrome.
    ///
    /// Not `panel.content` itself but a container inside it, because a PINNED
    /// slide-out has to shrink the document without shrinking the area the
    /// slide-outs are laid out in — and if those were the same view, a pinned
    /// panel would move out from under itself on every layout pass. The panel
    /// content stays the full inside of the chrome (the slide-out region);
    /// this container is what the document gets to keep.
    public var content: TUIView {
        documentContainer
    }

    /// Embeds a view's scrollbars into the window border (the Borland trick):
    /// the vertical bar rides the right border, the horizontal bar rides the
    /// bottom border under the client's own span, and the view stops spending
    /// interior cells on its own indicators. Pass `nil` to restore plain chrome.
    ///
    /// - Parameters:
    ///   - client: The scrollable view (a `content` descendant), or `nil`.
    ///   - vertical: Run of the right-border bar (default: the full edge).
    ///   - horizontal: Run of the bottom bar (default: under the client).
    // Remembered so a trailing slide-out can hand the bars back and forth:
    // when the panel opens, the border bar is on the wrong side of it.
    private var borderScrollClient: (any BorderScrollable)?
    private var borderScrollExtents: (BorderScrollbarExtent, BorderScrollbarExtent) = (.fullEdge, .underClient)

    public func embedScrollbars(
        for client: BorderScrollable?,
        vertical: BorderScrollbarExtent = .fullEdge,
        horizontal: BorderScrollbarExtent = .underClient
    ) {
        // Remember the REQUEST, then let `updateScrollbarOwnership` decide
        // whether to honour it right now. An app calling this while a panel
        // is open would otherwise re-embed bars the panel had just taken
        // away — which is exactly what happened: the app re-embeds on every
        // tab switch, so the handed-back bars lasted until the next one.
        borderScrollClient = client
        borderScrollExtents = (vertical, horizontal)

        guard client != nil else {
            // An explicit "no client" is the caller giving the bars up; there
            // is nothing left to arbitrate.
            panel.embedScrollbars(for: nil)
            return
        }

        updateScrollbarOwnership()
    }

    /// Whether the title row drags the window.
    public var isMovable = true

    /// Whether the bottom-right corner resizes the window.
    public var isResizable = true {
        didSet {
            panel.showsResizeHandle = isResizable
        }
    }

    /// Smallest size a resize drag can reach.
    public var minimumWindowSize = Size(width: 12, height: 4)

    /// Size state of the window.
    public enum WindowState: Sendable {
        /// The user-controlled frame (draggable, resizable).
        case normal

        /// Filled to the superview minus `maximizeInsets`.
        case maximized
    }

    /// Whether a maximize/restore box shows in the title bar.
    public var isMaximizable = true {
        didSet {
            panel.showsMaximizeButton = isMaximizable
        }
    }

    /// Current size state. Change it with `maximize()`/`restore()`.
    public private(set) var windowState: WindowState = .normal

    /// Edges to leave clear when maximized — e.g. `top: 1, bottom: 1` to keep a
    /// menu-bar strip and status row visible. Defaults to filling completely.
    public var maximizeInsets = EdgeInsets()

    // The frame to return to on restore (saved at the moment of maximize).
    private var normalFrame: Rect?

    // Chrome.
    private let panel: Panel

    // In-flight chrome drag.
    private enum ChromeDrag {
        /// Pointer offset within the window at the moment of the grab.
        case move(grab: Point)
        case resize
    }

    private var activeDrag: ChromeDrag?

    /// Creates a floating window.
    ///
    /// - Parameters:
    ///   - title: Title shown in the top border.
    ///   - frame: Position and size in screen coordinates.
    public init(title: String, frame: Rect) {
        self.panel = Panel(title)
        super.init(frame: frame)

        panel.isWindowChrome = true   // wears the vector titlebar on VTG terminals
        panel.showsCloseButton = true
        panel.showsResizeHandle = true
        panel.showsMaximizeButton = true
        panel.onClose = { [weak self] in
            self?.onCloseRequest()
        }
        panel.onMaximize = { [weak self] in
            self?.toggleMaximize()
        }
        panel.anchors = .fill()
        addSubview(panel)

        documentContainer.anchors = .fill()
        panel.content.addSubview(documentContainer)
    }

    // MARK: - Slide-out chrome

    /// The edge whose slide-out the title-bar button toggles, or nil for no
    /// button.
    ///
    /// The button sits right after the title and says which way the panel
    /// will move: `[>]` when closed (it will come out), `[<]` when open (it
    /// will go back). It is the discoverable half of a slide-out — the
    /// keyboard shortcut is the fast half, and a panel with neither is a
    /// feature nobody finds.
    public var slideOutToggleEdge: SlideOutEdge? {
        didSet {
            refreshSlideOutToggle()
        }
    }

    /// Updates the toggle glyph from the slide-out's state.
    ///
    /// Called on every open and close, because the button has to say what it
    /// will do NEXT, not what it did last.
    func refreshSlideOutToggle() {
        guard let edge = slideOutToggleEdge, let slideOut = slideOut(at: edge) else {
            panel.titleButton = nil
            return
        }

        // A leading panel comes out to the RIGHT, so `[>]` opens it. A
        // trailing panel comes out to the left, so the arrows swap.
        switch edge {
        case .leading:
            panel.titleButton = slideOut.isOpen ? "[<]" : "[>]"

        case .trailing:
            panel.titleButton = slideOut.isOpen ? "[>]" : "[<]"

        case .bottom:
            panel.titleButton = slideOut.isOpen ? "[^]" : "[v]"
        }

        panel.onTitleButton = { [weak self] in
            self?.toggleSlideOut(edge)
        }
    }

    /// Moves the document's scrollbars off the window border while a panel
    /// stands between the border and the document, and back when it closes.
    ///
    /// Bobby: *"on the right switch the view to use the scroll bars in the
    /// border… I would like to see the slider move in and back again when it
    /// closes"* — and then, of the bottom: *"right bar worked, the bottom
    /// didn't."*
    ///
    /// The first attempt at the bottom was `BorderScrollbarExtent.underClient`
    /// for the vertical bar, which is a real improvement but the wrong tool:
    /// an extent bounds how far a bar RUNS along its edge, not which edge it
    /// sits on. The horizontal bar therefore stayed on the window's bottom
    /// border — below the build panel, nowhere near the document it scrolls.
    ///
    /// Both edges are the same problem: a trailing panel puts itself between
    /// the right border and the document, a bottom panel between the bottom
    /// border and the document. Either way the bars belong to the view, whose
    /// own edges are where the document actually ends. Closing the panel hands
    /// them back to the border.
    ///
    /// The visible transition is the point, not a side effect: the slider
    /// moving in and back out is what tells you the bar still belongs to the
    /// document.
    public func updateScrollbarOwnership() {
        guard let client = borderScrollClient else {
            return
        }

        // A LEADING panel is not in this list: it sits between the document
        // and the left border, and neither bar lives there.
        let displacesABar = [SlideOutEdge.trailing, .bottom].contains {
            slideOut(at: $0)?.isOpen ?? false
        }

        if displacesABar {
            // `embedScrollbars(for: nil)` hands the previous client its own
            // bars back, which is exactly the inward move.
            panel.embedScrollbars(for: nil)
        } else {
            panel.embedScrollbars(
                for: client,
                vertical: borderScrollExtents.0,
                horizontal: borderScrollExtents.1
            )
        }
    }

    /// What the document gets after pinned slide-outs have taken their space.
    ///
    /// Anchored to fill until something is pinned; from then on its frame is
    /// set outright, which is why `applySlideOutContent` clears the anchors.
    private let documentContainer = TUIView()

    open override func applySlideOutContent(_ rect: Rect) {
        // Window coordinates in, panel-content coordinates out.
        let region = slideOutRegion
        let local = Rect(
            x: rect.minX - region.minX,
            y: rect.minY - region.minY,
            width: rect.size.width,
            height: rect.size.height
        )

        guard local != documentContainer.frame else {
            return   // the common case: nothing pinned, nothing to do
        }

        documentContainer.anchors = AnchorSet()
        documentContainer.frame = local
        documentContainer.layoutIfNeeded()
    }

    /// The inside of the chrome, in window coordinates.
    ///
    /// This is the whole of "exist outside of the scroll bars": a slide-out
    /// covers content, never the border, so the bars embedded in that border
    /// (`embedScrollbars`) stay where they are and stay usable with a panel
    /// open. The trailing slide-out stops one column short of the vertical
    /// bar rather than covering it.
    open override var slideOutRegion: Rect {
        // Computed from the window's bounds rather than read off
        // `panel.content.frame`, because slide-outs are positioned in the SAME
        // layout pass that sizes the panel. Reading the frame meant opening a
        // panel before the window had ever laid out gave it a zero region —
        // and a slide-out that silently never appears the first time is the
        // worst kind of bug, since the second time it works.
        //
        // `panel` fills the window, so panel coordinates are window
        // coordinates, and `Panel.contentRect` is the same function the panel
        // lays its own content out with.
        Panel.contentRect(forBounds: bounds)
    }

    /// Fills the superview (minus `maximizeInsets`), saving the current frame
    /// so `restore()` is exact. No-op without a superview.
    public func maximize() {
        guard let superview, windowState == .normal else {
            return
        }

        normalFrame = frame
        windowState = .maximized
        panel.isMaximized = true
        frame = maximizedFrame(in: superview.bounds)
        setNeedsDisplay()
    }

    /// Returns a maximized window to its saved normal frame.
    public func restore() {
        guard windowState == .maximized else {
            return
        }

        windowState = .normal
        panel.isMaximized = false

        if let normalFrame {
            frame = normalFrame
        }

        normalFrame = nil
        setNeedsDisplay()
    }

    /// Maximizes a normal window, or restores a maximized one.
    public func toggleMaximize() {
        windowState == .maximized ? restore() : maximize()
    }

    /// Re-applies the maximized frame after the desktop resizes. Called by
    /// `App` on a terminal resize; does nothing for a normal window.
    public func reflowMaximizeIfNeeded() {
        guard windowState == .maximized, let superview else {
            return
        }

        frame = maximizedFrame(in: superview.bounds)
        setNeedsDisplay()
    }

    // A manual move/resize takes ownership of the geometry: the window keeps
    // its current (maximized) size but becomes a normal, user-controlled frame.
    private func exitMaximizedForManualGeometry() {
        guard windowState == .maximized else {
            return
        }

        windowState = .normal
        panel.isMaximized = false
        normalFrame = nil
    }

    // The maximized frame: the superview bounds inset by `maximizeInsets`.
    private func maximizedFrame(in bounds: Rect) -> Rect {
        Rect(
            x: bounds.origin.x + maximizeInsets.left,
            y: bounds.origin.y + maximizeInsets.top,
            width: max(minimumWindowSize.width, bounds.size.width - maximizeInsets.left - maximizeInsets.right),
            height: max(minimumWindowSize.height, bounds.size.height - maximizeInsets.top - maximizeInsets.bottom)
        )
    }

    /// Esc asks to close (before focused views see the key).
    open override func handleHotKey(_ key: KeyInput) -> Bool {
        if key.key == .escape, key.modifiers.isEmpty {
            onCloseRequest()
            return true
        }

        return false
    }

    /// Title-row presses move; corner presses resize.
    ///
    /// Only presses the chrome declined arrive here (the close box is the
    /// panel's), and the window captures the gesture, so drags track even
    /// when the pointer briefly outruns the frame.
    open override func mouseEvent(_ mouse: MouseInput) -> Bool {
        switch mouse.action {
        case .press where mouse.button == .left:
            if isResizable,
               mouse.position.x == bounds.size.width - 1,
               mouse.position.y == bounds.size.height - 1 {
                exitMaximizedForManualGeometry()
                activeDrag = .resize
                return true
            }

            if isMovable, mouse.position.y == 0 {
                exitMaximizedForManualGeometry()
                activeDrag = .move(grab: mouse.position)
                return true
            }

            return false

        case .drag:
            switch activeDrag {
            case .move(let grab):
                // The pointer arrives in window-local coordinates; keep the
                // grabbed title cell under it.
                let delta = mouse.position - grab
                frame = Rect(
                    origin: Point(
                        x: frame.origin.x + delta.x,
                        y: max(0, frame.origin.y + delta.y)
                    ),
                    size: frame.size
                )
                return true

            case .resize:
                frame = Rect(
                    origin: frame.origin,
                    size: Size(
                        width: max(minimumWindowSize.width, mouse.position.x + 1),
                        height: max(minimumWindowSize.height, mouse.position.y + 1)
                    )
                )
                return true

            case nil:
                return false
            }

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
}
