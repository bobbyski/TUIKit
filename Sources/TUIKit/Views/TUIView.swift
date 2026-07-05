/// Base class for everything drawable in TUIKit.
///
/// Views form a tree, AppKit style: each view has a `frame` expressed in its
/// parent's coordinate space and draws in its own local space starting at
/// (0, 0). Containers own translation and clipping — a view never learns its
/// absolute position, and its drawing physically cannot escape its parent's
/// viewport (see `Painter`).
///
/// ```text
///   root (frame in screen coords)
///    └─ panel (frame in root coords)
///        └─ label (frame in panel coords, draws at its own 0,0)
/// ```
///
/// Subclasses override `draw(_:)` to paint their content, and the responder
/// methods (`keyDown(_:)`, `mouseEvent(_:)`, hot/cold key hooks) to handle
/// input. A view receives input only through the typed responder surface —
/// raw terminal bytes never reach the view layer. Focus itself is owned by
/// the view's `Window` (the focus scope), not by individual views.
@MainActor
open class TUIView {
    /// The parent view, when attached.
    public private(set) weak var superview: TUIView?

    /// Child views in back-to-front drawing order.
    public private(set) var subviews: [TUIView] = []

    /// The window this view lives in, when attached to one.
    ///
    /// Walks the superview chain; a detached view returns `nil`. Windows
    /// return themselves. Through the window, views reach app services:
    /// `owningWindow?.app?.pasteboard`.
    public var owningWindow: Window? {
        var view: TUIView? = self

        while let current = view {
            if let window = current as? Window {
                return window
            }

            view = current.superview
        }

        return nil
    }

    /// Position and size in the parent's coordinate space.
    public var frame: Rect {
        didSet {
            if frame != oldValue {
                setNeedsDisplay()
            }

            if frame.size != oldValue.size {
                setNeedsLayout()
            }
        }
    }

    /// Whether the view and its subtree are skipped during rendering.
    public var isHidden: Bool = false {
        didSet {
            if isHidden != oldValue {
                setNeedsDisplay()
            }
        }
    }

    /// Theme override for this view and its subtree.
    ///
    /// `nil` (the default) inherits the nearest ancestor's theme; the root
    /// fallback is `Theme.standard`. Setting a theme relayouts and repaints
    /// the subtree — intrinsic sizes can be theme-dependent (a button grows
    /// for its drop shadow under Turbo), so display alone is not enough.
    public var theme: Theme? {
        didSet {
            if theme != oldValue {
                invalidateThemeDependentLayout()
            }
        }
    }

    /// The theme *context* for this view and its subtree — which parallel
    /// palette its slots resolve through (see `ThemeContext`, Docs/Themes.md).
    ///
    /// `nil` (the default) follows the parent; with none set anywhere, slots
    /// resolve against the theme's `base`. Windows set this by type
    /// (`contentWindow`, `modalWindows`, …); chrome sets `desktop`.
    public var themeContext: ThemeContext? {
        didSet {
            if themeContext != oldValue {
                invalidateThemeDependentLayout()
            }
        }
    }

    // A theme (or context) change can move intrinsic sizes, so every container
    // in the subtree re-measures — marking only display would leave controls
    // drawing into stale frames (e.g. a shadowed button truncating its label).
    private func invalidateThemeDependentLayout() {
        setNeedsLayout()

        for subview in subviews {
            subview.invalidateThemeDependentLayout()
        }
    }

    /// Name for the data layer: dotted-path lookup, bulk form I/O, and
    /// bindings (`Docs/DataBinding.md`). Distinct from `identifier`, which is
    /// the stylesheet `#id`.
    public var name: String?

    /// The value binding attached to this view, when any (set by `bind(...)`).
    /// Storage lives here so `load()`/`save()` can walk the tree generically.
    var fieldBinding: FieldBinding?

    // MARK: - Style identity (the CSS layer's selector hooks)

    /// Unique name for stylesheet `#id` selectors.
    public var identifier: String? {
        didSet {
            if identifier != oldValue {
                setNeedsDisplay()
            }
        }
    }

    /// Class names for stylesheet `.class` selectors (HTML `class=`).
    public var styleClasses: Set<String> = [] {
        didSet {
            if styleClasses != oldValue {
                setNeedsDisplay()
            }
        }
    }

    /// Style sheet applying to this view and its subtree.
    ///
    /// Sheets cascade: an inner sheet's rules apply after (and can
    /// override) an outer one's. See `StyleSheet` and
    /// `Docs/StyleSheets.md`.
    public var styleSheet: StyleSheet? {
        didSet {
            if styleSheet != oldValue {
                setNeedsDisplay()
            }
        }
    }

    /// Menu shown on right-click over this view (or its subtree, unless a
    /// descendant sets its own).
    ///
    /// The owning `Window` presents it at the pointer — below when there
    /// is room, above otherwise — with the usual menu keyboard model
    /// (↑/↓, Return, Esc); clicking elsewhere dismisses.
    public var contextMenu: Menu?

    /// The theme in effect for this view: the nearest ancestor's theme,
    /// with matching stylesheet rules applied when any sheets exist
    /// (outer sheets first, then specificity, then source order).
    ///
    /// Style sheets are entirely optional — with none in the ancestor
    /// chain this is exactly the inherited theme.
    public var effectiveTheme: ResolvedTheme {
        var inherited: Theme?
        var context: ThemeContext?
        var foundContext = false
        var sheetHolders: [TUIView] = []
        var current: TUIView? = self

        // Nearest ancestor with a theme, and (independently) the nearest with a
        // context — both walked over the same weak `superview` chain.
        while let view = current {
            if inherited == nil, let theme = view.theme {
                inherited = theme
            }

            if !foundContext, let viewContext = view.themeContext {
                context = viewContext
                foundContext = true
            }

            if view.styleSheet != nil {
                sheetHolders.append(view)
            }

            current = view.superview
        }

        // Resolve the matrix for this view's context, then cascade sheets on
        // top from the root inward.
        var resolved = (inherited ?? .standard).resolved(for: context)

        for holder in sheetHolders.reversed() {
            holder.styleSheet?.apply(to: self, theme: &resolved)
        }

        return resolved
    }

    /// Whether this view needs to be redrawn.
    public private(set) var needsDisplay = true

    // Whether any descendant needs to be redrawn.
    private var subtreeNeedsDisplay = true

    /// Creates a view.
    ///
    /// - Parameter frame: Position and size in the parent's coordinate space.
    public init(frame: Rect = .zero) {
        self.frame = frame
    }

    /// The view's own coordinate space: origin zero, the frame's size.
    public var bounds: Rect {
        Rect(origin: .zero, size: frame.size)
    }

    // MARK: - Hierarchy

    /// Adds a child view at the front of the drawing order.
    ///
    /// The view is removed from any previous parent first.
    ///
    /// - Parameter view: TUIView to add.
    public func addSubview(_ view: TUIView) {
        view.removeFromSuperview()
        subviews.append(view)
        view.superview = self
        setNeedsLayout()
    }

    /// Detaches the view from its parent.
    public func removeFromSuperview() {
        guard let superview else {
            return
        }

        superview.subviews.removeAll { $0 === self }
        superview.setNeedsLayout()
        self.superview = nil
    }

    // MARK: - Drawing

    /// Paints the view's content in local coordinates.
    ///
    /// The base implementation draws nothing. Subclasses override this and
    /// draw through the painter only — there is no way to reach the terminal
    /// from a view, by design.
    ///
    /// - Parameter painter: Clipped, translated surface for this view.
    open func draw(_ painter: Painter) {}

    /// Marks the view as needing redraw and records dirtiness up the tree.
    public func setNeedsDisplay() {
        needsDisplay = true

        var ancestor = superview

        while let view = ancestor {
            view.subtreeNeedsDisplay = true
            ancestor = view.superview
        }
    }

    /// Forces this view and its whole subtree to redraw on the next frame.
    ///
    /// A convenience over `setNeedsDisplay()` that also re-dirties every
    /// descendant, so a view whose children hold stale content can be
    /// refreshed wholesale — handy for manually managed containers like
    /// `AbsoluteLayout`.
    public func refresh() {
        setNeedsDisplay()

        for subview in subviews {
            subview.refresh()
        }
    }

    /// Whether this view or anything beneath it needs redrawing.
    public var needsDisplayInTree: Bool {
        needsDisplay || subtreeNeedsDisplay
    }

    // MARK: - Layout

    /// The size the view's content wants, when it has a natural size.
    ///
    /// Layout containers use this for fit-content sizing; views without a
    /// natural size return `nil` and are treated as flexible.
    open var intrinsicContentSize: Size? {
        nil
    }

    /// Smallest size layout containers may give the view.
    public var minimumSize: Size = .zero {
        didSet {
            if minimumSize != oldValue {
                superview?.setNeedsLayout()
            }
        }
    }

    /// Largest size layout containers may give the view, when limited.
    public var maximumSize: Size? {
        didSet {
            if maximumSize != oldValue {
                superview?.setNeedsLayout()
            }
        }
    }

    /// Edge/center pinning applied by the parent's default layout pass.
    ///
    /// Layout containers (stacks, grids) own their children's frames and
    /// ignore anchors.
    public var anchors: AnchorSet? {
        didSet {
            if anchors != oldValue {
                superview?.setNeedsLayout()
            }
        }
    }

    /// Whether the view needs a layout pass.
    public private(set) var needsLayout = true

    /// Marks the view as needing layout (and therefore redraw).
    public func setNeedsLayout() {
        needsLayout = true
        setNeedsDisplay()
    }

    /// Computes subview frames.
    ///
    /// The default implementation applies each subview's `anchors`. Layout
    /// containers override this and own their children's frames outright.
    open func layoutSubviews() {
        for subview in subviews {
            guard let anchors = subview.anchors else {
                continue
            }

            subview.frame = anchors.resolvedFrame(
                in: bounds,
                current: subview.frame,
                preferred: subview.intrinsicContentSize
            )
        }
    }

    /// Runs any pending layout for the view and its subtree, top down.
    ///
    /// Rendering calls this automatically; tests call it directly to assert
    /// geometry without rendering anything.
    public func layoutIfNeeded() {
        if needsLayout {
            layoutSubviews()
            needsLayout = false
        }

        for subview in subviews {
            subview.layoutIfNeeded()
        }
    }

    /// Forces a layout re-evaluation of this view *and its ancestors* on the
    /// next frame.
    ///
    /// `setNeedsLayout()` alone re-lays-out this view's own children, but a
    /// parent that sizes itself from this view — a stack around an
    /// `AbsoluteLayout` whose children just moved, say — would not re-measure.
    /// `relayout()` also marks the ancestor chain, so the whole path
    /// re-evaluates and the parent adopts this view's new intrinsic size.
    public func relayout() {
        setNeedsLayout()

        var ancestor = superview

        while let view = ancestor {
            view.setNeedsLayout()
            ancestor = view.superview
        }
    }

    // MARK: - Responder Surface

    /// Whether the view can hold keyboard focus.
    ///
    /// Focusable controls override this to return `true`. Focus itself is
    /// granted and revoked by the view's `Window` through
    /// `makeFirstResponder(_:)`.
    open var acceptsFirstResponder: Bool {
        false
    }

    /// Whether the view currently holds keyboard focus.
    ///
    /// Managed by the owning `Window`; views only read it (typically to draw
    /// a focus indicator).
    public internal(set) var isFirstResponder = false {
        didSet {
            if isFirstResponder != oldValue {
                setNeedsDisplay()
            }
        }
    }

    /// Called after the view gains keyboard focus.
    open func didBecomeFirstResponder() {}

    /// Called after the view loses keyboard focus.
    open func didResignFirstResponder() {}

    /// Whether this view is a transient overlay (a menu dropdown, pop-up list,
    /// or context menu) that a press *anywhere outside it* should dismiss —
    /// including a press that lands on the desktop or a different window, which
    /// its own window would otherwise never see. Such overlays tear themselves
    /// down from `didResignFirstResponder`, so dismissal is just moving focus
    /// off them. Ordinary views stay put on an outside click.
    open var dismissesOnOutsidePress: Bool { false }

    /// Handles a key while the view is (or contains) the first responder.
    ///
    /// Unhandled keys bubble up the superview chain, then fall through to
    /// focus traversal (Tab / Shift+Tab) and finally the cold-key pass.
    ///
    /// - Parameter key: Decoded key input.
    /// - Returns: `true` when the view consumed the key.
    open func keyDown(_ key: KeyInput) -> Bool {
        false
    }

    /// Offers a key to the view before focus routing (accelerators).
    ///
    /// The window walks the tree depth-first; the first view returning
    /// `true` consumes the key.
    ///
    /// - Parameter key: Decoded key input.
    /// - Returns: `true` when the view consumed the key.
    open func handleHotKey(_ key: KeyInput) -> Bool {
        false
    }

    /// Offers a key nothing else consumed (fallback shortcuts).
    ///
    /// - Parameter key: Decoded key input.
    /// - Returns: `true` when the view consumed the key.
    open func handleColdKey(_ key: KeyInput) -> Bool {
        false
    }

    /// Handles a mouse event delivered in the view's local coordinates.
    ///
    /// Unhandled events bubble up the superview chain.
    ///
    /// - Parameter mouse: Decoded mouse event, position in local coordinates.
    /// - Returns: `true` when the view consumed the event.
    open func mouseEvent(_ mouse: MouseInput) -> Bool {
        false
    }

    // MARK: - Hit Testing and Traversal

    /// Finds the deepest visible view containing a point.
    ///
    /// Overridable: a view can decline points inside its frame to become
    /// click-through there (a menu-bar strip window claims only its bar
    /// row). Click-to-activate honors this — declined points fall to the
    /// windows behind.
    ///
    /// - Parameter point: Position in this view's local coordinates.
    /// - Returns: The deepest hit view and the point translated into its
    ///   local coordinates, or `nil` when the point is outside this view.
    open func hitTest(_ point: Point) -> (view: TUIView, local: Point)? {
        guard !isHidden, bounds.contains(point) else {
            return nil
        }

        for subview in subviews.reversed() {
            if let hit = subview.hitTest(point - subview.frame.origin) {
                return hit
            }
        }

        return (self, point)
    }

    // Visits the visible tree depth-first (self, then children in order)
    // until the body returns true. Returns whether any visit returned true.
    @discardableResult
    func traverseVisible(_ body: (TUIView) -> Bool) -> Bool {
        guard !isHidden else {
            return false
        }

        if body(self) {
            return true
        }

        for subview in subviews {
            if subview.traverseVisible(body) {
                return true
            }
        }

        return false
    }

    // Collects visible views depth-first that satisfy the predicate.
    func collectVisible(where predicate: (TUIView) -> Bool) -> [TUIView] {
        var result: [TUIView] = []

        traverseVisible { view in
            if predicate(view) {
                result.append(view)
            }

            return false
        }

        return result
    }

    // Whether this view is the given view or one of its descendants.
    func isDescendant(of ancestor: TUIView) -> Bool {
        var current: TUIView? = self

        while let view = current {
            if view === ancestor {
                return true
            }

            current = view.superview
        }

        return false
    }

    // Draws this view and its subtree, clearing dirty flags.
    //
    // Order is deterministic: a view paints before its children, and
    // children paint in `subviews` order (later siblings overdraw earlier
    // ones).
    func renderTree(with painter: Painter) {
        guard !isHidden else {
            needsDisplay = false
            subtreeNeedsDisplay = false
            return
        }

        // Re-base the painter on this view's resolved theme (explicit
        // theme override and/or stylesheet rules); a no-op when nothing
        // applies.
        let painter = painter.withBase(effectiveTheme.base)

        draw(painter)

        for subview in subviews {
            subview.renderTree(with: painter.forSubview(frame: subview.frame))
        }

        needsDisplay = false
        subtreeNeedsDisplay = false
    }
}
