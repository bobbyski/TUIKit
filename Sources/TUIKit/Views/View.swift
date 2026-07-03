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
open class View {
    /// The parent view, when attached.
    public private(set) weak var superview: View?

    /// Child views in back-to-front drawing order.
    public private(set) var subviews: [View] = []

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
    /// - Parameter view: View to add.
    public func addSubview(_ view: View) {
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
    /// - Parameter point: Position in this view's local coordinates.
    /// - Returns: The deepest hit view and the point translated into its
    ///   local coordinates, or `nil` when the point is outside this view.
    public func hitTest(_ point: Point) -> (view: View, local: Point)? {
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
    func traverseVisible(_ body: (View) -> Bool) -> Bool {
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
    func collectVisible(where predicate: (View) -> Bool) -> [View] {
        var result: [View] = []

        traverseVisible { view in
            if predicate(view) {
                result.append(view)
            }

            return false
        }

        return result
    }

    // Whether this view is the given view or one of its descendants.
    func isDescendant(of ancestor: View) -> Bool {
        var current: View? = self

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

        draw(painter)

        for subview in subviews {
            subview.renderTree(with: painter.forSubview(frame: subview.frame))
        }

        needsDisplay = false
        subtreeNeedsDisplay = false
    }
}
