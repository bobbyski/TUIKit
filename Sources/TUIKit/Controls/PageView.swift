/// Paged content: one page at a time, dots beneath, arrows either side.
///
/// ```text
///   ┌────────────────────────┐
///   │       (page 2 of 3)    │
///   ◂        ○ ● ○           ▸
/// ```
///
/// `←`/`→` (and PageUp/PageDown) turn pages when the focus is on the page
/// view — or on something inside the page that does not use the arrows.
/// Clicking an arrow or a dot turns too. Only the current page is laid out
/// and visible, so hidden pages leave the focus order; turning a page moves
/// the focus onto the new page when it had been inside the old one.
///
/// ```swift
/// let tour = PageView(pages: [welcome, features, finish])
/// tour.onPageChanged = { index in footer.text = "Step \(index + 1) of 3" }
/// ```
@MainActor
public final class PageView: TUIView {
    /// The pages, in order.
    public private(set) var pages: [TUIView]

    /// Index of the page showing.
    public private(set) var currentIndex: Int

    /// Whether the dots-and-arrows row draws beneath the page.
    public var showsControls = true {
        didSet {
            if showsControls != oldValue {
                setNeedsLayout()
                setNeedsDisplay()
            }
        }
    }

    /// Called when the page changes through interaction or
    /// `setCurrentIndex(_:notify:)`.
    public var onPageChanged: (Int) -> Void = { _ in }

    /// Creates a page view.
    ///
    /// - Parameters:
    ///   - pages: The pages, in order.
    ///   - currentIndex: The page to show first.
    public init(pages: [TUIView], currentIndex: Int = 0) {
        self.pages = pages
        self.currentIndex = pages.isEmpty ? 0 : min(max(0, currentIndex), pages.count - 1)
        super.init(frame: .zero)

        for (index, page) in pages.enumerated() {
            page.isHidden = index != self.currentIndex
            addSubview(page)
        }
    }

    /// Page views take keyboard focus, so the arrows work with nothing
    /// focusable on a page.
    public override var acceptsFirstResponder: Bool {
        true
    }

    /// The largest page plus the controls row.
    public override var intrinsicContentSize: Size? {
        let sizes = pages.compactMap(\.intrinsicContentSize)
        let width = max(sizes.map(\.width).max() ?? 0, pages.count * 2 + 3)
        let height = (sizes.map(\.height).max() ?? 0) + (showsControls ? 1 : 0)
        return Size(width: width, height: height)
    }

    /// Shows a page programmatically.
    ///
    /// - Parameters:
    ///   - index: The page to show, clamped.
    ///   - notify: Whether `onPageChanged` fires. Defaults to silent.
    public func setCurrentIndex(_ index: Int, notify: Bool = false) {
        guard !pages.isEmpty else {
            return
        }

        let target = min(max(0, index), pages.count - 1)

        guard target != currentIndex else {
            return
        }

        turn(to: target)

        if notify {
            onPageChanged(currentIndex)
        }
    }

    /// Turns forward, exactly as `→` would.
    ///
    /// - Returns: `true` when there was a next page.
    @discardableResult
    public func next() -> Bool {
        guard currentIndex + 1 < pages.count else {
            return false
        }

        turn(to: currentIndex + 1)
        onPageChanged(currentIndex)
        return true
    }

    /// Turns back, exactly as `←` would.
    ///
    /// - Returns: `true` when there was a previous page.
    @discardableResult
    public func previous() -> Bool {
        guard currentIndex > 0 else {
            return false
        }

        turn(to: currentIndex - 1)
        onPageChanged(currentIndex)
        return true
    }

    /// The current page fills everything above the controls row.
    public override func layoutSubviews() {
        let pageHeight = max(0, bounds.size.height - (showsControls ? 1 : 0))

        for (index, page) in pages.enumerated() {
            page.isHidden = index != currentIndex

            if index == currentIndex {
                page.frame = Rect(x: 0, y: 0, width: bounds.size.width, height: pageHeight)
            }
        }
    }

    /// Draws the arrows and dots.
    public override func draw(_ painter: Painter) {
        guard showsControls, bounds.size.width >= 3, bounds.size.height >= 1, !pages.isEmpty else {
            return
        }

        let theme = effectiveTheme
        let y = bounds.size.height - 1
        let dim = CellStyle(foreground: theme.placeholderForeground, background: theme.background)
        var live = theme.base

        if let cue = theme.cueAccent(over: theme.background) {
            live.foreground = cue
        }

        painter.write("◂", at: Point(x: 0, y: y), style: currentIndex > 0 ? live : dim)
        painter.write("▸", at: Point(x: bounds.size.width - 1, y: y), style: currentIndex + 1 < pages.count ? live : dim)

        for (index, x) in dotColumns.enumerated() {
            painter.write(index == currentIndex ? "●" : "○", at: Point(x: x, y: y), style: index == currentIndex ? live : dim)
        }
    }

    /// Arrows and PageUp/PageDown turn pages.
    public override func keyDown(_ key: KeyInput) -> Bool {
        guard key.modifiers.isEmpty else {
            return false
        }

        switch key.key {
        case .left, .pageUp:
            return previous()

        case .right, .pageDown:
            return next()

        default:
            return false
        }
    }

    /// Clicks on the arrows or dots turn pages.
    public override func mouseEvent(_ mouse: MouseInput) -> Bool {
        guard showsControls, mouse.action == .press, mouse.button == .left,
              mouse.position.y == bounds.size.height - 1 else {
            return false
        }

        let x = mouse.position.x

        if x == 0 {
            return previous()
        }

        if x == bounds.size.width - 1 {
            return next()
        }

        if let index = dotColumns.firstIndex(of: x), index != currentIndex {
            turn(to: index)
            onPageChanged(currentIndex)
            return true
        }

        return false
    }

    // Dot columns, centred, two cells apart.
    private var dotColumns: [Int] {
        let span = pages.count * 2 - 1
        let start = max(1, (bounds.size.width - span) / 2)
        return (0..<pages.count).map { start + $0 * 2 }
    }

    // Switches pages and keeps the focus on a visible page.
    private func turn(to index: Int) {
        let previousPage = pages[currentIndex]
        currentIndex = index
        setNeedsLayout()
        setNeedsDisplay()

        if let window = owningWindow, let focused = window.firstResponder,
           focused.isDescendant(of: previousPage) {
            if !window.makeFirstResponder(pages[index]) {
                window.makeFirstResponder(self)
            }
        }
    }
}
