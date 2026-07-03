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
    public var content: View {
        panel.content
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

        panel.showsCloseButton = true
        panel.showsResizeHandle = true
        panel.onClose = { [weak self] in
            self?.onCloseRequest()
        }
        panel.anchors = .fill()
        addSubview(panel)
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
                activeDrag = .resize
                return true
            }

            if isMovable, mouse.position.y == 0 {
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
