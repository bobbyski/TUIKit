/// A component that builds its base, then applies a configuration closure to
/// the resulting view. The engine behind the structural modifiers.
public struct Configured<Base: Component>: Component {
    let base: Base
    let apply: (TUIView) -> Void

    /// Builds the base, then applies the configuration.
    public func makeView() -> TUIView {
        let view = base.makeView()
        apply(view)
        return view
    }
}

public extension Component {
    /// Applies an arbitrary configuration to the built view (the escape hatch
    /// behind the typed modifiers below).
    ///
    /// - Parameter apply: Configures the built view.
    /// - Returns: A component that builds `self`, then configures it.
    func configure(_ apply: @escaping (TUIView) -> Void) -> Configured<Self> {
        Configured(base: self, apply: apply)
    }

    /// Sets the view's `#id` for stylesheet selectors.
    func id(_ identifier: String) -> Configured<Self> {
        configure { $0.identifier = identifier }
    }

    /// Adds stylesheet `.class` names.
    func styleClass(_ names: String...) -> Configured<Self> {
        let set = Set(names)
        return configure { $0.styleClasses.formUnion(set) }
    }

    /// Overrides the theme for this view and its subtree.
    func theme(_ theme: Theme) -> Configured<Self> {
        configure { $0.theme = theme }
    }

    /// Attaches a style sheet to this view and its subtree.
    func styleSheet(_ sheet: StyleSheet) -> Configured<Self> {
        configure { $0.styleSheet = sheet }
    }

    /// Hides or shows the view.
    func hidden(_ hidden: Bool = true) -> Configured<Self> {
        configure { $0.isHidden = hidden }
    }

    /// Pins the view with an anchor set (for anchor-based parents).
    func anchors(_ set: AnchorSet) -> Configured<Self> {
        configure { $0.anchors = set }
    }

    /// Fills the parent (a bare window, a panel's content area, …).
    func fill(inset: Int = 0) -> Configured<Self> {
        anchors(.fill(inset: inset))
    }

    /// Centers the view in an anchor-based parent.
    func centered(width: Int? = nil, height: Int? = nil) -> Configured<Self> {
        anchors(.centered(width: width, height: height))
    }

    /// Constrains the view's size. A given `width`/`height` fixes that axis;
    /// the `min`/`max` variants clamp it.
    func frame(
        width: Int? = nil,
        height: Int? = nil,
        minWidth: Int? = nil,
        maxWidth: Int? = nil,
        minHeight: Int? = nil,
        maxHeight: Int? = nil
    ) -> Configured<Self> {
        configure { view in
            var minimum = view.minimumSize
            var maximum = view.maximumSize

            if let width {
                minimum.width = width
                maximum = Size(width: width, height: maximum?.height ?? .max)
            }

            if let height {
                minimum.height = height
                maximum = Size(width: maximum?.width ?? .max, height: height)
            }

            if let minWidth { minimum.width = minWidth }
            if let minHeight { minimum.height = minHeight }

            if let maxWidth { maximum = Size(width: maxWidth, height: maximum?.height ?? .max) }
            if let maxHeight { maximum = Size(width: maximum?.width ?? .max, height: maxHeight) }

            view.minimumSize = minimum
            view.maximumSize = maximum
        }
    }

    /// Wraps the view in a single-child container with padding around it.
    func padding(_ insets: EdgeInsets) -> Padded<Self> {
        Padded(base: self, insets: insets)
    }

    /// Wraps the view in a single-child container padded equally on all sides.
    func padding(all: Int) -> Padded<Self> {
        padding(EdgeInsets(all: all))
    }
}

/// A component that wraps its base in an inset container, adding padding.
public struct Padded<Base: Component>: Component {
    let base: Base
    let insets: EdgeInsets

    /// Builds the base inside a padded single-child container.
    public func makeView() -> TUIView {
        let container = VStack(insets: insets)
        let child = base.makeView()
        container.addSubview(child)
        return container
    }
}

/// A box for reaching a control created *inside* a builder from a sibling's
/// closure, without a preceding `let`.
///
/// ```swift
/// let field = Ref<TextField>()
/// VStack {
///     TextField().ref(field)
///     Button("Submit") { submit(field.value.text) }
/// }
/// ```
public final class Ref<T> {
    /// The referenced value, set once the component builds.
    public var value: T!

    /// Creates an empty reference.
    public init() {}
}

public extension Component where Self: TUIView {
    /// Captures the built control into a `Ref` for later imperative access.
    func ref(_ box: Ref<Self>) -> Self {
        box.value = self
        return self
    }
}
