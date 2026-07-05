/// A flexible empty component that soaks up leftover space in a stack,
/// pushing its neighbours apart (the named form of a spacer view).
public final class Spacer: TUIView {
    /// Creates a spacer.
    ///
    /// - Parameter minLength: Smallest length the spacer keeps on the stack's
    ///   main axis.
    public init(minLength: Int = 0) {
        super.init(frame: .zero)
        minimumSize = Size(width: minLength, height: minLength)
    }
}

/// Overlapping children, each fill-anchored — later ones draw over earlier
/// ones (badges, overlays, watermarks). Its natural size is the largest
/// child's.
public final class ZStack: TUIView {
    /// Builds a Z-stack from a component list.
    ///
    /// - Parameter content: The overlapping children, back to front.
    public init(@NodeBuilder _ content: () -> [any Component]) {
        super.init(frame: .zero)

        for child in content() {
            let view = child.makeView()
            view.anchors = .fill()
            addSubview(view)
        }
    }

    /// The largest child's natural size.
    public override var intrinsicContentSize: Size? {
        let sizes = subviews.compactMap(\.intrinsicContentSize)

        guard !sizes.isEmpty else {
            return nil
        }

        return Size(
            width: sizes.map(\.width).max() ?? 0,
            height: sizes.map(\.height).max() ?? 0
        )
    }
}

public extension VStack {
    /// Builds a vertical stack from a component list.
    ///
    /// - Parameters:
    ///   - spacing: Cells between adjacent children.
    ///   - alignment: Cross-axis placement (defaults to `.fill`, so children
    ///     share the width and line up).
    ///   - insets: Padding inside the stack.
    ///   - content: The children.
    convenience init(
        spacing: Int = 0,
        alignment: StackAlignment = .fill,
        insets: EdgeInsets = .zero,
        @NodeBuilder _ content: () -> [any Component]
    ) {
        self.init(spacing: spacing, alignment: alignment, insets: insets)

        for child in content() {
            addSubview(child.makeView())
        }
    }
}

public extension HStack {
    /// Builds a horizontal stack from a component list.
    ///
    /// - Parameters:
    ///   - spacing: Cells between adjacent children.
    ///   - alignment: Cross-axis placement (defaults to `.fill`).
    ///   - insets: Padding inside the stack.
    ///   - content: The children.
    convenience init(
        spacing: Int = 0,
        alignment: StackAlignment = .fill,
        insets: EdgeInsets = .zero,
        @NodeBuilder _ content: () -> [any Component]
    ) {
        self.init(spacing: spacing, alignment: alignment, insets: insets)

        for child in content() {
            addSubview(child.makeView())
        }
    }
}

public extension ScrollView {
    /// Builds a scroll view whose document is the built children stacked
    /// vertically.
    ///
    /// - Parameter content: The document's children.
    convenience init(@NodeBuilder _ content: () -> [any Component]) {
        let document = VStack()

        for child in content() {
            document.addSubview(child.makeView())
        }

        self.init(document: document)
    }
}

/// One tab in a `TabView` builder: a title and its content.
@MainActor
public struct Tab {
    let title: String
    let content: any Component

    /// Creates a tab.
    ///
    /// - Parameters:
    ///   - title: Tab title.
    ///   - content: The tab's content (several are wrapped in a `VStack`).
    public init(_ title: String, @NodeBuilder _ content: () -> [any Component]) {
        self.title = title

        let children = content()

        if children.count == 1 {
            self.content = children[0]
        } else {
            let stack = VStack()
            children.forEach { stack.addSubview($0.makeView()) }
            self.content = stack
        }
    }
}

/// Collects `Tab`s inside a `TabView` builder.
@MainActor
@resultBuilder
public enum TabBuilder {
    /// Collects a single tab.
    public static func buildExpression(_ tab: Tab) -> [Tab] { [tab] }
    /// Flattens the block's parts.
    public static func buildBlock(_ parts: [Tab]...) -> [Tab] { parts.flatMap { $0 } }
    /// Keeps the `if` branch's parts (or none).
    public static func buildOptional(_ part: [Tab]?) -> [Tab] { part ?? [] }
    /// Keeps the `if` branch's parts.
    public static func buildEither(first: [Tab]) -> [Tab] { first }
    /// Keeps the `else` branch's parts.
    public static func buildEither(second: [Tab]) -> [Tab] { second }
    /// Flattens a `for` loop's parts.
    public static func buildArray(_ parts: [[Tab]]) -> [Tab] { parts.flatMap { $0 } }
}

public extension TabView {
    /// Builds a tab view from `Tab`s.
    ///
    /// ```swift
    /// TabView {
    ///     Tab("Form")  { form }
    ///     Tab("Files") { files }
    /// }
    /// ```
    ///
    /// - Parameter tabs: The tabs.
    convenience init(@TabBuilder _ tabs: () -> [Tab]) {
        self.init()

        for tab in tabs() {
            addTab(tab.title, content: tab.content.makeView())
        }
    }
}

public extension SplitView {
    /// Builds a split view from two panes (the first two components).
    ///
    /// ```swift
    /// SplitView(.horizontal) { sidebar; editor }
    /// ```
    ///
    /// - Parameters:
    ///   - axis: Direction the panes flow.
    ///   - content: The two panes.
    convenience init(_ axis: StackView.Axis, @NodeBuilder _ content: () -> [any Component]) {
        let views = content().map { $0.makeView() }
        self.init(
            axis: axis,
            first: views.first ?? Spacer(),
            second: views.count > 1 ? views[1] : Spacer()
        )
    }
}

public extension Panel {
    /// Builds a titled panel whose content is the built children stacked
    /// vertically and filling the content area.
    ///
    /// - Parameters:
    ///   - title: Title shown in the top border.
    ///   - body: The panel's content.
    convenience init(_ title: String = "", @NodeBuilder _ body: () -> [any Component]) {
        self.init(title)

        let stack = VStack()

        for child in body() {
            stack.addSubview(child.makeView())
        }

        stack.anchors = .fill()
        content.addSubview(stack)
    }
}
