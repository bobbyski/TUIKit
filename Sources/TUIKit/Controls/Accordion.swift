/// Titled sections that open one at a time, or share the space.
///
/// ```text
///   ▾ General                ▸ General
///     (content)              ▾ Appearance
///   ▸ Appearance               (content)
///   ▸ Advanced               ▸ Advanced
/// ```
///
/// The sections are ordinary `DisclosureGroup`s — Space, Return or a click
/// on a header toggles — coordinated by the accordion: in `.exclusive`
/// mode opening one closes the others; in `.shared` mode every open
/// section gets an equal share of the height left after the headers.
///
/// ```swift
/// let settings = Accordion(mode: .exclusive)
/// settings.addSection("General", content: generalForm, isExpanded: true)
/// settings.addSection("Appearance", content: themeForm)
/// settings.onSectionChanged = { index, open in remember(index, open) }
/// ```
@MainActor
public final class Accordion: TUIView {
    /// How open sections relate.
    public enum Mode: Hashable, Sendable {
        /// Opening a section closes the others.
        case exclusive

        /// Open sections split the space.
        case shared
    }

    /// How open sections relate.
    public var mode: Mode {
        didSet {
            if mode != oldValue {
                if mode == .exclusive, let first = sections.firstIndex(where: \.isExpanded) {
                    for (index, section) in sections.enumerated() where index != first {
                        section.setExpanded(false)
                    }
                }

                setNeedsLayout()
            }
        }
    }

    /// The sections, in order.
    public private(set) var sections: [DisclosureGroup] = []

    /// Called with a section's index and new state when it opens or closes
    /// through interaction or `setExpanded(_:_:notify:)`.
    public var onSectionChanged: (Int, Bool) -> Void = { _, _ in }

    /// Creates an empty accordion.
    ///
    /// - Parameter mode: Exclusive (the default) or shared.
    public init(mode: Mode = .exclusive) {
        self.mode = mode
        super.init(frame: .zero)
    }

    /// Appends a section.
    ///
    /// - Parameters:
    ///   - title: Header text.
    ///   - content: The section's content; fills the section when open.
    ///   - isExpanded: Whether it starts open (in `.exclusive` mode this
    ///     closes the others).
    /// - Returns: The section's disclosure group.
    @discardableResult
    public func addSection(_ title: String, content: TUIView, isExpanded: Bool = false) -> DisclosureGroup {
        let section = DisclosureGroup(title, isExpanded: false)
        content.anchors = .fill()
        section.content.addSubview(content)
        sections.append(section)
        addSubview(section)

        section.onExpansionChanged = { [weak self, weak section] open in
            guard let self, let section, let index = self.sections.firstIndex(where: { $0 === section }) else {
                return
            }

            self.coordinate(opened: open ? index : nil)
            self.onSectionChanged(index, open)
        }

        if isExpanded {
            setExpanded(sections.count - 1, true)
        }

        setNeedsLayout()
        return section
    }

    /// Opens or closes a section programmatically.
    ///
    /// - Parameters:
    ///   - index: The section.
    ///   - expanded: The new state.
    ///   - notify: Whether `onSectionChanged` fires. Defaults to silent.
    public func setExpanded(_ index: Int, _ expanded: Bool, notify: Bool = false) {
        guard sections.indices.contains(index), sections[index].isExpanded != expanded else {
            return
        }

        sections[index].setExpanded(expanded)
        coordinate(opened: expanded ? index : nil)

        if notify {
            onSectionChanged(index, expanded)
        }
    }

    /// Headers plus the natural height of whatever is open.
    public override var intrinsicContentSize: Size? {
        let widths = sections.compactMap { $0.intrinsicContentSize?.width }
        let heights = sections.map { $0.intrinsicContentSize?.height ?? 1 }
        return Size(width: widths.max() ?? 0, height: heights.reduce(0, +))
    }

    /// Headers one row each; open sections split what is left.
    public override func layoutSubviews() {
        guard !sections.isEmpty else {
            return
        }

        let open = sections.filter(\.isExpanded)
        let leftover = max(0, bounds.size.height - sections.count)
        let share = open.isEmpty ? 0 : leftover / open.count
        var remainder = open.isEmpty ? 0 : leftover - share * open.count
        var y = 0

        for section in sections {
            var height = 1

            if section.isExpanded {
                height += share + (remainder > 0 ? 1 : 0)
                remainder = max(0, remainder - 1)
            }

            section.frame = Rect(x: 0, y: y, width: bounds.size.width, height: min(height, max(0, bounds.size.height - y)))
            y += height
        }
    }

    // Enforces exclusivity after a section opened, and reflows.
    private func coordinate(opened index: Int?) {
        if mode == .exclusive, let index {
            for (position, section) in sections.enumerated() where position != index && section.isExpanded {
                section.setExpanded(false)
            }
        }

        setNeedsLayout()
        setNeedsDisplay()
    }
}
