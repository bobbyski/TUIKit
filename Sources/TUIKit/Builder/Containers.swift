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
