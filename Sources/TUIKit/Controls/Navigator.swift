/// A push/pop stack of views with a title per level.
///
/// ```text
///   ◂ Back   Appearance            ← header: Back (below the root) + title
///   ─────────────────────────
///   (the top view)
/// ```
///
/// Push a view with a title to drill in; Esc (or Backspace, when nothing
/// focused uses it), Enter on the header, or a click on `◂ Back` pops. Only
/// the top view is laid out and visible, so the levels below leave the
/// focus order, and the focus moves onto whatever was pushed or revealed.
/// This is the piece phone-width terminals, drill-down settings and
/// wizards all need.
///
/// ```swift
/// let settings = Navigator(root: menu, title: "Settings")
/// appearanceRow.onActivate = { settings.push(appearanceForm, title: "Appearance") }
/// settings.onDepthChanged = { depth in status.text = "level \(depth)" }
/// ```
@MainActor
public final class Navigator: TUIView {
    /// One level of the stack.
    public struct Level {
        /// The level's view.
        public let view: TUIView

        /// The level's title, shown in the header.
        public var title: String
    }

    /// The stack, root first.
    public private(set) var levels: [Level]

    /// How many levels are on the stack (the root is 1).
    public var depth: Int {
        levels.count
    }

    /// The view on top.
    public var topView: TUIView {
        levels[levels.count - 1].view
    }

    /// The title on top.
    public var title: String {
        levels[levels.count - 1].title
    }

    /// Whether the header row draws.
    public var showsHeader = true {
        didSet {
            if showsHeader != oldValue {
                setNeedsLayout()
                setNeedsDisplay()
            }
        }
    }

    /// The back affordance's text.
    public var backTitle = "◂ Back" {
        didSet {
            setNeedsDisplay()
        }
    }

    /// Called with the new depth after a push or pop.
    public var onDepthChanged: (Int) -> Void = { _ in }

    /// Creates a navigator showing its root.
    ///
    /// - Parameters:
    ///   - root: The first level's view.
    ///   - title: The first level's title.
    public init(root: TUIView, title: String) {
        levels = [Level(view: root, title: title)]
        super.init(frame: .zero)
        addSubview(root)
    }

    /// The header takes focus once there is a Back to press, so Enter pops
    /// even when the top view holds nothing focusable.
    public override var acceptsFirstResponder: Bool {
        depth > 1
    }

    /// The top view's natural size plus the header.
    public override var intrinsicContentSize: Size? {
        guard let size = topView.intrinsicContentSize else {
            return nil
        }

        return Size(width: max(size.width, backTitle.count + title.count + 4), height: size.height + (showsHeader ? 1 : 0))
    }

    /// Drills in.
    ///
    /// - Parameters:
    ///   - view: The new top view.
    ///   - title: Its title.
    public func push(_ view: TUIView, title: String) {
        topView.isHidden = true
        levels.append(Level(view: view, title: title))
        addSubview(view)
        reveal(view)
        onDepthChanged(depth)
    }

    /// Renames the top level — a wizard's step counter, a document's dirty
    /// marker.
    ///
    /// - Parameter title: The new header title.
    public func setTitle(_ title: String) {
        guard levels[levels.count - 1].title != title else {
            return
        }

        levels[levels.count - 1].title = title
        setNeedsDisplay()
    }

    /// Comes back one level.
    ///
    /// - Returns: `true` when there was a level to pop.
    @discardableResult
    public func pop() -> Bool {
        guard depth > 1 else {
            return false
        }

        let leaving = levels.removeLast()
        leaving.view.removeFromSuperview()
        topView.isHidden = false
        reveal(topView)
        onDepthChanged(depth)
        return true
    }

    /// Comes all the way back.
    public func popToRoot() {
        guard depth > 1 else {
            return
        }

        while levels.count > 1 {
            levels.removeLast().view.removeFromSuperview()
        }

        topView.isHidden = false
        reveal(topView)
        onDepthChanged(depth)
    }

    /// The top view fills everything below the header.
    public override func layoutSubviews() {
        let headerHeight = showsHeader ? 1 : 0

        for level in levels {
            level.view.isHidden = level.view !== topView
        }

        topView.frame = Rect(x: 0, y: headerHeight, width: bounds.size.width, height: max(0, bounds.size.height - headerHeight))
    }

    /// Draws the header: Back (below the root) and the title.
    public override func draw(_ painter: Painter) {
        guard showsHeader, bounds.size.width > 0, bounds.size.height > 0 else {
            return
        }

        let theme = effectiveTheme
        painter.fill(Rect(x: 0, y: 0, width: bounds.size.width, height: 1), with: TerminalCell(character: " ", style: theme.header))

        var x = 1

        if depth > 1 {
            var back = theme.header

            if isFirstResponder, let cue = theme.cueAccent(over: back.background) {
                back.foreground = cue
            }

            painter.write(backTitle, at: Point(x: x, y: 0), style: back)
            x += backTitle.count + 3
        }

        painter.write(Label.truncated(title, width: max(0, bounds.size.width - x)), at: Point(x: x, y: 0), style: theme.header)
    }

    /// Esc and Backspace pop (bubbled up from the top view when unused);
    /// Enter pops while the header is focused.
    public override func keyDown(_ key: KeyInput) -> Bool {
        guard key.modifiers.isEmpty, depth > 1 else {
            return false
        }

        switch key.key {
        case .escape, .backspace:
            return pop()

        case .enter where isFirstResponder:
            return pop()

        default:
            return false
        }
    }

    /// A click on `◂ Back` pops.
    public override func mouseEvent(_ mouse: MouseInput) -> Bool {
        guard showsHeader, depth > 1, mouse.action == .press, mouse.button == .left,
              mouse.position.y == 0, (1...(backTitle.count)).contains(mouse.position.x) else {
            return false
        }

        return pop()
    }

    // Lays the new top out and moves the focus onto it (or the header).
    private func reveal(_ view: TUIView) {
        setNeedsLayout()
        setNeedsDisplay()
        superview?.setNeedsLayout()   // the intrinsic size follows the top view

        if let window = owningWindow, !window.makeFirstResponder(view) {
            window.makeFirstResponder(acceptsFirstResponder ? self : nil)
        }
    }
}
