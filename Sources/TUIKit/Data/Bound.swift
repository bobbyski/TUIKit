/// Generates a `$`-prefixed `Binding` projection for a model property.
///
/// ```swift
/// final class Profile {          // a class — the binding writes back via self
///     @Bound var name: String = ""
///     @Bound var age: Int = 0
/// }
///
/// let profile = Profile()
/// TextField().bind(profile.$name)     // Binding<String> to profile.name
/// Stepper().bind(profile.$age)        // Binding<Int> to profile.age
/// ```
///
/// Requires an explicit type annotation (the macro expands syntactically) and
/// a reference-type enclosing scope. This is sugar over `Bindings(profile).name`
/// — see `Docs/DataBinding.md`.
@attached(peer, names: arbitrary)
public macro Bound() = #externalMacro(module: "TUIKitMacros", type: "BoundMacro")
