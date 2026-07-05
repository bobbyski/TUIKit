# TUIKit Architecture

TUIKit is an AppKit-inspired terminal UI framework. This document describes
its layers and the ownership rules between them; the build plan and progress
live in [`../PLAN.md`](../PLAN.md), and the control class hierarchy is
diagrammed in [`ControlsUML.md`](ControlsUML.md).

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
|  TUIView hierarchy, local coords, clipping, responder chain,     |
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

The foundation phases (1–5) are complete: geometry (`Point`/`Size`/`Rect`),
the cell model (`TerminalCell`/`CellStyle`/`TerminalColor`/`CellFlags`),
`CellBuffer`, `TerminalDriver` with both `ANSIDriver` (raw mode, SGR mouse,
async input) and `HeadlessDriver`, the pure `ANSIInputDecoder`/`ANSIEncoder`,
the view system (`TUIView`, `Painter`, `SceneRenderer` with dirty-gated
frames), the responder/focus layer (`Window` scopes, hot → focused → Tab →
cold key routing, hit-tested mouse delivery), `App`'s pure-suspension run
loop, and the layout pass (`intrinsicContentSize`/min/max, `AnchorSet`,
`HStack`/`VStack`, `GridView`).

The control set (Phases 6/6B) has shipped: Label, Button (roles, drop-shadow
press animation), TextField, TextView, SyntaxTextView, Checkbox,
ToggleButton, RadioGroup, SegmentedControl, Slider, Stepper, LevelIndicator,
ProgressIndicator, ListView, TableView, TreeView, DirectoryTree, Browser
(Miller columns), ScrollView, SplitView, TabView (closable tabs), Panel,
FloatingWindow (move/resize/maximize), Dialog/FileDialog, MenuBar (+ context
menus), StatusBar, Toolbar, ComboBox, PopUpButton, DatePicker/CalendarView,
ColorPicker, PathControl, DisclosureGroup, RichText, MarkdownView.
`RowNavigationState` is the shared selection/scrolling core.

On top of the controls sit four newer systems, each with its own doc:

- **Theming** — a *slot × context* matrix (`Theme` = complete `base`
  `ThemePalette` + sparse per-context overlays), resolved per view through
  `themeContext` into a flat `ResolvedTheme`; Codable so themes ship as
  JSON. Includes the Turbo/Borland fidelity work: `&`-marker accelerators,
  themeable field wells, button pills/shadows, and border-embedded
  scrollbars (`BorderScrollable` + `Panel.embedScrollbars`). See
  [`Themes.md`](Themes.md).
- **Stylesheets** — CSS-like `StyleSheet`s layer *on top of* the resolved
  theme by selector specificity; disabling is `styleSheet = nil`. See
  [`StyleSheets.md`](StyleSheets.md).
- **TUIBuilder** — the declarative layer: `Component` + result builders,
  container components (`Form`, `Grid`, tabs), and chainable modifiers,
  producing the same `TUIView` tree as manual code. See
  [`TUIBuilder.md`](TUIBuilder.md).
- **Data binding** — non-reactive data in/out: `ValueControl`, dotted-path
  names, bulk `formValues()`/`applyValues()`, typed `Binding`/`@Bound` with
  `load()`/`save()` and optional live push. See
  [`DataBinding.md`](DataBinding.md).

Input has multi-click detection: `App` debounces press/release pairs into a
`.click` event carrying `clickCount` (single-select vs double-activate never
fire together). `swift run TUIKitDemo --interactive` is the living gallery —
a desktop shell with menus, themed windows, and one factory per subsystem;
`--events` keeps the raw driver viewer. Remaining in Phase 8: minimize
(8.10–8.12) and the headless demo exit test (8.2).

## Run Loop & Timers

`App.run(_:)` merges two sources into one `AsyncStream` of loop events —
driver input and timer ticks — and presents a frame after each. Because a
tick flows through the same path as a keypress, an animation redraws exactly
the way input does, and the loop still only ever suspends (never blocks).

Timers are the framework's one timing primitive. `App.addTimer(every:_:)`
returns a cancellable `AppTimer` whose body runs on the `MainActor` inside
the loop. The tick source is injectable behind `TimerSource`:
`ClockTimerSource` uses `Task.sleep` in production (cooperative suspension,
no blocked thread), and `ManualTimerSource.fire()` drives ticks by hand in
tests with zero wall-clock time — so animation is headless-scriptable just
like scripted input. `ProgressIndicator`'s indeterminate spinner is the
first client (`app.addTimer(every:) { spinner.advance() }`); Phase 11
tooltips will reuse it.

## RichSwift

TUIKit pairs with [RichSwift](https://github.com/bobbyski/RichSwift) the way
Textual pairs with Rich: RichSwift owns rich content rendering (markup,
tables, panels, markdown, syntax highlighting via `RichRenderable`/`Style`/
`Segment`), TUIKit owns interactivity, layout, focus, and compositing. The
`RichText` view renders RichSwift segments into `CellBuffer` cells (with
`MarkdownView` and `SyntaxTextView` as the markdown/code specializations),
making every RichSwift renderable available inside TUIKit apps. Both
libraries are ours, so improvements flow upstream instead of being worked
around. See the RichSwift Integration section of `../PLAN.md`.

## Testing Model

`HeadlessDriver` is a full driver, not a mock: tests script input through
`send(_:)` and assert on `snapshotText()`. Every view and control added in
later phases must be demonstrable in `TUIKitDemo` and provable through the
headless driver — that pairing is the framework's definition of done.
