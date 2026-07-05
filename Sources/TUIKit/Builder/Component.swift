/// Anything that produces a concrete TUIKit `TUIView`.
///
/// `Component` is the currency of the optional TUIBuilder layer (see
/// `Docs/TUIBuilder.md`). It is *not* reactive: `makeView()` runs once and
/// returns real control objects, which the retained-mode framework then owns.
/// Every `TUIView` is a `Component` (it is its own view), so all bundled controls
/// work in the DSL for free; user-defined compounds adopt `Composable`.
@MainActor
public protocol Component {
    /// Produces the concrete view this component describes.
    func makeView() -> TUIView
}

/// Every view is a leaf component: it *is* its own view.
extension TUIView: Component {
    /// A view is its own component — building returns `self`.
    public func makeView() -> TUIView { self }
}

/// A component defined by its `body` — the SwiftUI-shaped way to build your
/// own reusable control from other components.
///
/// ```swift
/// struct LabeledField: Composable {
///     let title: String
///     var body: some Component {
///         HStack(spacing: 1) { Label("\(title):").bold(); TextField() }
///     }
/// }
/// ```
///
/// A `Composable` is usable anywhere a bundled control is — its `makeView()`
/// (provided for free) builds its `body`.
@MainActor
public protocol Composable: Component {
    /// The component this one is composed of.
    associatedtype Body: Component

    /// What this component is made of.
    var body: Body { get }
}

public extension Composable {
    /// A composable's view is its body's view.
    func makeView() -> TUIView { body.makeView() }
}

/// Collects child components inside a container's trailing closure.
///
/// Supports plain lists, `if`/`if-else`, and `for` loops — all resolved once,
/// at build time (there is no reactivity to re-resolve them).
@MainActor
@resultBuilder
public enum NodeBuilder {
    /// Collects a single component.
    public static func buildExpression(_ component: any Component) -> [any Component] {
        [component]
    }

    /// Collects an already-built component list.
    public static func buildExpression(_ components: [any Component]) -> [any Component] {
        components
    }

    /// Flattens the block's parts.
    public static func buildBlock(_ parts: [any Component]...) -> [any Component] {
        parts.flatMap { $0 }
    }

    /// Keeps the `if` branch's parts (or none).
    public static func buildOptional(_ part: [any Component]?) -> [any Component] {
        part ?? []
    }

    /// Keeps the `if` branch's parts.
    public static func buildEither(first: [any Component]) -> [any Component] {
        first
    }

    /// Keeps the `else` branch's parts.
    public static func buildEither(second: [any Component]) -> [any Component] {
        second
    }

    /// Flattens a `for` loop's parts.
    public static func buildArray(_ parts: [[any Component]]) -> [any Component] {
        parts.flatMap { $0 }
    }
}
