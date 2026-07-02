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
/// Subclasses override `draw(_:)` to paint their content. Interaction,
/// focus, and layout arrive in later phases; this class deliberately owns
/// only geometry, hierarchy, drawing, and dirty tracking.
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
        setNeedsDisplay()
    }

    /// Detaches the view from its parent.
    public func removeFromSuperview() {
        guard let superview else {
            return
        }

        superview.subviews.removeAll { $0 === self }
        superview.setNeedsDisplay()
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
