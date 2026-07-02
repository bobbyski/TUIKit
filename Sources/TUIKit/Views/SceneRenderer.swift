/// Renders a view tree into presentable cell buffers.
///
/// The renderer sits between the view system and a `TerminalDriver`: it
/// turns a root view into a `CellBuffer` that any driver can present. It
/// owns the frame lifecycle — dirty checking, target creation, deterministic
/// compose — while views own only their local drawing.
///
/// ```text
///   View tree ──> SceneRenderer.renderIfNeeded(size:) ──> CellBuffer?
///                                                            │
///                                              driver.present(buffer)
/// ```
///
/// v1 semantics: dirtiness gates whether a frame is produced at all; a
/// produced frame redraws the full tree. Damage-region partial redraw can
/// land later behind this same API.
@MainActor
public final class SceneRenderer {
    /// Root of the rendered view tree.
    public let root: View

    // Size of the previous frame; a size change forces a render.
    private var lastRenderedSize: Size?

    /// Creates a renderer for a view tree.
    ///
    /// - Parameter root: Root view. Its frame is expressed in screen
    ///   coordinates.
    public init(root: View) {
        self.root = root
    }

    /// Whether the next `renderIfNeeded(size:)` would produce a frame.
    ///
    /// - Parameter size: Target frame size.
    /// - Returns: `true` when the tree is dirty or the size changed.
    public func needsRender(for size: Size) -> Bool {
        root.needsDisplayInTree || lastRenderedSize != size
    }

    /// Renders a frame only when something changed.
    ///
    /// - Parameter size: Target frame size in cells.
    /// - Returns: The composed frame, or `nil` when nothing needs drawing.
    public func renderIfNeeded(size: Size) -> CellBuffer? {
        guard needsRender(for: size) else {
            return nil
        }

        return render(size: size)
    }

    /// Renders a frame unconditionally.
    ///
    /// - Parameter size: Target frame size in cells.
    /// - Returns: The composed frame.
    public func render(size: Size) -> CellBuffer {
        let target = RenderTarget(size: size)
        let screen = Rect(origin: .zero, size: size)
        let painter = Painter(
            target: target,
            origin: root.frame.origin,
            clip: screen.intersection(root.frame)
        )

        root.renderTree(with: painter)
        lastRenderedSize = size

        return target.buffer
    }
}
