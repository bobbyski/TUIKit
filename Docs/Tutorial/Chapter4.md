# Chapter 4 — Focus, keys & mouse

Chapter 3's form works, but every key it understands belongs to some control.
This chapter adds an *app-level* shortcut — Ctrl+N focuses the task field
from anywhere — and in doing so meets the rule that governs all TUIKit
input: the key routing order.

## Who sees a key first

When a key arrives at a window, it routes **hot → focused → Tab traversal →
cold**:

1. **Hot** — the window's hot-key pass runs first, before any control. This
   is where app-wide shortcuts like Ctrl+N live.
2. **Focused** — the first responder (the focused control) gets its turn:
   the text field eats characters, the list eats arrows.
3. **Tab traversal** — unclaimed Tab / Shift+Tab moves focus. You never
   implement this; it's free.
4. **Cold** — anything still unclaimed reaches window-level fallbacks, like
   mnemonics (Alt+A) finding their button.

To claim the hot pass, subclass `Window` and override `handleHotKey`. From
`Tutorial/Milestones/Chapter4.swift`:

```swift
public final class Chapter4Window: Window {
    /// Called when Ctrl+N asks for a new task from anywhere in the window.
    var onNewTask: () -> Void = {}

    /// The hot-key pass runs before focus routing — this fires even while
    /// the list or a button holds the keyboard.
    public override func handleHotKey(_ key: KeyInput) -> Bool {
        if key.modifiers == .control, key.key == .character("n") {
            onNewTask()
            return true
        }

        return false
    }
}
```

Return `true` to consume the key; return `false` and routing continues to
the focused control. The subclass stays dumb — it exposes an `onNewTask`
closure and lets `makeWindow` decide what "new task" means, keeping all the
app logic in one place.

## Wiring the shortcut

The rest of the milestone is Chapter 3's form (minus the tabs, to keep the
excerpt short) plus this one wire:

```swift
        // The window-level shortcut: focus the field, wherever keys were.
        window.onNewTask = { [weak window, weak field] in
            if let window, let field {
                window.makeFirstResponder(field)
                status.text = "^N — ready for a new task"
            }
        }
```

`makeFirstResponder(field)` moves the keyboard to the field no matter which
control had it — that's the same call Chapter 3 used at launch, now used
mid-flight.

Mnemonics recap: Alt+A still adds, because `Button("&Add")` registered the
mnemonic and the cold pass finds it. So the app now has three keyboard
layers working together — Ctrl+N (hot), typing and arrows (focused), Tab
and Alt+A (traversal and cold) — and none of them stepped on another.

**Mouse comes free.** Nothing in this chapter (or any chapter) handled a
mouse event, yet clicking focuses controls, clicks press buttons, and
double-click activates list rows. Controls own their mouse behavior the same
way they own their keys — see the ownership rules in
[`Architecture.md`](../Architecture.md).

## Run it

```sh
swift run TUIKitTutorial ch4
```

Things to try:

- Tab into the list, then press Ctrl+N — focus jumps straight back to the
  field, from anywhere.
- Type a task, press Return, then Alt+A an empty one — the mnemonic works
  regardless of focus.
- Click around: field, list rows, the Add button. No mouse code exists in
  the milestone.
- Resize while a task is selected — focus and selection survive the reflow.

You've learned how keys route and where app-wide shortcuts live. Next
chapter we prove all of this works — headlessly, in CI, with real tests you
can copy.
