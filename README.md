# TUIKit

An AppKit-inspired terminal UI framework for Swift.

**Repository:** [github.com/bobbyski/TUIKit](https://github.com/bobbyski/TUIKit)

TUIKit brings the architecture that made desktop UI programming pleasant —
view hierarchies, a responder chain, focus scopes, rich controls, layout, and
theming — to the terminal, built on Swift 6 concurrency from the first line.
No global statics, no `exit()` shutdowns, no escape sequences leaking into
application code.

> **Status: pre-alpha.** TUIKit is under active initial development. The
> build plan and progress dashboard live in [`PLAN.md`](PLAN.md); the design
> is described in [`Docs/Architecture.md`](Docs/Architecture.md). APIs will
> change without notice until the first tagged release.

## Why another terminal UI library?

Existing Swift options are ports of older designs: widget toolkits with
global application state, thread-unsafe main loops, and testing as an
afterthought. TUIKit is designed around five commitments:

- **AppKit's shape.** Views own local coordinates; containers own clipping
  and translation; a responder chain routes keys; windows and dialogs own
  their focus scopes. If you know AppKit, you know where things live.
- **Swift concurrency native.** `MainActor`-isolated UI, actor-backed
  drivers, `AsyncStream` input — no Dispatch ceremony, no thread rules to
  memorize.
- **Semantic events.** Controls own their keyboard and mouse behavior and
  emit meaning (`onActivate`, `onSelectionChanged`) — applications never see
  raw escape sequences.
- **Headless by design.** A built-in in-memory driver renders the same cells
  a terminal would, so every view and control is testable in CI without a
  TTY.
- **Deterministic rendering.** State + style + frame produce the same cells,
  every time.

## Requirements

- Swift 6.3 or later
- macOS 15+ or Linux (Windows planned)
- No third-party dependencies.
  [RichSwift](https://github.com/bobbyski/RichSwift), our in-house terminal
  formatting library, is pulled in (and re-exported) automatically for rich
  content rendering — depending on TUIKit is all you need.

## Installation

Add TUIKit to your `Package.swift`:

```swift
dependencies: [
    // Local path while pre-release, so changes are testable without
    // pushing. At the first tagged release this becomes:
    //   .package(url: "https://github.com/bobbyski/TUIKit.git", from: "0.1.0")
    .package(path: "../TUIKit"),
],
targets: [
    .target(name: "YourApp", dependencies: ["TUIKit"]),
]
```

## A quick look

Working code against today's API — Controls v1 is complete (see `PLAN.md`
for the full set: lists, tables, trees, menus, dialogs, split views, a
markdown reader, a syntax-highlighted editor, and more):

```swift
import TUIKit

let app = App(driver: ANSIDriver())
let window = Window()
window.theme = .ocean                       // or .homebrew, .manPage, …

let field = TextField(placeholder: "Your name")
let button = Button("Greet") {
    let dialog = Dialog(title: "Hello", message: "Hello, \(field.text)!")
    dialog.addButton("OK", isDefault: true)
    dialog.onDismiss = { [weak dialog] in dialog.map { app.dismiss($0) } }
    dialog.sizeToFit(in: window.frame.size)
    app.present(dialog)
}

let form = VStack(spacing: 1, insets: EdgeInsets(all: 1))
form.addSubview(field)
form.addSubview(button)
form.anchors = .fill()
window.addSubview(form)

try await app.run(window)
```

## Demo

The demo gallery shows every shipped capability and grows a section per
control as each lands — it doubles as the eyeball-testing surface:

```sh
swift run TUIKitDemo
```

## Testing

TUIKit's headless driver renders into an in-memory cell buffer and accepts
scripted input, so tests assert on rendered text and semantic events without
a live terminal:

```swift
let driver = HeadlessDriver(size: Size(width: 80, height: 24))
await driver.send(.key(KeyInput(key: .enter)))
#expect(await driver.snapshotText().contains { $0.contains("Hello") })
```

## Documentation

- [`PLAN.md`](PLAN.md) — build plan and progress dashboard.
- [`Docs/Architecture.md`](Docs/Architecture.md) — layers, ownership rules,
  and design rationale.
- [`NEEDS_HUMAN.md`](NEEDS_HUMAN.md) — human review checklist.

## Relationship to UILess

TUIKit is a standalone framework — it has no UILess dependency and works for
any terminal application. It is developed alongside
[UILess](../UILessFramework/README.md), which consumes it as one of several
renderers for UI-less applications.

## License

TUIKit is released under the BSD 3-Clause License. See [`LICENSE`](LICENSE)
for details.

Copyright © 2026 Bobby Skinner. All rights reserved.
