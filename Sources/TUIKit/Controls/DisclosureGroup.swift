/// Collapsible section: a `▸/▾` header that shows or hides its content.
///
/// ```text
///   ▾ Advanced                ▸ Advanced
///     (content view)          (collapsed — content hidden)
/// ```
///
/// Space, Return, or clicking the header toggles. The group's intrinsic
/// height changes with expansion, so stacks reflow around it — the classic
/// collapsible form section. Hidden content drops out of the focus order
/// automatically.
///
/// ```swift
/// let advanced = DisclosureGroup("Advanced")
/// advanced.content.addSubview(optionsForm)
/// advanced.onExpansionChanged = { open in settings.advancedOpen = open }
/// ```
@MainActor
public final class DisclosureGroup: TUIView {
    /// Header text.
    public var title: String {
        didSet {
            if title != oldValue {
                superview?.setNeedsLayout()
                setNeedsDisplay()
            }
        }
    }

    /// Whether the content shows.
    public private(set) var isExpanded: Bool

    /// Container for the collapsible content.
    public let content = TUIView()

    /// Called when expansion changes through interaction or
    /// `setExpanded(_:notify:)`.
    public var onExpansionChanged: (Bool) -> Void = { _ in }

    /// Creates a disclosure group.
    ///
    /// - Parameters:
    ///   - title: Header text.
    ///   - isExpanded: Initial state.
    public init(_ title: String, isExpanded: Bool = false) {
        self.title = title
        self.isExpanded = isExpanded
        super.init(frame: .zero)
        addSubview(content)
        content.isHidden = !isExpanded
    }

    /// Disclosure groups take keyboard focus.
    public override var acceptsFirstResponder: Bool {
        true
    }

    /// Header row plus the content's natural height while expanded.
    public override var intrinsicContentSize: Size? {
        let contentSize = naturalContentSize
        let width = max(title.count + 2, contentSize.width)
        return Size(width: width, height: 1 + (isExpanded ? contentSize.height : 0))
    }

    // The content's natural size: its own intrinsic size, or (for the
    // common plain-container case) the largest intrinsic size among its
    // children — they overlay the same region.
    private var naturalContentSize: Size {
        if let size = content.intrinsicContentSize {
            return size
        }

        var width = 0
        var height = 0

        for subview in content.subviews {
            if let size = subview.intrinsicContentSize {
                width = max(width, size.width)
                height = max(height, size.height)
            }
        }

        return Size(width: width, height: height)
    }

    /// Sets the expansion programmatically.
    ///
    /// - Parameters:
    ///   - expanded: New state.
    ///   - notify: Whether `onExpansionChanged` fires. Defaults to silent.
    public func setExpanded(_ expanded: Bool, notify: Bool = false) {
        guard expanded != isExpanded else {
            return
        }

        isExpanded = expanded
        content.isHidden = !expanded
        invalidateAncestorLayout()   // intrinsic height changed
        setNeedsLayout()
        setNeedsDisplay()

        if notify {
            onExpansionChanged(isExpanded)
        }
    }

    /// Toggles, exactly as user interaction would.
    public func toggle() {
        isExpanded.toggle()
        content.isHidden = !isExpanded
        invalidateAncestorLayout()
        setNeedsLayout()
        setNeedsDisplay()
        onExpansionChanged(isExpanded)
    }

    // An intrinsic-size change must re-measure the whole ancestor chain —
    // the stack that sizes this group, the scroll view that sizes the
    // stack, and so on.
    private func invalidateAncestorLayout() {
        var view: TUIView? = superview

        while let current = view {
            current.setNeedsLayout()
            view = current.superview
        }
    }

    /// Positions the content below the header.
    public override func layoutSubviews() {
        content.frame = Rect(
            x: 0,
            y: 1,
            width: bounds.size.width,
            height: max(0, bounds.size.height - 1)
        )
    }

    /// Draws the disclosure triangle and title.
    public override func draw(_ painter: Painter) {
        let theme = effectiveTheme
        var triangleStyle = theme.header

        if isFirstResponder, theme.accent != .standard {
            triangleStyle.foreground = theme.accent
        }

        painter.write(isExpanded ? "▾" : "▸", at: .zero, style: triangleStyle)
        painter.write(
            " " + Label.truncated(title, width: max(0, bounds.size.width - 2)),
            at: Point(x: 1, y: 0),
            style: theme.header
        )
    }

    /// Space or Return toggles.
    public override func keyDown(_ key: KeyInput) -> Bool {
        guard key.modifiers.isEmpty else {
            return false
        }

        switch key.key {
        case .enter, .character(" "):
            toggle()
            return true

        default:
            return false
        }
    }

    /// Click on the header row toggles.
    public override func mouseEvent(_ mouse: MouseInput) -> Bool {
        guard mouse.action == .press, mouse.button == .left, mouse.position.y == 0 else {
            return false
        }

        toggle()
        return true
    }
}
