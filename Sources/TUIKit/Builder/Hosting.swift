public extension TUIView {
    /// Replaces this view's children with a single fill-anchored root built
    /// from the components (several are wrapped in a `VStack`).
    ///
    /// Call this on a plain view or a panel's `content` — not on a stack,
    /// which owns its children's frames and ignores the fill anchors, sizing
    /// the content to its intrinsic height instead.
    ///
    /// Use it to hand a built tree to a window or a panel's content area:
    ///
    /// ```swift
    /// window.setContent {
    ///     VStack(spacing: 1) { Label("Hi").bold(); Button("Quit") { app.stop() } }
    /// }
    /// ```
    ///
    /// - Parameter content: The content to install.
    /// - Returns: The installed root view.
    @discardableResult
    func setContent(@NodeBuilder _ content: () -> [any Component]) -> TUIView {
        for subview in subviews {
            subview.removeFromSuperview()
        }

        let views = content().map { $0.makeView() }
        let root: TUIView

        if views.count == 1 {
            root = views[0]
        } else {
            let stack = VStack()
            views.forEach { stack.addSubview($0) }
            root = stack
        }

        root.anchors = .fill()
        addSubview(root)
        return root
    }
}

public extension App {
    /// Runs an app whose key window's content is the built component tree.
    ///
    /// ```swift
    /// try await app.run {
    ///     Panel("Hello") {
    ///         VStack(spacing: 1, insets: EdgeInsets(all: 1)) {
    ///             Label("Welcome to TUIKit").bold()
    ///             Button("Quit") { app.stop() }
    ///         }
    ///     }
    /// }
    /// ```
    ///
    /// - Parameter content: The window's content.
    /// - Throws: Any driver startup error.
    func run(@NodeBuilder _ content: () -> [any Component]) async throws {
        let window = Window()
        window.setContent(content)
        try await run(window)
    }
}
