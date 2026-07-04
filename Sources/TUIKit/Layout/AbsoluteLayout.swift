/// Container that performs **no** automated layout on its immediate children.
///
/// Unlike `HStack`/`VStack`/`GridView`, an `AbsoluteLayout` never positions or
/// resizes the children you add — each keeps exactly the `frame` you give it,
/// in the container's own coordinate space. Anchors are ignored here. This is
/// the escape hatch for hand-placed UI (free-form canvases, overlays,
/// diagram-style layouts) inside an otherwise managed view tree.
///
/// ```text
///   ┌──────────────────────────┐
///   │  ┌────┐                   │   children sit wherever you put them;
///   │  │ A  │      ┌─────┐      │   the container does not move them
///   │  └────┘      │  B  │      │
///   │              └─────┘      │
///   └──────────────────────────┘
/// ```
///
/// It does size itself *to its parent*, though: `intrinsicContentSize` is the
/// bounding box of its children, so a stack/grid/anchor parent can give it the
/// room it needs. Because children are placed by direct `frame` assignment —
/// which does not tell the parent to re-measure — call `relayout()` after
/// moving or adding children to force the parent to re-evaluate that size, and
/// `refresh()` to force a redraw.
///
/// ```swift
/// let canvas = AbsoluteLayout()
/// canvas.place(Label("A"), at: Rect(x: 2, y: 1, width: 4, height: 1))
/// canvas.place(Label("B"), at: Rect(x: 14, y: 3, width: 5, height: 1))
/// stack.addSubview(canvas)   // the stack sizes to the 19×4 bounding box
///
/// // later, after moving a child:
/// b.frame = Rect(x: 20, y: 6, width: 5, height: 1)
/// canvas.relayout()          // parent re-measures; canvas grows to fit
/// ```
@MainActor
public final class AbsoluteLayout: TUIView {
    /// Creates an absolute-layout container.
    ///
    /// - Parameter frame: Position and size in the parent's coordinate space.
    public override init(frame: Rect = .zero) {
        super.init(frame: frame)
    }

    /// Adds a child at an explicit frame.
    ///
    /// - Parameters:
    ///   - view: Child to add.
    ///   - frame: Its frame in this container's coordinate space.
    /// - Returns: The added view, for chaining.
    @discardableResult
    public func place(_ view: TUIView, at frame: Rect) -> TUIView {
        view.frame = frame
        addSubview(view)
        return view
    }

    /// No automated layout: children keep the frames you set, and their
    /// `anchors` are ignored.
    public override func layoutSubviews() {}

    /// The bounding box of the visible children, so the parent can size this
    /// container. `nil` (flexible) when there are no visible children.
    public override var intrinsicContentSize: Size? {
        let frames = subviews.filter { !$0.isHidden }.map(\.frame)

        guard !frames.isEmpty else {
            return nil
        }

        let width = frames.map { $0.origin.x + $0.size.width }.max() ?? 0
        let height = frames.map { $0.origin.y + $0.size.height }.max() ?? 0
        return Size(width: max(0, width), height: max(0, height))
    }
}
