/// Top-level view that owns keyboard focus and input routing — a focus scope.
///
/// Windows are the focus scopes of TUIKit: they track the first responder,
/// own the tab order, and route input to their subtree. Views never manage
/// focus themselves; they accept it (`acceptsFirstResponder`) and react to
/// it (`didBecomeFirstResponder` / `didResignFirstResponder`).
///
/// Key routing order, AppKit-flavored:
///
/// ```text
///   1. hot keys      depth-first handleHotKey (accelerators)
///   2. focused chain first responder keyDown, bubbling up superviews
///   3. focus keys    Tab / Shift+Tab traversal (if not consumed above)
///   4. cold keys     depth-first handleColdKey (fallbacks)
/// ```
///
/// Mouse events hit-test to the deepest visible view, arrive in that view's
/// local coordinates, focus it on press when it accepts focus, and bubble up
/// the superview chain until consumed.
///
/// Window chrome (title bars, borders, dragging) is a later phase; this
/// class is the focus/routing scope.
@MainActor
open class Window: View {
    /// The view holding keyboard focus, when any.
    public private(set) var firstResponder: View?

    /// Whether the window should track the screen size.
    ///
    /// Set automatically when a window is presented with a zero frame.
    public var fillsScreen = false

    /// Creates a window.
    ///
    /// - Parameter frame: Position and size in screen coordinates. A zero
    ///   frame means "fill the screen" once presented.
    public override init(frame: Rect = .zero) {
        super.init(frame: frame)
    }

    // MARK: - Focus

    /// Moves keyboard focus to a view in this window's subtree.
    ///
    /// - Parameter view: View to focus, or `nil` to clear focus.
    /// - Returns: `true` when focus changed; `false` when the view refuses
    ///   focus or is not in this window's subtree.
    @discardableResult
    public func makeFirstResponder(_ view: View?) -> Bool {
        if let view {
            guard view.acceptsFirstResponder, view.isDescendant(of: self) else {
                return false
            }
        }

        guard firstResponder !== view else {
            return true
        }

        let previous = firstResponder
        firstResponder = view

        previous?.isFirstResponder = false
        previous?.didResignFirstResponder()

        view?.isFirstResponder = true
        view?.didBecomeFirstResponder()

        return true
    }

    /// Moves focus to the next focusable view in depth-first order, wrapping.
    ///
    /// - Returns: `true` when focus moved.
    @discardableResult
    public func focusNext() -> Bool {
        advanceFocus(by: 1)
    }

    /// Moves focus to the previous focusable view, wrapping.
    ///
    /// - Returns: `true` when focus moved.
    @discardableResult
    public func focusPrevious() -> Bool {
        advanceFocus(by: -1)
    }

    private func advanceFocus(by offset: Int) -> Bool {
        let focusables = collectVisible { $0.acceptsFirstResponder }

        guard !focusables.isEmpty else {
            return false
        }

        let currentIndex = firstResponder.flatMap { responder in
            focusables.firstIndex { $0 === responder }
        }

        let nextIndex: Int

        if let currentIndex {
            nextIndex = (currentIndex + offset + focusables.count) % focusables.count
        } else {
            nextIndex = offset > 0 ? 0 : focusables.count - 1
        }

        return makeFirstResponder(focusables[nextIndex])
    }

    // MARK: - Input Routing

    /// Routes one input event through the window.
    ///
    /// - Parameter input: Event with positions in window-local coordinates.
    /// - Returns: `true` when something in the window consumed the event.
    @discardableResult
    public func route(_ input: TerminalInput) -> Bool {
        switch input {
        case .key(let key):
            return routeKey(key)

        case .mouse(let mouse):
            return routeMouse(mouse)

        case .resize:
            // Size changes are the application's concern.
            return false
        }
    }

    private func routeKey(_ key: KeyInput) -> Bool {
        // 1. Hot keys.
        if traverseVisible({ $0.handleHotKey(key) }) {
            return true
        }

        // 2. Focused chain, bubbling from the first responder to the window.
        var responder = firstResponder

        while let view = responder {
            if view.keyDown(key) {
                return true
            }

            responder = view === self ? nil : view.superview
        }

        if firstResponder == nil, keyDown(key) {
            return true
        }

        // 3. Focus traversal.
        if key.key == .tab {
            return key.modifiers.contains(.shift) ? focusPrevious() : focusNext()
        }

        // 4. Cold keys.
        return traverseVisible { $0.handleColdKey(key) }
    }

    private func routeMouse(_ mouse: MouseInput) -> Bool {
        guard let hit = hitTest(mouse.position) else {
            return false
        }

        if mouse.action == .press, hit.view.acceptsFirstResponder {
            makeFirstResponder(hit.view)
        }

        // Deliver in local coordinates, bubbling up toward the window with
        // the position translated at each step.
        var target: View? = hit.view
        var localPosition = hit.local

        while let view = target {
            var localMouse = mouse
            localMouse.position = localPosition

            if view.mouseEvent(localMouse) {
                return true
            }

            guard view !== self, let superview = view.superview else {
                return false
            }

            localPosition = localPosition + view.frame.origin
            target = superview
        }

        return false
    }
}
