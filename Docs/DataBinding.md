# TUIKit — Data In / Out

Moving a screen's data in and out, **non-reactively**. Like the rest of
TUIKit, there is no state graph, no observation, no diffing: data moves at
moments you choose (`load()`/`save()`), or — opt-in — the instant a control is
edited. Controls still own their state and redraw themselves; this layer only
gets values across the boundary.

Everything lives under `Sources/TUIKit/Data/` and is additive — the control
sources are untouched (all conformances are extensions), so the layer is
optional and removable.

## Two surfaces, one foundation

Both surfaces sit on `ValueControl` — every value control can read/write its
primitive value type-erased, always through its **silent** setter (so writing
never re-fires the control's event, making the operations safe to repeat):

```swift
public protocol ValueControl: TUIView {
    func anyValue() -> Any
    func setAnyValue(_ value: Any) throws   // silent; light numeric/string coercion
}
```

Conformances (in `ValueControl.swift`): `TextField`/`ComboBox`/
`SyntaxTextView`/`PathControl`/`Label` → `String`; `Checkbox`/`ToggleButton`
→ `Bool`; `Slider`/`Stepper`/`LevelIndicator`/`TabView` → `Int`;
`SegmentedControl`/`RadioGroup`/`PopUpButton`/`ListView`/`TableView` → `Int?`;
`DatePicker` → `Date`; `ColorPicker` → `TerminalColor`; `ProgressIndicator` →
`Double`.

### 1. Named / dynamic — for serialization, scripting, tests

Give controls a `name` (distinct from the stylesheet `identifier`), then
address them by dotted path at any depth, or move the whole form as a
dictionary:

```swift
let city = TextField().named("city")
address.addSubview(city)                     // address is .named("address")

try root.value(for: "address.city")          // -> Any
try root.setValue("Seattle", for: "address.city")

let snapshot = root.formValues()             // ["address.city": "Seattle", …]
try root.applyValues(snapshot)               // unknown keys ignored; mismatches throw
```

Keys are the join of ancestor `name`s down to each named `ValueControl`.
Lookup walks **all** descendants (including hidden — hidden fields still hold
data), first match wins per segment.

### 2. Typed / bound — for a Swift model

Bind a control's value to a model property, then sync the tree. `load()` pulls
model→controls, `save()` pushes controls→model; both are idempotent.

```swift
final class Profile { var name = ""; var age = 0 }      // a class (reference type)
let model = Profile()

let form = VStack {
    Field("Name") { TextField().bind(model, \.name) }   // key-path binding
    Field("Age")  { Stepper(value: 0, in: 0...120).bind(model, \.age) }
}

form.load()   // model → controls
// … user edits …
form.save()   // controls → model
```

For value-type models (structs), bind with explicit closures via `Binding`:

```swift
field.bind(Binding(get: { box.name }, set: { box.name = $0 }))
```

Get `$model.property` ergonomics two ways. **No macro**, via `Bindings`:

```swift
let $form = Bindings(model)          // @dynamicMemberLookup over a class
field.bind($form.name)               // Binding<String> to model.name
```

Or, most simply, with the **`@Bound` macro** on the model's properties — the
type is inferred from the literal initializer, so there's no ceremony:

```swift
final class Profile {                // a class (the setter writes via self)
    @Bound var name = ""             // → `$name : Binding<String>`
    @Bound var age = 0               // → `$age : Binding<Int>`
    @Bound var due: Date = .now      // non-literal types: annotate
}
let model = Profile()
field.bind(model.$name)              // Binding<String> to model.name
```

**Live push (opt-in).** `bind(..., live: true)` also pushes on every edit,
composing with the control's existing change handler:

```swift
field.onChanged = { validate($0) }       // set the handler first…
field.bind(model, \.name, live: true)    // …then bind: both run on edit
```

Order matters — `live` wraps the handler present at bind time, so bind *after*
wiring `onChanged`.

## Choosing a surface

| Need | Use |
|---|---|
| Dump/restore a whole form, JSON-ish, scripting, headless assertions | `formValues()` / `applyValues()` / `value(for:)` |
| Type-safe sync to a Swift model | `bind(model, \.kp)` + `load()`/`save()` |
| Update the model as the user types | `bind(..., live: true)` |

The two coexist: a control can be both named and bound.

## Testing

All of it is headless and deterministic (`Tests/TUIKitTests/DataBindingTests.swift`):
round-trip per type, coercion, silent writes (event counter stays 0),
dotted-path read/write + `notFound`, dict dump/apply, key-path `load`/`save`
idempotence, and `live` composition.

## Dependency note

The `@Bound` macro is implemented in the `TUIKitMacros` compiler-plugin target,
which depends on **`swift-syntax`** — the one non-in-house dependency in the
project. It is confined to the macro plugin (build-time only); the TUIKit
library's *runtime* stays dependency-free, and everything except `@Bound` works
with no swift-syntax involvement. If you'd rather avoid the dependency
entirely, use `Bindings` (`@dynamicMemberLookup`) for the same `$model.x`
ergonomics and drop the macro target from `Package.swift`.
