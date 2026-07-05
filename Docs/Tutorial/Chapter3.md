# Chapter 3 — Controls & events (declarative)

The shell from Chapter 2 becomes a working app: a text field, an Add button,
the task list, and an About tab. This chapter is where TUIKit's event model
clicks — controls are ordinary values you keep references to, and they hand
you *semantic* events, never key codes.

## Controls are plain values

In TUIBuilder, a control declared inside the tree is fine when you never
talk to it again. When you do — read the field, append to the list — declare
it up front and drop it into the tree like any other component. From
`Tutorial/Milestones/Chapter3.swift`:

```swift
        // Controls are declared up front so the event closures below can
        // reach them; they drop into the builder tree like any component.
        let field = TextField(placeholder: "new task")
        let tasks = ListView(items: ["Ship Chapter 3"])
        let status = Label("Type a task and press Return — or click Add.", style: CellStyle(flags: .dim))

        // One code path for every way a task gets added.
        func addTask() {
            guard !field.text.isEmpty else {
                status.text = "type something first"
                return
            }

            tasks.items.append(field.text)
            field.setText("")
            status.text = "added — \(tasks.items.count) in the list"
        }
```

There's no state graph and no bindings — `tasks.items.append(...)` mutates
the real control, which redraws itself. That's the non-reactive model from
[`TUIBuilder.md`](../TUIBuilder.md) §6. (For syncing controls with a Swift
model, see [`DataBinding.md`](../DataBinding.md) — later, not needed here.)

## Semantic events

Applications never see raw keys; controls translate interaction into typed
closures. Three of them carry this whole app:

```swift
        // Semantic events: Return in the field submits…
        field.onSubmit = { _ in addTask() }

        // …a click (or arrows) moves the selection…
        tasks.onSelectionChanged = { index in
            if let index {
                status.text = "selected: \(tasks.items[index])"
            }
        }

        // …and Return or a double-click activates: mark the task done.
        tasks.onActivate = { index in
            tasks.items[index] = "✓ " + tasks.items[index]
            status.text = "completed: \(tasks.items[index])"
        }
```

Note the selection/activation split: a single click (or the arrow keys)
only *selects* — the list debounces clicks so selecting is never mistaken
for activating. Return or a double-click *activates*. You wire intent, and
the control owns the input details.

## Assembling the tabs

The content is now a `TabView` — each `Tab` holds one page, and the tab bar,
switching keys, and mouse handling come with it:

```swift
        window.setContent {
            TabView {
                Tab("Tasks") {
                    VStack(spacing: 1, insets: EdgeInsets(all: 1)) {
                        HStack(spacing: 1) {
                            field
                            Button("&Add") { addTask() }.role(.default)
                        }
                        tasks
                        status
                    }
                }
                Tab("About") {
                    VStack(spacing: 1, insets: EdgeInsets(all: 1)) {
                        Label("To-Do — the TUIKit tutorial app").bold()
                        Label("Chapter 3: controls and semantic events.")
                        Spacer()
                    }
                }
            }
        }

        // Start with the field focused so the reader can type immediately.
        window.makeFirstResponder(field)
```

Three details worth keeping:

- **`.role(.default)`** marks Add as the default button — it picks up the
  default-button styling and answers Return when focus isn't claiming it.
- **`"&Add"`** is a mnemonic, same as Chapter 1's `&Quit`: Alt+A clicks Add
  from anywhere.
- **`makeFirstResponder(field)`** puts the keyboard in the field on launch,
  so the reader types immediately. Every path — Return in the field, the
  button, Alt+A — funnels into the one `addTask()`.

## Run it

```sh
swift run TUIKitTutorial ch3
```

Things to try:

- Type a task and press Return; then add one with Alt+A instead.
- Arrow through the list (watch the status line follow the selection), then
  press Return on a task to complete it.
- Single-click a task — selection only. Double-click it — completed.
- Press Return with the field empty and read the status line.

You've learned the control model: plain values, semantic events, one code
path per action. Next chapter we add app-wide keyboard plumbing — and meet
the routing order that decides who sees a key first.
