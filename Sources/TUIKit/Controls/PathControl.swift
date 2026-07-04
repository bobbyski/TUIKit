/// Breadcrumb path bar: `Projects ▸ TUIKit ▸ Sources`.
///
/// Each crumb is clickable (or `←`/`→` + Return while focused) and reports
/// the *prefix path* down to that crumb — click `TUIKit` in the example
/// and `onPathSelected` receives `"Projects/TUIKit"`. The focused crumb
/// recolors to the theme's accent.
///
/// ```swift
/// let crumbs = PathControl(path: "/Users/bobby/Projects")
/// crumbs.onPathSelected = { prefix in browser.setRoot(prefix) }
/// ```
@MainActor
public final class PathControl: TUIView {
    /// The full path shown.
    public private(set) var path: String

    /// Called with the prefix path of the chosen crumb.
    public var onPathSelected: (String) -> Void = { _ in }

    // Path split into crumbs; whether the path was absolute.
    private var components: [String] = []
    private var isAbsolute = false

    // Crumb the keyboard has walked to.
    private var focusedCrumb = 0

    /// Creates a path control.
    ///
    /// - Parameter path: Initial path.
    public init(path: String = "") {
        self.path = path
        super.init(frame: .zero)
        rebuild()
    }

    /// Replaces the path (silent).
    ///
    /// - Parameter newPath: New path to show.
    public func setPath(_ newPath: String) {
        path = newPath
        rebuild()
        superview?.setNeedsLayout()
        setNeedsDisplay()
    }

    /// Path controls take keyboard focus.
    public override var acceptsFirstResponder: Bool {
        !components.isEmpty
    }

    /// One row at the crumbs' total width.
    public override var intrinsicContentSize: Size? {
        let text = components.reduce(0) { $0 + $1.count }
        let separators = max(0, components.count - 1) * 3   // " ▸ "
        return Size(width: text + separators, height: 1)
    }

    /// Draws the crumbs; the focused one wears the accent color. When the path
    /// is wider than the view it scrolls left so the tail (the deepest crumbs)
    /// stays visible — a filename never scrolls off the right edge.
    public override func draw(_ painter: Painter) {
        let theme = effectiveTheme
        let width = bounds.size.width
        var x = -shift

        for (index, component) in components.enumerated() {
            var style = CellStyle()

            if isFirstResponder, index == focusedCrumb, theme.accent != .standard {
                style.foreground = theme.accent
            }

            drawClipped(painter, component, x: &x, width: width, style: style)

            if index < components.count - 1 {
                drawClipped(painter, " ▸ ", x: &x, width: width, style: theme.placeholder)
            }
        }
    }

    // Writes a string starting at `x`, advancing it, painting only the cells
    // that fall inside [0, width) — so a left-scrolled path clips cleanly.
    private func drawClipped(_ painter: Painter, _ text: String, x: inout Int, width: Int, style: CellStyle) {
        for character in text {
            if x >= 0, x < width {
                painter.set(TerminalCell(character: character, style: style), at: Point(x: x, y: 0))
            }
            x += 1
        }
    }

    // How far the content is scrolled left so its tail stays visible.
    private var shift: Int {
        let total = (intrinsicContentSize?.width ?? 0)
        return max(0, total - bounds.size.width)
    }

    /// `←`/`→` walk the crumbs; Return chooses.
    public override func keyDown(_ key: KeyInput) -> Bool {
        guard key.modifiers.isEmpty, !components.isEmpty else {
            return false
        }

        switch key.key {
        case .left:
            moveFocus(to: focusedCrumb - 1)
            return true

        case .right:
            moveFocus(to: focusedCrumb + 1)
            return true

        case .home:
            moveFocus(to: 0)
            return true

        case .end:
            moveFocus(to: components.count - 1)
            return true

        case .enter:
            onPathSelected(prefixPath(to: focusedCrumb))
            return true

        default:
            return false
        }
    }

    /// Click a crumb to choose its prefix path.
    public override func mouseEvent(_ mouse: MouseInput) -> Bool {
        guard mouse.action == .press, mouse.button == .left else {
            return false
        }

        guard let index = crumbIndex(atX: mouse.position.x) else {
            return false
        }

        focusedCrumb = index
        setNeedsDisplay()
        onPathSelected(prefixPath(to: index))
        return true
    }

    // MARK: - Internals

    private func rebuild() {
        isAbsolute = path.hasPrefix("/")
        components = path.split(separator: "/").map(String.init)
        focusedCrumb = max(0, components.count - 1)
    }

    /// The path down to (and including) a crumb.
    ///
    /// - Parameter index: Crumb index.
    /// - Returns: The joined prefix, preserving absoluteness.
    public func prefixPath(to index: Int) -> String {
        let prefix = components.prefix(index + 1).joined(separator: "/")
        return isAbsolute ? "/" + prefix : prefix
    }

    private func crumbIndex(atX screenX: Int) -> Int? {
        // Map the screen x back into content coordinates through the scroll.
        let x = screenX + shift
        var start = 0

        for (index, component) in components.enumerated() {
            if x >= start, x < start + component.count {
                return index
            }

            start += component.count + 3
        }

        return nil
    }

    private func moveFocus(to index: Int) {
        let clamped = min(max(0, index), components.count - 1)

        if clamped != focusedCrumb {
            focusedCrumb = clamped
            setNeedsDisplay()
        }
    }
}
