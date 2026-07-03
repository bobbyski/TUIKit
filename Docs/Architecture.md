# TUIKit Architecture

TUIKit is an AppKit-inspired terminal UI framework. This document describes
its layers and the ownership rules between them; the build plan and progress
live in [`../PLAN.md`](../PLAN.md).

## Layers

```text
+---------------------------------------------------------------+
|  Application code                                             |
|  builds views, receives semantic events (onActivate, ...)     |
+-------------------------------+-------------------------------+
                                |
+-------------------------------v-------------------------------+
|  Controls (Phase 6)            Label Button TextField List ...|
|  own interaction state, keyboard model, mouse behavior        |
+-------------------------------+-------------------------------+
                                |
+-------------------------------v-------------------------------+
|  Views & Layout (Phases 3-5)                                  |
|  View hierarchy, local coords, clipping, responder chain,     |
|  focus scopes, stack/anchor layout                            |
+-------------------------------+-------------------------------+
                                |  CellBuffer out / TerminalInput in
+-------------------------------v-------------------------------+
|  Driver layer (Phase 2)                                       |
|  TerminalDriver protocol                                      |
|    ANSIDriver      raw mode + escape output + input decoding  |
|    HeadlessDriver  in-memory buffer + scripted input (tests)  |
|  ANSIEncoder       pure style -> SGR encoding (shared)        |
+---------------------------------------------------------------+
```

## Ownership Rules

- **Raw input stops at the driver.** Escape sequences, termios, and size
  probing exist only inside driver implementations. Everything above deals
  in `TerminalInput` (typed keys, mouse, resize) and `CellBuffer`.
- **Cells are the rendering currency.** Views draw cells into buffers;
  drivers present buffers. Rendering is deterministic: state + style +
  frame → the same cells, always. Tests assert on `CellBuffer.textLines()`.
- **Views own local coordinates.** Containers translate and clip; children
  cannot draw outside their parent's viewport.
- **Controls own their interaction.** Hover, focus ring, cursor position,
  selection, and standard keys live inside the control. Applications receive
  semantic events, never key codes.
- **Focus is owned by scopes.** Windows, dialogs, and composite controls
  maintain their own tab order and expose only focus outcomes.
- **Concurrency (requirement):** the framework is event driven and never
  blocks the main thread — or any cooperative thread. All waiting is
  expressed as `async`/`await` suspension: input arrives as
  `AsyncStream<TerminalInput>`, drivers are actors, UI runs on `MainActor`,
  and anything slow (terminal I/O, timers, animation frames) suspends rather
  than blocks. No busy-waiting, no synchronous reads on a calling thread, no
  semaphore parking. No global statics; `end()` restores the terminal
  instead of `exit()`.

## Current State

Phases 1–3 are in place: geometry (`Point`/`Size`/`Rect`), the cell model
(`TerminalCell`/`CellStyle`/`TerminalColor`/`CellFlags`), `CellBuffer`,
`TerminalDriver` with both `ANSIDriver` (raw mode, SGR mouse, async input)
and `HeadlessDriver`, the pure `ANSIInputDecoder` and `ANSIEncoder`, and the
view system — `View`, `Painter` (mechanical clipping + local coordinates),
and `SceneRenderer` (dirty-gated frames). Phase 4 added the interaction
layer: the `View` responder surface (typed key/mouse handlers, focus hooks),
`Window` as the focus scope (first responder, Tab order, hot → focused →
Tab → cold key routing, hit-tested mouse delivery in local coordinates), and
`App` — the window stack and the pure-suspension run loop with graceful
`stop()`. Phase 5 added layout: size preferences
(`intrinsicContentSize`/min/max) with a proper layout pass
(`setNeedsLayout`/`layoutIfNeeded`, run by the renderer before drawing),
`AnchorSet` edge/center pinning applied by the default `layoutSubviews`,
`HStack`/`VStack` with flexible-space distribution, and `GridView` with
fixed/fit/flexible tracks and spans. The interactive demo is a real TUIKit
app (`swift run TUIKitDemo --interactive`). Next: controls (Phase 6).

## RichSwift

TUIKit pairs with [RichSwift](https://github.com/bobbyski/RichSwift) the way
Textual pairs with Rich: RichSwift owns rich content rendering (markup,
tables, panels, markdown, syntax highlighting via `RichRenderable`/`Style`/
`Segment`), TUIKit owns interactivity, layout, focus, and compositing. The
planned `RichText` view renders RichSwift segments into `CellBuffer` cells,
making every RichSwift renderable available inside TUIKit apps. Both
libraries are ours, so improvements flow upstream instead of being worked
around. See the RichSwift Integration section of `../PLAN.md`.

## Testing Model

`HeadlessDriver` is a full driver, not a mock: tests script input through
`send(_:)` and assert on `snapshotText()`. Every view and control added in
later phases must be demonstrable in `TUIKitDemo` and provable through the
headless driver — that pairing is the framework's definition of done.
