# Chapter 6 — Traditional approach (hand-wired Chapter 3)

This is the appendix. The declarative style of Chapters 1–5 is the
recommended path — but TUIKit's builder is a construction convenience, not a
separate framework. Builders emit exactly the `TUIView` tree you would have
assembled by hand, so both styles produce identical objects, and themes,
focus, events, and headless testing work the same in each. Here we rebuild
Chapter 3's form with no builder in sight, to show what's underneath and
when dropping down is genuinely useful: when a view graph is dynamic
(views added and removed at runtime), or when a custom container wants full
control of its children's frames.

## Construct, anchor, wire, add

The hand-wired milestone has four steps. First, **construct** the views —
the same types the builder made for us, now made directly. From
`Tutorial/Milestones/Chapter6.swift`:

```swift
        // 1. Construct the views.
        let field = TextField(placeholder: "new task")
        let add = Button("&Add")
        add.role = .default
        let tasks = ListView(items: ["Ship Chapter 6"])
        let status = Label("The same app — not a builder in sight.", style: CellStyle(flags: .dim))
```

Compare with Chapter 3: `Button("&Add") { addTask() }.role(.default)` became
a bare `Button` plus `add.role = .default` — the modifier was only ever
sugar over the property.

Second, **anchor**. With no stack to line things up, each view pins its own
edges to the window; unpinned axes take the view's intrinsic size:

```swift
        // 2. Position them: anchors pin edges; unpinned axes take the
        //    view's intrinsic size (the button sizes itself, trailing-pinned).
        field.anchors = AnchorSet(leading: 1, trailing: 10, top: 1, height: 1)
        add.anchors = AnchorSet(trailing: 1, top: 1, height: 1)
        tasks.anchors = AnchorSet(leading: 1, trailing: 1, top: 3, bottom: 2)
        status.anchors = AnchorSet(leading: 1, trailing: 1, bottom: 0, height: 1)
```

This is the bookkeeping the `VStack`/`HStack` did for you — and the first
place hand-wiring costs something: the field's `trailing: 10` has to know
how wide the button is. Anchors still resize correctly (they're relative to
the window's edges), but the *relationships* between siblings are now yours
to maintain.

Third and fourth, **wire** the events — closure for closure identical to
Chapter 3, plus an explicit `add.onActivate` where the builder took a
trailing closure — and **add** everything to the window:

```swift
        field.onSubmit = { _ in addTask() }
        add.onActivate = { addTask() }

        tasks.onSelectionChanged = { index in
            if let index {
                status.text = "selected: \(tasks.items[index])"
            }
        }

        tasks.onActivate = { index in
            tasks.items[index] = "✓ " + tasks.items[index]
            status.text = "completed: \(tasks.items[index])"
        }

        // 4. Hang everything off the window.
        window.addSubview(field)
        window.addSubview(add)
        window.addSubview(tasks)
        window.addSubview(status)

        window.makeFirstResponder(field)
```

Everything from Chapters 3–5 carries over untouched: the semantic events,
`makeFirstResponder`, the Alt+A mnemonic, mouse handling — and the test
suite proves it, running the same typing walkthrough against this milestone
(`chapter6MatchesChapter3Behavior`) as against Chapter 3's.

Because the two styles are the same objects, they interleave freely — a
hand-built container can host builder content via `setContent`, and a
builder tree can contain hand-constructed views (that's how Chapters 3–5
dropped `field` and `tasks` into the tree). See
[`TUIBuilder.md`](../TUIBuilder.md) §12 for the interop rules, and the demo
app for both styles side by side: `Demo/TUIKitDemo/Declarative/` and
`Demo/TUIKitDemo/Traditional/` build screens of the same gallery each way.

## Run it

```sh
swift run TUIKitTutorial ch6
```

Things to try:

- Use it exactly like Chapter 3 — Return adds, arrows select, double-click
  completes. Nothing behaves differently.
- Resize and watch the anchors reflow; then compare the anchor arithmetic
  above with Chapter 3's stack, which needed none.
- Skim `Demo/TUIKitDemo/Traditional/` next to `Demo/TUIKitDemo/Declarative/`
  for the same comparison at demo scale.

You've seen the floor under the builder: construct, anchor, wire, add.
That's the whole tutorial — from here, [`TUIBuilder.md`](../TUIBuilder.md),
[`Themes.md`](../Themes.md), and [`DataBinding.md`](../DataBinding.md) are
the natural next reads.
