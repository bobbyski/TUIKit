# TUIBuilder — a declarative builder for TUIKit

**Status: core implemented; layer growing.** The core (`Component`,
`Composable`, `NodeBuilder`), container builder-inits (`VStack`/`HStack`/
`ScrollView`/`Panel`), `Spacer`, structural + typed modifiers, and `Ref` ship
in `Sources/TUIKit/Builder/`; the `--interactive` demo's default window is
built with them. Still to come: `Form`/`Field`, `Grid`/`GridRow`, `ZStack`,
and `App.run { }` hosting (see §13). This document describes the whole
*optional* declarative layer over TUIKit's controls. It reads like SwiftUI
at the call site — nested containers, trailing-closure children, chained
modifiers — but it is **not reactive**: there is no state graph, no bindings,
no diffing, no invalidation. It is a construction convenience that builds a
plain TUIKit `TUIView` tree **once**, which the existing retained-mode framework
then owns and redraws exactly as it does today.

The layer is purely additive. Every imperative pattern in `Docs/Architecture.md`
keeps working; TUIBuilder is a nicer way to *assemble* the same views. A
program can mix the two freely, file by file or line by line.

Design authority carries over from `../PLAN.md` and `Documents/AICoding rules.md`:
controls still own their interaction state, semantic events still flow out as
typed closures, raw input still lives at the framework edge, and everything is
still headless-testable. TUIBuilder adds no new runtime behavior — it emits the
same objects you would have `addSubview`'d by hand.

---

## Guiding principles

Four rules shape every API choice in this document. If a proposed API breaks
one of them, the API is wrong.

1. **Defaults first — declare only your differences.** Every control is usable
   bare: `TextField()`, `Button("OK")`, `Slider()`, `DatePicker()`. Every
   modifier is optional and additive. You write the *delta* from a sensible
   default and nothing else — no required configuration, no ceremony.

2. **The parent lines things up — you don't.** In the builder you never compute
   a `frame` and never set an `anchor` for the common case. Placing a control in
   a container hands its layout to that container: a `VStack` left-aligns and
   full-widths its children, an `HStack` lays them in a row, a `Form` aligns the
   label and field columns so every row lines up. Manual `frame`/`anchors` stay
   available as an *override*, never a requirement.

3. **Readable top to bottom.** The nesting on the page matches the nesting on
   the screen. There is no layout bookkeeping between the lines — the structure
   *is* the layout, so a screen reads like an outline of itself.

4. **The manual approach is a peer, not a legacy.** TUIBuilder is one option.
   Any screen can still be built with `addSubview` and explicit frames/anchors,
   and the two styles are the *same objects* — they interleave line by line
   (§12). Nothing you learn in one style is wasted in the other.

The rest of the document is these four rules made concrete.

---

## Contents

- [Guiding principles](#guiding-principles)
1. [Why (and why not reactive)](#1-why-and-why-not-reactive)
2. [The one idea: describe → build once](#2-the-one-idea-describe--build-once)
3. [A taste](#3-a-taste)
4. [The core: `Component`, `Composable`, `@NodeBuilder`](#4-the-core-component-composable-nodebuilder)
5. [Primitives, containers, and modifiers](#5-primitives-containers-and-modifiers)
6. [Events and the non-reactive update model](#6-events-and-the-non-reactive-update-model)
7. [Compound controls — the headline feature](#7-compound-controls--the-headline-feature)
8. [Hosting into a Window / App](#8-hosting-into-a-window--app)
9. [Layout, alignment, and Grid](#9-layout-alignment-and-grid)
10. [Worked examples](#10-worked-examples)
11. [Determinism and testing](#11-determinism-and-testing)
12. [Interop with imperative TUIKit](#12-interop-with-imperative-tuikit)
13. [Implementation plan](#13-implementation-plan)
14. [Open questions](#14-open-questions)
15. [Non-goals](#15-non-goals)

---

## 1. Why (and why not reactive)

Building a screen imperatively is correct but verbose. Compare assembling a
labeled form row today:

```swift
let row = HStack(spacing: 1)
row.addSubview(Label("Name:", style: CellStyle(flags: .bold)))
let field = TextField(placeholder: "type a name")
field.onSubmit = { store.name = $0 }
row.addSubview(field)
```

with the same thing declaratively:

```swift
HStack(spacing: 1) {
    Label("Name:").bold()
    TextField(placeholder: "type a name").onSubmit { store.name = $0 }
}
```

The declarative form nests to match the visual nesting, so a whole screen
reads top-to-bottom the way it looks. That is the entire benefit we are after.

**Why not reactive.** SwiftUI's real cost is its runtime: `@State`,
`@Binding`, `body` re-evaluation, identity/diffing, and the invalidation
engine. TUIKit is already a retained-mode toolkit whose controls own their
state and redraw themselves on mutation (`setNeedsDisplay`). Layering a second
state model on top would duplicate that and fight it. So TUIBuilder deliberately
stops at **construction**:

- `body` is evaluated **once**, when the view is built.
- There is no `@State`; to change something later you hold a reference to the
  real control and mutate it — which is exactly today's model (see §6).
- There is no diffing. To replace a subtree you rebuild it and swap the view.

This keeps the mental model tiny: *the DSL is a constructor, not a runtime.*

## 2. The one idea: describe → build once

Everything below reduces to a single protocol requirement:

```swift
@MainActor func makeView() -> TUIView
```

A **Component** is anything that can produce a concrete TUIKit `TUIView`. The
built-in controls already *are* views, so they are trivially components. A
user's compound control is a component whose `makeView()` builds its `body`.
`@NodeBuilder` is just sugar for collecting child components into a container.

There is no wrapper runtime, no shadow tree — `makeView()` returns the same
`Button`/`VStack`/… objects you use today. Once built, TUIBuilder is out of the
picture.

## 3. A taste

```swift
import TUIKit

let panel = Panel("Preferences") {
    VStack(spacing: 1, insets: EdgeInsets(all: 1)) {
        HStack(spacing: 1) {
            Label("Theme:").bold()
            PopUpButton(items: Theme.builtIn.map(\.name))
                .onSelectionChanged { applyTheme($0) }
        }

        Toggle("Wrap long lines").onChange { editor.wraps = $0 }

        if showAdvanced {
            DisclosureGroup("Advanced") {
                Stepper(value: 4, in: 1...16).onValueChanged { editor.tabWidth = $0 }
            }
        }

        Spacer()

        HStack(spacing: 2) {
            Spacer()
            Button("Cancel") { dismiss() }
            Button("Save") { save() }.style(.tinted)
        }
    }
}

window.setContent { panel }
```

`if showAdvanced { … }` is a plain compile-time/`build`-time branch — it is
evaluated once when the panel is built, not tracked. That is the whole
non-reactive story.

## 4. The core: `Component`, `Composable`, `@NodeBuilder`

The currency is one method — "produce a view." Every `TUIView` already can, so
every control is a component; user compounds add a `body`.

```swift
@MainActor
public protocol Component {
    func makeView() -> TUIView
}

// Every view is a leaf component: it *is* its own view. One extension, no
// per-control boilerplate.
extension TUIView: Component {
    public func makeView() -> TUIView { self }
}
```

So `Button`, `Label`, `VStack`, `TableView`, `DatePicker`, … are all usable in
the DSL immediately, and any control the framework adds later is too, for free.

**Compounds** adopt `Composable`, which adds the SwiftUI-shaped `body` and
derives `makeView()` for free:

```swift
@MainActor
public protocol Composable: Component {
    associatedtype Body: Component
    var body: Body { get }
}

public extension Composable {
    func makeView() -> TUIView { body.makeView() }
}
```

> **Why two protocols?** The toolkit already uses `body` as a property name
> (`Dialog.body`), so a single `Component` protocol *requiring* `body` would
> collide when `TUIView` conforms. Splitting the leaf currency (`Component`,
> `makeView`) from the compound shape (`Composable`, `body`) keeps both clean:
> controls conform to `Component`, your compounds conform to `Composable`.

**The builder.** `@NodeBuilder` gathers children as `any Component`:

```swift
@resultBuilder
public enum NodeBuilder {
    public static func buildExpression(_ c: any Component) -> [any Component] { [c] }
    public static func buildExpression(_ cs: [any Component]) -> [any Component] { cs }
    public static func buildBlock(_ parts: [any Component]...) -> [any Component] { parts.flatMap { $0 } }
    public static func buildOptional(_ part: [any Component]?) -> [any Component] { part ?? [] }
    public static func buildEither(first: [any Component]) -> [any Component] { first }
    public static func buildEither(second: [any Component]) -> [any Component] { second }
    public static func buildArray(_ parts: [[any Component]]) -> [any Component] { parts.flatMap { $0 } }
}
```

`buildOptional`/`buildEither`/`buildArray` give `if`, `if/else`, and `for`
inside a container — resolved once at build time.

## 5. Primitives, containers, and modifiers

TUIBuilder does **not** introduce a parallel type hierarchy. It adds
result-builder initializers to the existing container classes and chainable
methods to the existing controls. The names you already know are the names you
use.

**Everything has defaults; you add only differences.** A control with no
modifiers is a valid, complete component. Compare the bare and customized
forms:

```swift
TextField()                                        // placeholder none, empty
TextField(placeholder: "name").onSubmit { save($0) }   // only the two deltas

Slider()                                            // 0…100, step 1, value 0
Slider(value: 40).onValueChanged { volume = $0 }    // only what differs

Button("OK")                                        // tinted, no action
Button("OK") { confirm() }                          // add the action
```

**The container does the layout — you never set a frame or anchor.** Every
child below is placed by its parent; none of these examples computes a
position or size. That is principle #2 in code:

```swift
VStack(spacing: 1) {        // children left-align and fill the width
    Label("Title").bold()
    TextField(placeholder: "…")
    Button("Go") { }
}
```

Explicit `frame`/`anchors` remain available (§9) for the rare case a container
default is not what you want — but they are an override, never a prerequisite.

### Containers (builder initializers)

| Component | Builds | New initializer |
|-----------|--------|-----------------|
| `VStack` / `HStack` | the stack + its children | `init(spacing:alignment:insets:) { … }` |
| `Form` *(new, aligned)* | a two-column `Grid`; label + field columns line up | `init { Field("Name") { … } }` (§9) |
| `ZStack` *(new, tiny)* | overlapping children, fill-anchored | `init { … }` |
| `Grid` | `GridView` | `init(columns:) { GridRow { … } }` (§9) |
| `ScrollView` | scroll + document | `init { … }` (wraps children in a VStack document) |
| `AbsoluteLayout` | hand-placed children (**no** auto-layout) | `init { … }` + `.place(_:at:)` — the manual-placement escape hatch |
| `Panel` | titled panel; children go in `content` | `init(_ title:) { … }` |
| `TabView` | tabs | `init { Tab("Form") { … }; Tab("Files") { … } }` |
| `SplitView` | two panes | `init(_ axis:) { first; second }` |

Default cross-axis alignment is `.fill`, so a `VStack`'s children share its
width and line up on the left edge without a word of layout code; an `HStack`
gives its children a common row height. Those defaults *are* "line up in the
parent."

Example initializer (the pattern for all of them):

```swift
public extension VStack {
    convenience init(
        spacing: Int = 0,
        alignment: StackAlignment = .fill,
        insets: EdgeInsets = .zero,
        @NodeBuilder _ content: () -> [any Component]
    ) {
        self.init(spacing: spacing, alignment: alignment, insets: insets)
        for child in content() { addSubview(child.makeView()) }
    }
}
```

### Primitives (sugar over `init`)

Most controls already have good initializers, so no new type is needed —
`Label("Hi")`, `TextField(placeholder: "…")`, `Slider(value: 40, in: 0...100)`
work in the DSL as-is. Two small conveniences round it out:

- `Spacer(minLength: Int = 0)` — a flexible empty view (today's `TUIView()`
  spacer, named).
- `Divider(axis:)` — already exists; usable directly.

### Modifiers

Modifiers come in two flavors.

**Structural modifiers** (available on *any* component) build the child, then
configure or wrap the resulting view. They return an opaque component so they
chain:

```swift
public extension Component {
    func padding(_ insets: EdgeInsets) -> some Component            // wraps in an inset container
    func padding(all: Int) -> some Component
    func frame(width: Int? = nil, height: Int? = nil,
               minWidth: Int? = nil, maxWidth: Int? = nil,
               minHeight: Int? = nil, maxHeight: Int? = nil) -> some Component
    func anchors(_ set: AnchorSet) -> some Component
    func fill(inset: Int = 0) -> some Component                     // anchors(.fill(inset:))
    func centered(width: Int? = nil, height: Int? = nil) -> some Component
    func theme(_ theme: Theme) -> some Component
    func styleSheet(_ sheet: StyleSheet) -> some Component
    func styleClass(_ names: String...) -> some Component           // sets styleClasses
    func id(_ identifier: String) -> some Component
    func hidden(_ hidden: Bool = true) -> some Component
    func configure(_ apply: @escaping (TUIView) -> Void) -> some Component   // escape hatch
}
```

They are all implemented over one tiny type:

```swift
public struct Configured<Base: Component>: Component {
    let base: Base
    let apply: (TUIView) -> Void
    public var body: Never { fatalError() }
    public func makeView() -> TUIView { let v = base.makeView(); apply(v); return v }
}
// e.g. func id(_ s: String) -> some Component { Configured(base: self) { $0.identifier = s } }
```

**Typed modifiers** (available on a *specific* control) set that control's
config/events and return the concrete control, so they still count as a leaf
component. These are thin, and live next to each control:

```swift
public extension Button {
    @discardableResult func onActivate(_ f: @escaping () -> Void) -> Self { onActivate = f; return self }
    @discardableResult func style(_ s: ControlStyle) -> Self { style = s; return self }
    @discardableResult func bold() -> Self { /* label styling */ return self }
}

public extension TextField {
    @discardableResult func onChange(_ f: @escaping (String) -> Void) -> Self { onChanged = f; return self }
    @discardableResult func onSubmit(_ f: @escaping (String) -> Void) -> Self { onSubmit = f; return self }
}

public extension Label {
    @discardableResult func bold() -> Self { style.flags.insert(.bold); return self }
    @discardableResult func dim() -> Self { style.flags.insert(.dim); return self }
    @discardableResult func align(_ a: TextAlignment) -> Self { alignment = a; return self }
}
```

Because these return `Self` (a real control, i.e. a leaf component), they mix
with structural modifiers seamlessly:

```swift
Button("Save") { save() }.style(.tinted).padding(all: 1).id("save-button")
```

## 6. Events and the non-reactive update model

Events are **typed closures set at construction** — the same `onActivate`,
`onChanged`, `onSelectionChanged`, `onValueChanged`, `onDateChanged`, … the
controls already expose. There is no binding indirection: the closure is the
wire.

To *change* a control after the screen is built, hold a reference and mutate
it — the control redraws itself, exactly as in imperative TUIKit. Because the
builder consumes the **real reference-type control**, you can simply declare it
first and drop it into the tree:

```swift
let name = TextField(placeholder: "name")
let greeting = Label("")

let form = VStack(spacing: 1) {
    name.onChange { greeting.text = $0.isEmpty ? "" : "Hi, \($0)" }
    greeting
    Button("Clear") { name.setText(""); greeting.text = "" }
}
```

`name` and `greeting` are ordinary controls; the closures capture and mutate
them directly. No `@State`, no reactivity — and it is fully testable through
the headless driver because it is just controls calling setters.

For inline capture without a preceding `let`, an optional `Ref<T>` box is
offered:

```swift
let field = Ref<TextField>()
VStack {
    TextField(placeholder: "name").ref(field)
    Button("Submit") { submit(field.value.text) }
}
```

`Ref` is a trivial `final class Ref<T> { var value: T! }`; `.ref(_)` is a
`configure` that assigns. It exists only so a control created *inside* the
builder can be reached from a sibling's closure.

## 7. Compound controls — the headline feature

A compound control is a `Composable` — a `Component` with a `body`. Once defined it is usable
**anywhere a bundled control is** — inside builders, as a window's content, or
`makeView()`'d into imperative code. This is the "build your own, use it like
ours" goal.

```swift
struct LabeledField: Composable {
    let title: String
    var placeholder = ""
    var onChange: (String) -> Void = { _ in }

    var body: some Component {
        HStack(spacing: 1) {
            Label("\(title):").bold().frame(minWidth: 10)
            TextField(placeholder: placeholder).onChange(onChange)
        }
    }
}
```

Use it exactly like `Button` or `Slider`:

```swift
VStack(spacing: 1) {
    LabeledField(title: "Name",  placeholder: "full name") { store.name = $0 }
    LabeledField(title: "Email", placeholder: "you@host")  { store.email = $0 }
}
```

(For a *column* of labeled rows whose fields all align, prefer the built-in
`Form` from §9 — it measures the label column for you. `LabeledField` here is
shown to illustrate the compound mechanism, not as the way to build a form.)

Compounds nest and compose:

```swift
struct StatCard: Composable {
    let title: String
    let value: String

    var body: some Component {
        Panel(title) {
            VStack(spacing: 0, insets: EdgeInsets(all: 1)) {
                Label(value).bold().align(.center)
                Label(title).dim().align(.center)
            }
        }
        .frame(minWidth: 14, minHeight: 4)
    }
}

HStack(spacing: 2) {
    StatCard(title: "Open",   value: "37")
    StatCard(title: "Closed", value: "12")
    StatCard(title: "Merged", value: "\(prCount)")
}
```

### When you need identity: a class-based compound

If a compound needs to expose its own imperative API (methods, live setters,
its own semantic event), define it as a **`TUIView` subclass** that builds its
subtree with the DSL in `init`. It is then a leaf component *and* a normal
control — this is exactly how the bundled composites (`ColorPicker`,
`FileDialog`) are structured, now written declaratively:

```swift
public final class SearchList: TUIView {
    public var onSelect: (String) -> Void = { _ in }

    private let field = TextField(placeholder: "filter…")
    private let list = ListView()
    private let all: [String]

    public init(_ items: [String]) {
        self.all = items
        super.init(frame: .zero)

        field.onChanged = { [weak self] query in self?.filter(query) }
        list.onActivate = { [weak self] i in self?.emit(i) }

        // Build the layout declaratively, then adopt it as this view's tree.
        let content = VStack(spacing: 0) {
            field
            list
        }
        content.anchors = .fill()
        addSubview(content)
        filter("")
    }

    public override var acceptsFirstResponder: Bool { false }   // composite scope

    private func filter(_ query: String) {
        list.items = query.isEmpty ? all
            : all.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    private func emit(_ index: Int) { onSelect(list.items[index]) }
}
```

`SearchList("…")` now drops into any builder and any imperative
`addSubview` — identical to a bundled control. **The rule of thumb:** value-type
`Component` for pure layout composition; `TUIView`-subclass for a control with its
own identity, state, or events.

## 8. Hosting into a Window / App

Two convenience seams connect a component tree to the run loop:

```swift
public extension Window {
    /// Replaces the window's content with a single fill-anchored root built
    /// from the components (wrapping several in a VStack).
    func setContent(@NodeBuilder _ content: () -> [any Component])
}

public extension App {
    /// Runs an app whose key window's content is the built tree.
    func run(@NodeBuilder _ content: () -> [any Component]) async throws
}
```

```swift
let app = App(driver: ANSIDriver())
try await app.run {
    Panel("Hello") {
        VStack(spacing: 1, insets: EdgeInsets(all: 1)) {
            Label("Welcome to TUIKit").bold()
            Button("Quit") { app.stop() }
        }
    }
}
```

`setContent` builds once, fill-anchors the root, and hands it to the ordinary
window/render machinery. Nothing about focus, routing, theming, or the run loop
changes.

## 9. Layout, alignment, and Grid

Layout stays TUIKit's: containers own frames, `AnchorSet` pins leaves, min/max
clamp. The DSL only renames the entry points — and, per principle #2, you reach
for these only to *override* a default, never to achieve the common case.

- `.padding(all: 1)` wraps the child in a one-child container with `insets`
  (or, inside a stack, folds into the stack's own `insets` where possible).
- `.frame(minWidth:maxWidth:…)` sets `minimumSize`/`maximumSize`.
- `.fill()` / `.centered()` / `.anchors(…)` set `anchors` for anchor-based
  parents (e.g. a `Panel.content` or a bare `Window`).

### Automatic alignment: `Form`

The most common "line up" need is a column of labeled controls whose fields all
start at the same x. `Form` does that with **zero** layout code: it measures the
label column and aligns every field, so you only name the field and drop in the
control.

```swift
Form {
    Field("Name")    { TextField(placeholder: "your name") }
    Field("Email")   { TextField(placeholder: "you@host") }
    Field("Theme")   { PopUpButton(items: Theme.builtIn.map(\.name)) }
    Field("Density") { SegmentedControl(["Compact", "Cozy", "Roomy"], selectedIndex: 1) }
}
```

Renders with the labels right-aligned into a shared column and the controls
lined up beside them:

```text
    Name:  ┃your name            ┃
   Email:  ┃you@host             ┃
   Theme:   Standard ▾
 Density:   Compact  Cozy  Roomy
```

`Form` lowers to `Grid(columns: [.fitContent, .flexible()])` — one `GridRow` per
`Field`, the title in column 0, the control in column 1. Because the label
column is `.fitContent`, it sizes to the widest label and everything aligns
automatically. Overrides exist (`Form(labelWidth:)`, `Field(align:)`) but are
rarely needed. This is principle #2 at its most literal: you declare *what* each
row is, and the container decides *where* everything goes.

### `Grid`

The general case needs placement metadata. Proposed shape:

```swift
Grid(columns: [.fitContent, .flexible(1), .fixed(6)], columnSpacing: 1, rowSpacing: 0) {
    GridRow {
        Label("Name").bold()
        TextField(placeholder: "…")
        Button("Edit") { }
    }
    GridRow {
        Label("Notes").bold()
        TextField(placeholder: "…")
        Button("Edit") { }
    }
}
```

`GridRow` maps its children left-to-right onto columns and advances the row.
Spans use a modifier:

```swift
GridRow {
    Label("Full-width header").gridSpan(columns: 3)
}
```

`@GridBuilder` collects `GridRow`s; each `GridRow` lowers to `place(_, column:,
row:, columnSpan:, rowSpan:)` calls on the underlying `GridView`. (This is the
most involved container and is scheduled last — see §13.)

## 10. Worked examples

### A settings screen

Note how little is on each line: a bare control plus the one or two deltas that
matter, and no layout code — `Form` lines the rows up, the `VStack` stacks the
sections, the trailing `HStack` right-justifies the buttons with a `Spacer`.

```swift
struct SettingsScreen: Composable {
    let store: Settings

    var body: some Component {
        Panel("Settings") {
            VStack(spacing: 1, insets: EdgeInsets(all: 1)) {

                // Labeled rows line themselves up — no widths, no anchors.
                Form {
                    Field("Name")    { TextField(placeholder: "your name").onChange { store.name = $0 } }
                    Field("Theme")   { PopUpButton(items: Theme.builtIn.map(\.name)).onSelectionChanged { store.themeIndex = $0 } }
                    Field("Density") { SegmentedControl(["Compact", "Cozy", "Roomy"], selectedIndex: 1).onSelectionChanged { store.density = $0 } }
                }

                Toggle("Enable telemetry", isOn: store.telemetry).onChange { store.telemetry = $0 }

                Spacer()

                HStack(spacing: 2) {
                    Spacer()                              // pushes the buttons to the right
                    Button("Reset") { store.reset() }
                    Button("Apply") { store.apply() }     // .tinted is already the default
                }
            }
        }
    }
}
```

### A reusable card list (compound built from a compound)

```swift
struct TaskRow: Composable {
    let task: Task
    var onToggle: (Bool) -> Void = { _ in }

    var body: some Component {
        HStack(spacing: 1) {
            Toggle("", isOn: task.done).onChange(onToggle)
            Label(task.title).frame(maxWidth: 40)
            Spacer()
            Label(task.due).dim()
        }
    }
}

struct TaskList: Composable {
    let tasks: [Task]

    var body: some Component {
        ScrollView {
            VStack(spacing: 0) {
                for task in tasks {                       // build-time loop
                    TaskRow(task: task) { markDone(task, $0) }
                }
            }
        }
    }
}
```

Both `TaskRow` and `TaskList` are now first-class: usable in a bigger builder,
a window's `setContent`, or `addSubview(TaskList(tasks: …).makeView())`.

## 11. Determinism and testing

Because `makeView()` runs once and returns concrete controls, TUIBuilder adds
no nondeterminism. A built tree renders through the headless driver like any
other, so components are tested exactly like controls:

```swift
@Test @MainActor func statCardRendersValueAndTitle() {
    let card = StatCard(title: "Open", value: "37").makeView()
    let window = Window(frame: Rect(x: 0, y: 0, width: 16, height: 4))
    card.anchors = .fill()
    window.addSubview(card)

    let lines = SceneRenderer(root: window).render(size: window.frame.size).textLines()
    #expect(lines.contains { $0.contains("37") })
    #expect(lines.contains { $0.contains("Open") })
}
```

Guidance: test compounds by `makeView()` + headless render (structure and
events), the same contract-test discipline the controls use. The DSL surface
itself gets a few tests proving `if/else`/`for` lower correctly and that
modifiers set the expected view properties.

## 12. Interop with imperative TUIKit

The two styles are the same objects, so they interleave with no bridge:

```swift
// Imperative outer, declarative inner:
let panel = Panel("Log")
panel.content.addSubview(
    VStack(spacing: 0) {
        for line in lines { Label(line) }
    }.makeView().fill()          // .fill() here is the imperative helper, or set anchors
)

// Declarative outer, imperative inner:
VStack {
    myHandBuiltToolbar          // any existing TUIView instance is a component
    LabeledField(title: "Q") { search($0) }
}
```

Rule: `component.makeView()` drops down to imperative; any `TUIView` instance
lifts up to declarative for free. There is never a wrapper to unwrap.

## 13. Implementation plan

Small, phased, each phase independently useful and independently tested. This
is an optional module; it can ship after TUIKit 1.0 without blocking anything.

| Phase | Deliverable | Notes |
|-------|-------------|-------|
| B0 | `Component`, `@NodeBuilder`, `TUIView`/`Never` conformances | The core; unlocks every existing control in the DSL. |
| B1 | Container initializers: `VStack`/`HStack`/`ZStack`/`ScrollView`/`Panel` | Result-builder `convenience init`s; `ZStack` is a new ~30-line container. |
| B2 | Structural modifiers + `Configured` + `Spacer`/`Ref` | `padding`, `frame`, `anchors`/`fill`/`centered`, `theme`, `id`, `styleClass`, `hidden`, `configure`. |
| B3 | Typed modifiers per control | `onActivate`/`onChange`/`style`/`bold`/… — mechanical, one small extension per control. |
| B4 | Hosting: `Window.setContent`, `App.run { }` | Connects to the run loop. |
| B5 | `TabView`/`SplitView` builders | `Tab("…") { }` / two-pane closure. |
| B6 | `Grid` + `GridRow` + `@GridBuilder` + `.gridSpan` | The placement-metadata container; the fiddliest, so it comes late. |
| B7 | `Form` + `Field` (over `Grid`) | The auto-aligning labeled form — principle #2's flagship; builds on B6. |
| B8 | Docs + a declarative rewrite of one demo tab | Prove the DSL builds the *same* tree the imperative demo does (headless-identical). |

**File layout** (new, under `Sources/TUIKit/Builder/`):

```
Builder/
  Component.swift        // protocol, NodeBuilder, TUIView/Never conformances
  Containers.swift       // VStack/HStack/ZStack/ScrollView/Panel/TabView/SplitView inits
  Modifiers.swift        // Configured, structural modifiers, Spacer, Ref
  ControlModifiers.swift // typed per-control chainable setters
  Grid.swift             // Grid/GridRow/@GridBuilder
  Form.swift             // Form/Field (aligned two-column grid)
  Hosting.swift          // Window.setContent, App.run { }
```

No changes to existing control sources except (optionally) moving each
control's typed modifiers next to it. Nothing in the core framework depends on
`Builder/`, so the module is deletable without touching controls.

**Testing:** a `BuilderTests` suite proving (a) leaves/compounds build the
expected view types, (b) `if`/`for` lower correctly, (c) modifiers set the
documented properties, and (d) a compound renders identically to its
hand-built equivalent through the headless driver.

## 14. Open questions

- **Namespacing.** Reusing the control class names (`VStack`, `Button`) keeps
  one vocabulary but means the builder `init`s live on those classes. Do we
  ever want a `TUI.` value-type facade instead? (Leaning no — the reference-type
  reuse is the feature.)
- **`padding` semantics.** Wrap in a container vs. fold into a parent stack's
  `insets`. Wrapping is simpler and composes; folding avoids an extra view.
  Start with wrapping; optimize later.
- **`Spacer` in non-stack parents.** Only meaningful inside a stack; in other
  containers it is inert. Document, don't enforce.
- **`ZStack` alignment.** v1 fill-anchors every child; per-child alignment can
  come later via `.anchors`.
- **Grid ergonomics.** `GridRow` (implicit rows) vs. explicit
  `.gridCell(column:row:)`. Proposal favors `GridRow`; revisit against real
  layouts in B6.
- **Result-builder limits.** `buildLimitedAvailability` and `for`-with-`where`
  are out of scope until a real need appears.

## 15. Non-goals

To keep the layer honest, TUIBuilder will **not**:

- introduce `@State`, `@Binding`, `ObservableObject`, or any reactivity;
- diff, reconcile, or re-invoke `body` after the initial build;
- own layout, focus, theming, or input — those stay in the view layer;
- wrap controls in a shadow tree or hide the real `TUIView` objects;
- become mandatory — every screen can still be built imperatively.

It is a construction convenience with SwiftUI's *look* and none of its runtime.
When you need to change the UI, you hold a control and call a setter, the same
as today.
