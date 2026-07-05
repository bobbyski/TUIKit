# Chapter 1 — Hello, terminal

We're at the very beginning: no To-Do app yet, just the smallest possible
TUIKit program — an `App` on a driver, one `Window`, some declarative
content, and a clean exit. By the end of this chapter you'll understand every
line of a running TUIKit app, which is a short list of lines.

## App, driver, window

A TUIKit program is three objects. The **driver** owns the terminal — raw
mode, escape sequences, input decoding all stop there (see
[`Architecture.md`](../Architecture.md)). The **`App`** runs the event loop
on top of it. The **`Window`** is the root view you hand to `app.run(_:)`.
The tutorial runner ends with exactly this:

```swift
let app = App(driver: ANSIDriver())
try await app.run(milestone.makeWindow(app: app))
```

`run` suspends until the app stops — it's `async` all the way down; TUIKit
never blocks a thread. Everything else in this chapter happens inside
`makeWindow`.

## The milestone

Here is Chapter 1's entire window, from
`Tutorial/Milestones/Chapter1.swift`:

```swift
    /// A full-screen window with a greeting and a Quit button.
    public static func makeWindow(app: App) -> Window {
        // A zero-frame window fills the screen and follows resizes.
        let window = Window()

        // `setContent` installs a built component tree as the window's
        // (fill-anchored) root. Everything here is a plain TUIView underneath.
        window.setContent {
            VStack(spacing: 1, insets: EdgeInsets(all: 2)) {
                Label("Hello, terminal!").bold()
                Label("Every frame you see is cells — try resizing the window.")

                // The `&` marks a keyboard mnemonic: Alt+Q activates it, and
                // the Q renders in the theme's accelerator color.
                Button("&Quit") { app.stop() }

                // A flexible spacer keeps the content at the top.
                Spacer()
            }
        }

        return window
    }
```

Three things to notice.

**A zero-frame window is full screen.** `Window()` with no frame fills the
terminal and follows resizes — you will not compute a frame in this tutorial,
ever.

**`setContent` hosts a builder tree.** The closure is
[TUIBuilder](../TUIBuilder.md) syntax: the nesting on the page matches the
nesting on the screen. It's not reactive — the builder constructs a plain
`TUIView` tree once, and the retained-mode framework owns it from then on.

**Quitting is already handled.** Ctrl+C is built in. The `&` in `"&Quit"`
adds a second way: Alt+Q activates the button from anywhere, and the Q
renders in the theme's accelerator color. Clicking it works too — the
button's closure calls `app.stop()`, `run` returns, and the driver restores
the terminal.

## Even shorter: `app.run { }`

When you don't need to keep the window around, `Hosting.swift` offers sugar
that makes the window for you:

```swift
try await app.run {
    Panel("Hello") {
        VStack(spacing: 1, insets: EdgeInsets(all: 1)) {
            Label("Welcome to TUIKit").bold()
            Button("Quit") { app.stop() }
        }
    }
}
```

The tutorial uses the explicit `Window` form because later chapters configure
the window — but for a quick tool, this is the whole program.

## Run it

```sh
swift run TUIKitTutorial ch1
```

Things to try:

- Resize the terminal — the window follows; every frame is redrawn cells.
- Press Alt+Q (or click Quit) and note the terminal comes back clean.
- Restart and quit with Ctrl+C instead — same clean exit, built in.

You've learned the whole skeleton: driver → app → window → content. Next
chapter, that content becomes the To-Do app's shell — and you still won't
compute a single frame.
