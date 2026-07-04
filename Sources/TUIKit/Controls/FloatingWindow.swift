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
    public var content: TUIView {
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
