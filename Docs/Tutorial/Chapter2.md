# Chapter 2 — Layout: the app shell

Chapter 1 gave us a window with a greeting. Now we lay out the To-Do app's
skeleton: a header row, a two-pane content area, and a status line. The whole
point of this chapter is what you *won't* do — compute a frame. Stacks and
intrinsic sizes do all of it, and resize just works.

## Rows and columns

TUIKit's builder layout is two containers deep: `VStack` stacks children top
to bottom, `HStack` left to right. Each child is either **intrinsic** — it
knows its natural size, like a one-row `Label` or a `Divider` — or
**flexible**, like a `Panel` or `Spacer`, which stretches to share whatever
space the intrinsic children leave behind. That one distinction is the entire
layout model: fixed rows keep their height, flexible rows split the rest.

Here is the shell, from `Tutorial/Milestones/Chapter2.swift`:

```swift
        window.setContent {
            VStack(spacing: 0) {
                // Header: one intrinsic row.
                Label(" To-Do").bold()
                Divider(axis: .horizontal)

                // Content: two titled panels sharing the flexible middle.
                // Panels draw their own border and inset their content.
                HStack(spacing: 1) {
                    Panel("Tasks") {
                        Label("(the form arrives in Chapter 3)")
                    }
                    Panel("Details") {
                        Label("(select a task to see it here)")
                    }
                }

                // Status: one intrinsic row pinned to the bottom by the
                // flexible content above it.
                Divider(axis: .horizontal)
                Label(" Ready.", style: CellStyle(flags: .dim))
            }
        }
```

Read it top to bottom and you've read the screen top to bottom — that's
builder rule three from [`TUIBuilder.md`](../TUIBuilder.md).

**The header and status are intrinsic.** A `Label` is one row; a `Divider`
is one row. The `VStack` gives each exactly that.

**The `HStack` is the flexible middle.** It's the only flexible child of the
`VStack`, so it takes every row the header and status don't — which is what
pins the status line to the bottom without anyone saying "bottom".

**Panels bring their own chrome.** `Panel("Tasks")` draws a titled border
and insets its content; the two panels are both flexible, so the `HStack`
splits the width between them evenly. Their colors come from the current
theme (see [`Themes.md`](../Themes.md)) — nothing here picks a color.

Notice also what `Spacer` did in Chapter 1 and doesn't need to do here: a
`Spacer` is just an empty flexible child you add when *nothing else* is
flexible and you want the slack to go somewhere specific.

## Run it

```sh
swift run TUIKitTutorial ch2
```

Things to try:

- Resize the terminal in both directions — header and status stay one row,
  the panels absorb every change.
- Make the terminal very narrow and watch the two panels split whatever's
  left, borders intact.
- Count the layout code you just read: two stacks, zero frames.

You've learned the layout model — intrinsic children keep their size,
flexible children share the rest. Next chapter the "Tasks" panel gets a real
form: controls, events, and a list that actually holds tasks.
