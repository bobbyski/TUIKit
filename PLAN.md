# TUIKit — Build Plan

TUIKit (working name, rename freely) is a standalone AppKit-like terminal UI
framework in Swift. It exists because no current Swift TUI toolkit combines a
modern concurrency model, a real responder/focus architecture, a rich control
set, and a headless testing story (see `Code/UILessFramework/TUI.md` and the
TermKit findings summarized in `Code/UILessFramework/ROADMAP.md` Phase B.1).

TUIKit is usable with no UILess dependency. UILess consumes it only from its
TUI renderer target (UILess roadmap Phase B.2). This plan is the working plan
for the framework; the UILess roadmap tracks only the phase's overall status.

Design authority: `Documents/AICoding rules.md` — especially the framework
golden rules (components own their interaction state, semantic events out,
raw input at framework edges, focus owned by scopes, layout declarative and
testable, demos read as tutorials).

Docs: `Docs/Architecture.md` (layers/ownership), `Docs/ControlsUML.md`
(maintained control class diagram — update it with every control change).

---

## Dashboard

```
Overall Progress  █████████████████░░░░░░░░░░░░░░░  54%   (36 / 67 items)

Phase 1 · Package Scaffold & Docs     ██████████████████████████  100%  ✅ Complete
Phase 2 · Terminal Drivers            ██████████████████████████  100%  ✅ Complete (44 tests green 2026-07-01; interactive demo check pending)
Phase 3 · View System & Rendering     ██████████████████████████  100%  🔄 Code complete, unverified
Phase 4 · Run Loop & Responder Chain  ██████████████████████████  100%  🔄 Code complete, unverified
Phase 5 · Layout                      ██████████████████████████  100%  🔄 Code complete, unverified
Phase 6 · Controls v1                 ████████████████░░░░░░░░░░   63%  🔄 In Progress (12 of 19 controls)
Phase 7 · Styling & Theming           ░░░░░░░░░░░░░░░░░░░░░░░░░░    0%  ⏳ Pending
Phase 8 · Demo & Polish               ███░░░░░░░░░░░░░░░░░░░░░░░   12%  🔄 Demo gallery started early
Phase 9 · Tutorial                    ░░░░░░░░░░░░░░░░░░░░░░░░░░    0%  ⏳ Pending
Phase 10 · VTG Vector Graphics        ░░░░░░░░░░░░░░░░░░░░░░░░░░    0%  ⏳ Pending (rev 2)
```

**Status key:** ✅ Done &nbsp;|&nbsp; 🔄 In Progress &nbsp;|&nbsp; ⏳ Pending &nbsp;|&nbsp; 🚫 Blocked

---

## Architecture North Star

AppKit's shape, terminal's medium, Swift concurrency's execution model:

- **REQUIREMENT — event driven, never block the main thread.** The framework
  is fully event driven, and no framework code may ever block the main
  thread (or any cooperative thread). Anything that waits — input reads,
  timers, terminal writes, animations, app run loops — must be expressed as
  `async`/`await` so it suspends instead of blocking. There is no
  busy-waiting, no synchronous `read()` on a calling thread, no semaphore
  parking. This is a hard acceptance criterion for every phase: a deliverable
  that blocks is not Done.
- `MainActor`-isolated UI, instances over globals, clean shutdown (no
  `exit()` from framework code).
- Views own local coordinates; containers own translation and clipping.
- A responder chain routes keys; focus is owned by scopes (windows, dialogs,
  composite controls).
- Controls own their interaction state and emit semantic events
  (`onSelectionChanged(items)`, not key codes).
- Rendering is deterministic: state + style + frame → the same cells, every
  time — provable through the headless driver.
- Raw escape sequences live only in drivers, behind protocols.

## RichSwift Integration

[RichSwift](https://github.com/bobbyski/RichSwift) is Bobby's Rich-inspired
terminal formatting library (markup, tables, panels, progress, markdown,
syntax highlighting; MIT; Swift 6.3; Foundation-only). TUIKit and RichSwift
mirror the Textual↔Rich relationship: RichSwift owns rich *content*
rendering, TUIKit owns the *interactive* full-screen layer. Because we own
both, gaps get fixed upstream in RichSwift rather than worked around here.

Integration points:

- **Phase 6 — `RichText` view.** A TUIKit view that renders RichSwift markup
  and any `RichRenderable` (tables, panels, markdown, syntax) into cells —
  RichSwift `Segment`s map onto `CellBuffer` rows the way Textual renders
  Rich segments into its compositor. This makes every RichSwift renderable
  usable inside a TUIKit app for free.
- **Phase 2/7 — one SGR story.** When the ANSI driver lands, reconcile
  TUIKit's `ANSIEncoder` with RichSwift's `Style`/ANSI emission: either
  adopt RichSwift's encoding or upstream TUIKit's cell-oriented needs into
  it. One encoder should survive.
- **Dependency policy.** The "zero dependencies" claim becomes "no
  third-party dependencies" — in-house packages (RichSwift) are allowed.
  `CellBuffer` remains TUIKit's compositing currency either way.

## Phase 1 — Package Scaffold & Docs ✅ 100%

Layout per the AICoding rules framework structure.

| # | Item | Status | Notes |
|---|------|--------|-------|
| 1.1 | `Package.swift` (library `TUIKit`, macOS + Linux) | ✅ Done | Swift 6 language mode; zero dependencies. Includes TUIKitDemo executable (Demo/TUIKitDemo). |
| 1.2 | `Sources/TUIKit/TUIKit.swift` entry file | ✅ Done | Framework summary with layer diagram; version constant. |
| 1.3 | `Docs/Architecture.md` | ✅ Done | Layer diagram + ownership rules; update as phases land. |
| 1.4 | `NEEDS_HUMAN.md` | ✅ Done | Created; watchlist notes the future ANSI input decoder. |
| 1.5 | `Tests/TUIKitTests` smoke test | ✅ Done | Smoke + geometry tests in TUIKitTests.swift. |

## Phase 2 — Terminal Drivers ✅ 100% (tests verified; interactive demo check pending)

| # | Item | Status | Notes |
|---|------|--------|-------|
| 2.1 | `TerminalDriver` protocol | ✅ Done | Async protocol: size, begin/end, present, cursor, input stream. |
| 2.2 | Cell/attribute model | ✅ Done | TerminalCell/CellStyle/TerminalColor/CellFlags + CellBuffer with clipping; ANSIEncoder (pure SGR encoding) added as shared driver piece. |
| 2.3 | ANSI driver (macOS/Linux) | ✅ Done | Actor: termios raw mode, alt screen, SGR mouse, DispatchSourceRead + non-blocking fd (never blocks), SIGWINCH resize, writes off the cooperative pool, full-redraw present (diffing later). |
| 2.4 | Input decoder | ✅ Done | Pure state machine: UTF-8, ctrl/alt, arrows+modifiers, nav/tilde keys, F1-F12 (SS3/CSI/tilde), shift-tab, SGR mouse (press/release/drag/move/scroll/modifiers), chunk-split and lone-ESC handling; 20 tests. |
| 2.5 | Headless driver | ✅ Done | Actor: scripted input, presented-buffer snapshots, resize simulation; 6 tests. |

## Phase 3 — View System & Rendering 🔄 100% (code complete, unverified)

| # | Item | Status | Notes |
|---|------|--------|-------|
| 3.1 | `View` base: frame, bounds, subviews | ✅ Done | @MainActor class: hierarchy, reparenting, hidden, frame-change dirtying; draws only through Painter. |
| 3.2 | Clipping contract | ✅ Done | Enforced mechanically in Painter (clip = ∩ of ancestor frames); contract tests incl. oversize, escape, and negative-origin children. |
| 3.3 | Painter/surface | ✅ Done | set/write/fill/drawBox in local coords; forSubview composes translation+clip; RenderTarget internal. |
| 3.4 | Dirty tracking & compose | ✅ Done | setNeedsDisplay with ancestor propagation; SceneRenderer.renderIfNeeded gates frames (v1 = full redraw per dirty frame; damage regions later); deterministic parent-then-children order. |
| 3.5 | Render snapshot testing | ✅ Done | 14 view-system tests assert on rendered textLines(). |

## Phase 4 — Run Loop & Responder Chain 🔄 100% (code complete, unverified)

| # | Item | Status | Notes |
|---|------|--------|-------|
| 4.1 | `App`/run loop on `MainActor` | ✅ Done | for-await over driver input (pure suspension); stop() returns control to caller with terminal restored; Ctrl+C default (opt-out); dirty-gated presents. |
| 4.2 | Responder chain | ✅ Done | View responder surface (keyDown/hot/cold/mouse + focus hooks); routing hot → focused chain (bubbling) → Tab traversal → cold. Mouse capture: the view that consumes a left press receives the drags and the release (scrollbar thumbs keep dragging off the bar; buttons cancel on release-outside). |
| 4.3 | Focus scopes | ✅ Done | Window owns firstResponder + depth-first tab order with wraparound; hidden views skipped; composite-scope nesting later with composites. |
| 4.4 | Semantic event surface | ✅ Done | Views receive typed KeyInput/MouseInput in local coords only; per-control typed callbacks (onActivate etc.) land with each Phase 6 control. |
| 4.5 | Window stack | ✅ Done | App present/dismiss stack; top window is key (modal input rule); z-order via subview compositing; fillsScreen windows follow resize. |

## Phase 5 — Layout 🔄 100% (code complete, unverified)

| # | Item | Status | Notes |
|---|------|--------|-------|
| 5.1 | Size preferences | ✅ Done | intrinsicContentSize (open) + minimumSize/maximumSize; layout pass (setNeedsLayout/layoutIfNeeded) with renderer integration. |
| 5.2 | `HStack` / `VStack` | ✅ Done | Shared StackView engine: natural-size children fixed, flexible share leftover (deterministic remainders), spacing/insets/alignment, hidden skipped, min/max clamps, fit-content intrinsic size for nesting. |
| 5.3 | Anchor/pin helpers | ✅ Done | AnchorSet (edge insets, fixed lengths, centering) applied by the default View.layoutSubviews; .fill/.centered helpers; per-axis resolution with intrinsic fallback. |
| 5.4 | `Grid` | ✅ Done | GridView: fixed/fitContent/flexible(weight) tracks both axes, auto-growing rows, column+row spans, spacing/insets. |
| 5.5 | Geometry-only layout tests | ✅ Done | 16 tests assert frames via layoutIfNeeded, no rendering; plus render-runs-layout integration checks. |

## Phase 6 — Controls v1 🔄 42%

Each control owns its interaction state, keyboard model, and mouse behavior.

| # | Item | Status | Notes |
|---|------|--------|-------|
| 6.1 | Label | ✅ Done | Alignment (leading/center/trailing), ellipsis truncation, intrinsic size. |
| 6.1b | RichText view (RichSwift) | ⏳ Pending | Renders RichSwift markup and `RichRenderable`s (tables/panels/markdown/syntax) into cells; see RichSwift Integration section. |
| 6.2 | Button | ✅ Done | Return/Space + press/release-inside activation with pressed feedback; focus inverts; `onActivate`. |
| 6.3 | TextField | ✅ Done | Cursor movement/editing keys, horizontal scrolling, click-to-place-cursor, placeholder; `onChanged`/`onSubmit`. (Text selection deferred to SyntaxTextView work.) |
| 6.4 | Checkbox / RadioGroup | ✅ Done | Toggle via Space/Return/click, arrows+click selection; silent programmatic setters, typed events; RadioGroup inverts the full current row when focused (visible focus even with no selection). |
| 6.5 | List | ✅ Done | `ListView` on the shared `RowNavigationState` core (pure, unit-tested): arrows/Home/End/PgUp/PgDn, viewport scrolling, wheel scroll without selection change, click select, Return activate, selects first row on focus for a visible highlight; `onSelectionChanged`/`onActivate`. The 6.10 design answer: TableView will be a multi-column consumer of the same core. |
| 6.5a | `SegmentedControl` | ✅ Done | Horizontal button-style exclusive selection; arrows/Home/End/click, selected inverted, focus bold; silent programmatic select; typed event. |
| 6.5b | `TabView` (folder tabs) | ✅ Done | Tab bar selects which content view shows below; ←/→ + click switch tabs; non-selected content hidden (drops from focus order); addTab/select/title API. |
| 6.6 | ScrollView | ✅ Done | Viewport + document view at full content size; offset clamps both axes; arrows/PgUp-PgDn/Home/End when focused, wheel anytime; proportional ░/█ indicator bars in reserved column/row (two-pass reservation) that are live — track click pages toward the click, thumb drags (via window mouse capture); silent `setOffset`, `onOffsetChanged`. Clipping needs nothing special — the Painter contract already contains the document. Note: focus traversal can still reach controls scrolled out of view; revisit with 6.16. |
| 6.7 | Window / Panel chrome | ⏳ Pending | Title, border, close; drag/resize later. |
| 6.8 | MenuBar / Menu | ⏳ Pending | Hot keys, submenu navigation. |
| 6.9 | Dialog / Alert | ⏳ Pending | Modal focus capture, default/cancel actions. |
| 6.10 | `TableView` | ✅ Done | The multi-column consumer of `RowNavigationState`, as designed in 6.5: identical keyboard model to ListView below a fixed bold+underline header; `TableColumn` fixed/flexible(weight) widths (stack-style deterministic remainders, 1-cell separators); selection inverts the full row; header click emits `onSortRequested(column)` — the app owns data and sort order; `onSelectionChanged`/`onActivate`, silent `select`. |
| 6.11 | `TreeView` | ✅ Done | `TreeNode` model (parent links, `childProvider` loads lazily exactly once on first expansion); expanded nodes flatten onto `RowNavigationState`, so navigation is ListView's; `→` expands then steps into children, `←` collapses then steps to the parent; disclosure-triangle clicks toggle; selection survives rebuilds by node identity; `onSelectionChanged`/`onActivate`, silent `select`. |
| 6.12 | `SplitView` | ⏳ Pending | H/V panes, keyboard- and mouse-draggable divider, min sizes, collapse. |
| 6.13 | `Stepper` | ✅ Done | `[-] 42 [+]`: Up/`+` and Down/`-` step (clamped to `range`, custom `step`), Home/End jump to bounds, clicking a bracket steps; field width sized to the range's widest value; silent `setValue`, `onValueChanged`; steps at a bound emit nothing. |
| 6.14 | Open/Save dialog | ⏳ Pending | File and directory choosing (open/save/select-folder modes) behind a `FileSystemProvider` protocol (AICoding rule 30) so tests use a fake file system; builds on TableView + TextField + Dialog. |
| 6.15 | Color picker | ⏳ Pending | Named/palette/RGB selection matching `TerminalColor`; preview swatches; typed color events. |
| 6.16 | `SyntaxTextView` | ⏳ Pending | Editable text view with syntax highlighting rendered through RichSwift `Syntax` (see RichSwift Integration); line numbers, scroll; builds on TextField/ScrollView internals. |

## Phase 7 — Styling & Theming ⏳ 0%

| # | Item | Status | Notes |
|---|------|--------|-------|
| 7.1 | Style model | ⏳ Pending | Colors, emphasis, borders; per-control style points. |
| 7.2 | Theme cascade | ⏳ Pending | Defaults → theme → per-view override; reset-safe switching. |
| 7.3 | Built-in themes | ⏳ Pending | At least light/dark/mono. |
| 7.4 | CSS-like layer (future) | ⏳ Pending | The Textual-inspired layer from `TUI.md`; design doc first. |

## Phase 8 — Demo & Polish 🔄 12%

| # | Item | Status | Notes |
|---|------|--------|-------|
| 8.1 | Demo app | 🔄 In Progress | Gallery (cells, view tree, layout, controls) + `--interactive` live control form + `--events` driver viewer; grows with each control (AICoding rule 40). |
| 8.2 | Headless demo test | ⏳ Pending | The demo renders identically through the headless driver — the phase exit criterion. |
| 8.3 | API review pass | ⏳ Pending | Swift API Design Guidelines; public surface smaller than implementation. |
| 8.4 | Docs complete | ⏳ Pending | Doc comments on all public API; Architecture.md current. |

## Phase 9 — Tutorial ⏳ 0%

A step-by-step "Building with TUIKit" tutorial (`Docs/Tutorial/`), written
for someone who has never used the framework. Each chapter is a short read
ending in a runnable milestone; the code for every milestone lives in a
`TUIKitTutorial` executable target so it compiles (and is tested headlessly)
forever — a tutorial that drifts from the API is worse than none.

| # | Item | Status | Notes |
|---|------|--------|-------|
| 9.1 | Outline & ground rules | ⏳ Pending | Chapter list, voice, and the runnable-milestone rule; every snippet comes from compiling code. |
| 9.2 | Ch. 1 — Hello, terminal | ⏳ Pending | App, Window, the run loop, drawing a first view, quitting cleanly (Esc/Ctrl+C). |
| 9.3 | Ch. 2 — Layout | ⏳ Pending | Stacks, grid, anchors, intrinsic sizes; build the app shell (title bar, content, status line). |
| 9.4 | Ch. 3 — Controls & events | ⏳ Pending | Add the form: fields, buttons, list, tabs; wire semantic events (`onActivate`, `onSelectionChanged`). |
| 9.5 | Ch. 4 — Focus, keys & mouse | ⏳ Pending | Responder chain, Tab traversal, hot/cold keys, mouse routing; add app-level shortcuts. |
| 9.6 | Ch. 5 — Testing your app | ⏳ Pending | Drive the finished app through the headless driver: scripted input, buffer snapshots, resize. |
| 9.7 | `TUIKitTutorial` target + CI test | ⏳ Pending | Per-chapter milestones runnable via `swift run TUIKitTutorial ch3`; a test renders each milestone headlessly so chapters can never rot. |

## Phase 10 — VTG Vector Graphics Mode ⏳ 0% (rev 2)

**Rev 2 — starts only after Phases 1-9 ship as TUIKit 1.0.** Adds optional
vector graphics inside the terminal via the VectorTerminal Graphics (VTG)
protocol, wrapped by the in-house `VectorTerminalSDK`
(`AIResearch/GraphicalTerminal/Code/VectorTerminalSDK`; APC escape
sequences, retained scene with object ids, layers under/over the text
plane, pixel/cell mouse events, hit regions, capability query). In-house
dependency, same policy as RichSwift.

**Goal: attractive chrome, not a control set.** VTG makes the *existing*
windows and controls beautiful — rounded panel borders, shadows, focus
glows, pill buttons behind ordinary text, smooth scrollbar thumbs — drawn
mostly on the under-text layer beneath the same cell-rendered controls.
There is no app-facing vector drawing API and no new vector controls; the
public control surface and semantic events do not change. VTG is purely a
presentation upgrade the framework applies when the terminal supports it.

Ground rules carried over from rev 1: raw VTG/APC sequences live only in
the driver layer; chrome is drawn through a typed internal surface; every
feature has a headless/fake-transport testing story; cell rendering must
remain the universal fallback — a TUIKit app never *requires* VTG, and
apps cannot tell (except visually) which mode they are running in.

| # | Item | Status | Notes |
|---|------|--------|-------|
| 10.1 | Capability detection & fallback contract | ⏳ Pending | Probe `capabilities?` (typed `VTGCapabilities`) during driver `begin`; expose `driver.graphics` as optional. The fallback rule is uniform: no VTG → today's cell rendering, exactly as it is in rev 1; never a crash, never a behavior difference. |
| 10.2 | VTG driver integration | ⏳ Pending | Extend `TerminalDriver` with an optional graphics surface backed by `VectorTerminalCanvas`; one output path so VTG APC writes interleave safely with cell present (frames via `startFrame`/`endFrame` for tear-free updates). Raw sequences stay in the driver, per the Phase 2 contract. |
| 10.3 | Cell↔pixel geometry | ⏳ Pending | `glyphSize?`-based metrics: view-local cell coordinates ↔ canvas pixel coordinates conversion owned by the framework (one mapper, tested), so views position vector art in their own coordinate space. |
| 10.4 | Internal chrome surface | ⏳ Pending | A framework-internal (not public) typed decoration surface controls draw chrome through, in local coordinates, alongside their cell `draw(_:)`: rounded rects, fills, shadows, pill shapes, focus glows. Framework composes translation and VTG layer `clip` so the Painter clipping contract holds for chrome too; object ids are view-scoped and reclaimed when views move/disappear. |
| 10.5 | Control & window chrome pass | ⏳ Pending | Apply the surface across the set: window/panel borders and shadows, button and segmented pills behind text, rounded text-field wells, smooth scrollbar thumb, tab folder shapes, focus glow. Chrome hooks into the Phase 7 theme cascade (themes may define both cell and VTG styling); zero public API change to any control. |
| 10.6 | VTG input routing | ⏳ Pending | VTG-native pixel mouse events decoded in the driver and routed through the existing responder chain as the same typed `MouseInput` in cell coords — chrome never changes hit-testing semantics, it only looks better. |
| 10.7 | Headless VTG testing | ⏳ Pending | Closure-backed `VTGOutput` transport recording sequences + scripted event injection: assert emitted VTG chrome commands and unchanged input routing deterministically, no terminal required (same discipline as the headless cell driver). |
| 10.8 | Demo & fallback proof | ⏳ Pending | The *same* demo app, untouched, runs twice: in a VTG terminal with full chrome, and in a plain terminal with cell rendering — identical behavior, focus order, and events in both. That equivalence is the phase exit criterion. |

---

## Testing Rules

- The headless driver is a Phase 2 deliverable precisely so every later phase
  lands with deterministic tests; no phase is Done with manual-only proof.
- Input decoding, layout geometry, focus routing, and control contracts each
  get their own suites (contract tests, not implementation trivia).
- Follow the maintenance conventions in
  `Code/UILessFramework/TEST_PLAN.md`; TUIKit keeps its test status in this
  file's dashboard.

## Maintenance Rules

- Update the dashboard in the same commit as the work it reflects.
- Files over 500 code lines or overly complicated functions go to
  `NEEDS_HUMAN.md` with an alert to Bobby.
- Every public symbol gets a documentation comment; classes get use-case
  summaries with ASCII diagrams where they help.
