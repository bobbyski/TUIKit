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
(maintained control class diagram — update it with every control change),
`Docs/TUIBuilder.md` (an optional SwiftUI-shaped, non-reactive declarative
builder over the controls — core implemented, see Phase 12), `Docs/DataBinding.md`
(non-reactive form data in/out: named lookup + typed bindings — see Phase 14).

---

## Dashboard

```
Overall Progress  ████████████████████░░░░░░░░░░░░  63%   (73 / 116 items)

Phase 1 · Package Scaffold & Docs     ██████████████████████████  100%  ✅ Complete
Phase 2 · Terminal Drivers            ██████████████████████████  100%  ✅ Complete (44 tests green 2026-07-01; interactive demo check pending)
Phase 3 · View System & Rendering     ██████████████████████████  100%  🔄 Code complete, unverified
Phase 4 · Run Loop & Responder Chain  ██████████████████████████  100%  🔄 Code complete, unverified
Phase 5 · Layout                      ██████████████████████████  100%  🔄 Code complete, unverified
Phase 6 · Controls v1                 ██████████████████████████  100%  🔄 Code complete (all 21 controls; full-suite verification pending)
Phase 6B · Controls v2                ██████████████████████████  100%  🔄 Code complete (all 14; full-suite verification pending)
Phase 6C · Editor v2 (selection…)     ██████████████████████████  100%  🔄 Code complete on feature/editor-v2 (selection, clipboard incl. OSC 52, undo/redo, find/goto; verification pending)
Phase 7 · Styling & Theming           ██████████████████████████  100%  🔄 Code complete (verification pending)
Phase 8 · Demo & Polish               ██████████████████████░░░░   85%  🔄 Turbo theme suite (8.5–8.8, 8.13–8.15), border scrollbars (8.7), multi-click (8.16), API review (8.3), docs (8.4) done; remaining: headless demo test (8.2), minimize trio (8.10–8.12)
Phase 9 · Tutorial                    ██████████████████████████  100%  ✅ Docs/Tutorial (README + Ch1–6), TUIKitTutorial runner + TUIKitTutorialMilestones library, anti-rot tests render every chapter headlessly
Phase 10 · VTG Vector Graphics        ████████████████████░░░░░░   75%  🔄 Core shipped (10.1–10.5 first pass, 10.7; Ambiance theme); pending: real-VectorTerminal check (10.8), wider control pass
Phase 11 · Controls v3                ░░░░░░░░░░░░░░░░░░░░░░░░░░    0%  ⏳ Pending (rev 2: search, sheets, images, tokens, tooltips)
Phase 12 · TUIBuilder (declarative)   ██████████████████████████  100%  🔄 Code complete — core, containers, Form, Grid/Tab/Split DSL, hosting
Phase 13 · TUIView base rename        ██████████████████████████  100%  ✅ Done — base class View → TUIView (SwiftUI coexistence)
Phase 14 · Data In / Out (binding)    ██████████████████████████  100%  🔄 Code complete — value/named/dict + typed binding + load/save/live + @Bound macro
Phase 15 · TUICodeEditor              ████████████████░░░░░░░░░░   62%  🔄 E1–E5/E8 code complete — stateful colouring, banded gutter, OmegaCLIDE swapped over; E6 folding, E7 diff/merge, E9 perf remain
Phase 16 · Control Parity             ███████████████████████░░░   90%  🔄 Waves A+B complete (16.1–16.25 + 16.29 PreferencesDialog; MasterDetail renamed — the sidebar IS SlideOut); Wave C siblings remain — 28 items in 3 waves (CONTROL_PARITY.md)
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
  third-party *runtime* dependencies" — in-house packages (RichSwift) are
  allowed. The one exception is **`swift-syntax`**, used solely by the
  `TUIKitMacros` compiler-plugin target for the Phase 14.6 `@Bound` macro: it
  is build-time only and the library's runtime stays dependency-free (delete
  the macro target to remove it entirely). `CellBuffer` remains TUIKit's
  compositing currency either way.
- **One import.** RichSwift is a dependency of the TUIKit library target
  and is `@_exported` from it: depending on TUIKit pulls RichSwift in
  automatically, and `import TUIKit` alone exposes the RichSwift API. The
  few shared names (`Panel`, `Table`, `Text`) qualify with a module prefix.

## Phase 1 — Package Scaffold & Docs ✅ 100%

Layout per the AICoding rules framework structure.

| # | Item | Status | Notes |
|---|------|--------|-------|
| 1.1 | `Package.swift` (library `TUIKit`, macOS + Linux) | ✅ Done | Swift 6 language mode; no third-party dependencies (RichSwift, in-house, added in Phase 6 per the dependency policy). Includes TUIKitDemo executable (Demo/TUIKitDemo). |
| 1.2 | `Sources/TUIKit/TUIKit.swift` entry file | ✅ Done | Framework summary with layer diagram; version constant. |
| 1.3 | `Docs/Architecture.md` | ✅ Done | Layer diagram + ownership rules; update as phases land. |
| 1.4 | `NEEDS_HUMAN.md` | ✅ Done | Created; watchlist notes the future ANSI input decoder. |
| 1.5 | `Tests/TUIKitTests` smoke test | ✅ Done | Smoke + geometry tests in TUIKitTests.swift. |

## Phase 2 — Terminal Drivers ✅ 100% (tests verified; interactive demo check pending)

| # | Item | Status | Notes |
|---|------|--------|-------|
| 2.1 | `TerminalDriver` protocol | ✅ Done | Async protocol: size, begin/end, present, cursor, input stream. |
| 2.2 | Cell/attribute model | ✅ Done | TerminalCell/CellStyle/TerminalColor/CellFlags + CellBuffer with clipping; ANSIEncoder (pure SGR encoding) added as shared driver piece. |
| 2.3 | ANSI driver (macOS/Linux) | ✅ Done | Actor: termios raw mode, alt screen, SGR mouse, DispatchSourceRead + non-blocking fd (never blocks), SIGWINCH resize, writes off the cooperative pool. Present is damage-diffed (2026-08-20, `ANSIEncoder.frame`): only changed rows repaint, so an idle app writes ~bytes/s not ~screens/s; baseline resets on begin/resume/resize. Input chunks decode strictly in arrival order (AsyncStream hand-off, 2026-08-20) and control strings self-heal at `controlStringCap` — a lost ST can no longer deafen the app (the "locks up after idle" / "quit doesn't quit" reports). |
| 2.4 | Input decoder | ✅ Done | Pure state machine: UTF-8, ctrl/alt, arrows+modifiers, nav/tilde keys, F1-F12 (SS3/CSI/tilde), shift-tab, SGR mouse (press/release/drag/move/scroll/modifiers), chunk-split and lone-ESC handling; 20 tests. |
| 2.5 | Headless driver | ✅ Done | Actor: scripted input, presented-buffer snapshots, resize simulation; 6 tests. |

## Phase 3 — View System & Rendering 🔄 100% (code complete, unverified)

| # | Item | Status | Notes |
|---|------|--------|-------|
| 3.1 | `TUIView` base: frame, bounds, subviews | ✅ Done | @MainActor class: hierarchy, reparenting, hidden, frame-change dirtying; draws only through Painter. |
| 3.2 | Clipping contract | ✅ Done | Enforced mechanically in Painter (clip = ∩ of ancestor frames); contract tests incl. oversize, escape, and negative-origin children. |
| 3.3 | Painter/surface | ✅ Done | set/write/fill/drawBox in local coords; forSubview composes translation+clip; RenderTarget internal. |
| 3.4 | Dirty tracking & compose | ✅ Done | setNeedsDisplay with ancestor propagation; SceneRenderer.renderIfNeeded gates frames (v1 = full redraw per dirty frame; damage regions later); deterministic parent-then-children order. |
| 3.5 | Render snapshot testing | ✅ Done | 14 view-system tests assert on rendered textLines(). |

## Phase 4 — Run Loop & Responder Chain 🔄 100% (code complete, unverified)

| # | Item | Status | Notes |
|---|------|--------|-------|
| 4.1 | `App`/run loop on `MainActor` | ✅ Done | for-await over driver input (pure suspension); stop() returns control to caller with terminal restored; Ctrl+C default (opt-out); dirty-gated presents. |
| 4.2 | Responder chain | ✅ Done | TUIView responder surface (keyDown/hot/cold/mouse + focus hooks); routing hot → focused chain (bubbling) → Tab traversal → cold. Mouse capture: the view that consumes a left press receives the drags and the release (scrollbar thumbs keep dragging off the bar; buttons cancel on release-outside). |
| 4.3 | Focus scopes | ✅ Done | Window owns firstResponder + depth-first tab order with wraparound; hidden views skipped; composite-scope nesting later with composites. |
| 4.4 | Semantic event surface | ✅ Done | Views receive typed KeyInput/MouseInput in local coords only; per-control typed callbacks (onActivate etc.) land with each Phase 6 control. |
| 4.5 | Window stack | ✅ Done | App present/dismiss stack; top window is key; z-order via subview compositing; fillsScreen windows follow resize. Overlapping-window support: `Window.isModal` (Dialog defaults true — modals swallow outside clicks), click-to-activate for non-modal stacks (activate-and-forward, targeted by hit test so partially-transparent windows like menu-bar strips are click-through), `App.activate(_:)` raises programmatically. The stack root is the public, stylable `Desktop` (background fill character + theme; its theme is the inherited default for every window). |

## Phase 5 — Layout 🔄 100% (code complete, unverified)

| # | Item | Status | Notes |
|---|------|--------|-------|
| 5.1 | Size preferences | ✅ Done | intrinsicContentSize (open) + minimumSize/maximumSize; layout pass (setNeedsLayout/layoutIfNeeded) with renderer integration. |
| 5.2 | `HStack` / `VStack` | ✅ Done | Shared StackView engine: natural-size children fixed, flexible share leftover (deterministic remainders), spacing/insets/alignment, hidden skipped, min/max clamps, fit-content intrinsic size for nesting. |
| 5.3 | Anchor/pin helpers | ✅ Done | AnchorSet (edge insets, fixed lengths, centering) applied by the default TUIView.layoutSubviews; .fill/.centered helpers; per-axis resolution with intrinsic fallback. |
| 5.4 | `Grid` | ✅ Done | GridView: fixed/fitContent/flexible(weight) tracks both axes, auto-growing rows, column+row spans, spacing/insets. |
| 5.5 | Geometry-only layout tests | ✅ Done | 16 tests assert frames via layoutIfNeeded, no rendering; plus render-runs-layout integration checks. |
| 5.6 | `AbsoluteLayout` + force hooks | ✅ Done | Container that does **no** automated layout on its immediate children — each keeps the `frame` you set (anchors ignored) via `place(_:at:)`; it still auto-sizes to its parent through an `intrinsicContentSize` equal to the children's bounding box. Since direct child-frame changes don't propagate size upward, `TUIView.relayout()` (marks self + ancestor chain, so the parent re-measures) and `TUIView.refresh()` (re-dirties the subtree to force a redraw) force reevaluation. |

## Phase 6 — Controls v1 🔄 100% (code complete; full-suite verification pending)

Each control owns its interaction state, keyboard model, and mouse behavior.

| # | Item | Status | Notes |
|---|------|--------|-------|
| 6.1 | Label | ✅ Done | Alignment (leading/center/trailing), ellipsis truncation, intrinsic size. |
| 6.1b | RichText view (RichSwift) | ✅ Done | Two paths: markup via `Markup.parse` (RichSwift `Style`/`Color` map directly onto `CellStyle` — no escapes involved), and any `RichRenderable` (tables/panels/markdown/syntax) rendered at view width then decoded by the internal `SGRDecoder` (the inverse of `ANSIEncoder`, scoped to the SGR subset RichSwift emits). Display-only; width-keyed render cache. RichSwift lands as the package's first (in-house) dependency. |
| 6.1c | `MarkdownView` | ✅ Done | Scrolling markdown reader over RichSwift `Markdown` (headings, lists, quotes, inline bold/code, highlighted code fences): the view soft word-wraps the styled output to its width (RichSwift keeps one line per source line), scrolls with arrows/PgUp-PgDn/Home/End/wheel, and reserves the last column for the solid proportional indicator. Read-only; `setMarkdown` resets to the top. |
| 6.2 | Button | ✅ Done | Return/Space + press/release-inside activation with pressed feedback; focus inverts; `onActivate`. |
| 6.3 | TextField | ✅ Done | Cursor movement/editing keys, horizontal scrolling, click-to-place-cursor, placeholder; `onChanged`/`onSubmit`. (Text selection deferred to SyntaxTextView work.) |
| 6.4 | Checkbox / RadioGroup | ✅ Done | Toggle via Space/Return/click, arrows+click selection; silent programmatic setters, typed events; RadioGroup inverts the full current row when focused (visible focus even with no selection). |
| 6.5 | List | ✅ Done | `ListView` on the shared `RowNavigationState` core (pure, unit-tested): arrows/Home/End/PgUp/PgDn, viewport scrolling, wheel scroll without selection change, click select, Return activate, selects first row on focus for a visible highlight; `onSelectionChanged`/`onActivate`. The 6.10 design answer: TableView will be a multi-column consumer of the same core. |
| 6.5a | `SegmentedControl` | ✅ Done | Horizontal button-style exclusive selection; arrows/Home/End/click, selected inverted, focus bold; silent programmatic select; typed event. |
| 6.5b | `TabView` (folder tabs) | ✅ Done | Tab bar selects which content view shows below; ←/→ + click switch tabs; non-selected content hidden (drops from focus order); addTab/select/title API. |
| 6.6 | ScrollView | ✅ Done | Viewport + document view at full content size; offset clamps both axes; arrows/PgUp-PgDn/Home/End when focused, wheel anytime; solid proportional indicator bars (dim track, bright thumb — no glyph patterns) in reserved column/row (two-pass reservation) that are live — track click pages toward the click, thumb drags (via window mouse capture); `fitsDocumentWidth` reflows the document to the viewport for vertical-only scrolling (forms on small screens); silent `setOffset`, `onOffsetChanged`. Clipping needs nothing special — the Painter contract already contains the document. Note: focus traversal can still reach controls scrolled out of view; revisit with 6.16. |
| 6.7 | Window / Panel chrome | ✅ Done | `Panel`: single-line border, themed title in the top border, optional `[x]` close affordance emitting `onClose`, optional `◢` resize handle; application content lives in the inset `content` view. `FloatingWindow`: a non-modal `Window` wearing Panel chrome with drag-to-move (title row), drag-to-resize (corner, clamped to `minimumWindowSize`), close box + Esc emitting `onCloseRequest` — gesture continuity via window mouse capture. |
| 6.8 | MenuBar / Menu | ✅ Done | `Menu`/`MenuItem` model (separators, disabled items, per-item `keyEquivalent` fired from anywhere via the hot-key pass — menu closed or open); bar highlights with ←/→, Return/↓ opens; dropdown navigates with ↑/↓ (skipping separators/disabled), slides between menus with ←/→, Esc closes, click toggles/activates; focus returns to the bar on close (unless an outside click took focus — that focus stands). Dropdowns dismiss on focus loss, so outside clicks close them (the earlier v1 limitation is gone). |
| 6.9 | Dialog / Alert | ✅ Done | `Dialog`: a `Window` wearing `Panel` chrome, so modality is the existing stack rule (top window is key). Default button (initial focus; Return via cold-key pass when something else holds focus) and cancel button (Esc via hot-key pass); every button runs its action then `onDismiss`; multiline message; `preferredSize` + `sizeToFit(in:)` centering. |
| 6.10 | `TableView` | ✅ Done | The multi-column consumer of `RowNavigationState`, as designed in 6.5: identical keyboard model to ListView below a fixed bold+underline header; `TableColumn` fixed/flexible(weight) widths (stack-style deterministic remainders, 1-cell separators); selection inverts the full row; header click emits `onSortRequested(column)` — the app owns data and sort order; `onSelectionChanged`/`onActivate`, silent `select`. |
| 6.11 | `TreeView` | ✅ Done | `TreeNode` model (parent links, `representedValue`, `childProvider` loads lazily exactly once on first expansion); expanded nodes flatten onto `RowNavigationState`, so navigation is ListView's; `→` expands then steps into children, `←` collapses then steps to the parent; disclosure-triangle clicks toggle; selection survives rebuilds by node identity; `onSelectionChanged`/`onActivate`, silent `select`. |
| 6.11b | `DirectoryTree` | ✅ Done | File-system outline composed over `TreeView` behind the `FileSystemProvider` protocol (AICoding rule 30; `LocalFileSystem` for the real disk, fake providers in tests — no test touches the disk). Lazy per-directory listing on first expansion, directories-first case-insensitive sort, `showsFiles` filter, `setRoot`/`reload`/`expandRoot`; path-typed events (`onSelectionChanged(String?)`, `onActivate(String)`). Standalone control now; becomes the tree half of 6.14. |
| 6.12 | `SplitView` | ✅ Done | H/V panes around a one-cell divider; divider drags with the mouse (grabbed via window capture, so the drag survives leaving the divider cell), arrows move it while focused, Home/End snap against the pane minimums; `minimumFirst/SecondLength` clamp every path; silent `setDividerPosition`, `onDividerMoved`. Collapse = a zero minimum + Home/End. |
| 6.13 | `Stepper` | ✅ Done | `[-] 42 [+]`: Up/`+` and Down/`-` step (clamped to `range`, custom `step`), Home/End jump to bounds, clicking a bracket steps; field width sized to the range's widest value; silent `setValue`, `onValueChanged`; steps at a bound emit nothing. |
| 6.14 | Open/Save dialog | ✅ Done | `FileDialog(mode:root:fileSystem:)` — open / save / selectFolder — composed from `Dialog` (modality, default/cancel buttons, new `body` slot) + `DirectoryTree` + `TextField`. Save mode joins the current directory with the name field (file selection prefills the name, folder selection retargets); footer always shows the path confirm would return; Return confirms from tree, name field, or button; tested entirely against a fake `FileSystemProvider`. **Folder-picker fixes (found dogfooding OmegaCLIDE's New Project wizard):** a directories-only picker no longer pre-highlights the first child — it arrived answering with a folder the user never chose, and made the browsed directory unchoosable whenever it had subfolders (new `DirectoryList.selectsFirstEntryOnReload`, an init parameter because the first `reload()` runs during init); and `canCreateDirectories: true` now actually surfaces New Folder outside save mode, where the button had been built inside the Name row and so was silently dropped. |
| 6.15 | Color picker | ✅ Done | Composite of existing controls: `TabView` with Named (16-swatch grid, arrow/click selection), Palette (index stepper), and RGB (three steppers) tabs, plus an always-visible preview swatch with a readable description (`TerminalColor` is now `CustomStringConvertible`); one typed `onColorChanged(TerminalColor)`; silent `setColor` switches to the matching tab. |
| 6.16 | `SyntaxTextView` | ✅ Done | Editable multi-line code view: line-oriented cursor editing (insert, Return splits, Backspace/Delete join, Tab indents — Shift+Tab still leaves), two-axis viewport that follows the cursor, click-to-place, wheel scroll, dim line-number gutter; per-line highlighting through RichSwift `Syntax` with a per-line cache (editing one line re-highlights one line); `onChanged`, silent `setText`. Text selection still deferred (noted at 6.3). |

## Phase 6B — Controls v2 🔄 100% (14 of 14; code complete)

A second wave of controls, motivated by building the desktop-style demo.
Same rules as v1: controls own their interaction state, semantic events
out, theme slots for presentation, headless tests for every behavior.

Shared affordance: `Button`, `PopUpButton`, and `Toolbar` items take a
`ControlStyle` — `.tinted` (accent-colored label, no brackets; the default)
or `.bordered` (the classic `[ … ]`). Color carries "actionable"; on a
colorless theme the tinted style falls back to an underline.

| # | Item | Status | Notes |
|---|------|--------|-------|
| 6B.1 | `PopUpButton` | ✅ Done | `[ Balanced ▾ ]` closed; Space/Return/↓/click opens the internal `PopUpList` (bordered, theme-styled) attached to the owning window — **below when it fits, above when tighter**; ↑/↓/Home/End + Return choose, Esc cancels, and losing focus dismisses (an outside click closes without stealing focus back); silent `select`, `onSelectionChanged(Int)`. `PopUpList` is the shared machinery for 6B.3/6B.14. |
| 6B.2 | `ToggleButton` | ✅ Done | Checkbox semantics, color presentation: on wears the selection slot, off the placeholder (dim); focus adds inverse/bold. Space/Return/click toggle; silent `setOn`, `onChange(Bool)`; restyles via themes and stylesheets like everything else. |
| 6B.3 | `ComboBox` | ✅ Done | `TextField` + trailing `▾` (accent-colored while open); the disclosure click or `↓` from the field pops the shared `PopUpList` (below/above by space), highlighting the item matching the text; picking fills the field and fires `onSelectionChanged` + `onChanged`; `onChanged`/`onSubmit` pass through from the field; free text stays free. |
| 6B.4 | `StatusBar` | ✅ Done | One-row segmented container: segments declare `minimumWidth` (default: content's natural width), optional `maximumWidth`, and a `percentage` weight; mins honored first, leftover split by weight with one-cell remainders to the earliest segments, maximums clamp, too-narrow bars shrink from the trailing end. Separators are real connected `Divider`s, so an enclosing Panel welds them into its border (`┴` when the bar sits on the bottom row); `showsSeparators` toggles them. Hosts any one-row control. |
| 6B.5 | `Divider` | ✅ Done | Visible line (h/v, 1-cell intrinsic) in the theme's border slot + `borderStyle` glyphs. `isConnected` (default true, opt out per divider): tee/cross junctions (`├ ┤ ┬ ┴ ┼`, with double/heavy tables) where dividers cross, where a perpendicular divider's endpoint abuts, and — drawn by the enclosing `Panel` — where a divider reaches the content edge, joining it into the border. `isDraggable`: arrows while focused or mouse drag (window capture) move the line, resizing only the sibling views whose edges abut it (pane behavior — captions and crossing lines are untouched), then relaying out so anchored siblings resolve; `onMoved`. Focus/drag cue is a color change only (line recolors to the accent; no cue on `mono`) — never inverse, never bold: bold box-drawing glyphs render unevenly in common terminal fonts and read as a dashed line. Panel-edge joining walks the whole content subtree. v1 limit: junction pairs assume one border style. |
| 6B.6 | `ProgressIndicator` | ✅ Done | Two styles: determinate `.bar` (a **solid** accent fill over a dim track — blanks painted on background colors, never a shaded/hash glyph — reusing the scrollbar slot and its colorless `mono` fallback, with an optional trailing `NN%` label) and indeterminate `.spinner` (a glyph advanced one frame per `advance()`, optional caption). Display-only, non-focusable. Ships the App timer story as a **first-class TUIKit facility**: `App.addTimer(every:repeats:_:)` and `App.schedule(after:_:)` (one-shot; self-cancels) return a cancellable `AppTimer`; input and ticks merge into one `AsyncStream` so a tick presents a frame like a keypress does. The tick source is the injectable `TimerSource` — `ClockTimerSource` (`Task.sleep`, never blocks) in production, `ManualTimerSource` (`fire()`, zero wall-clock) for headless tests. Surfaced in the framework summary and the UML app-layer diagram; Phase 11 tooltips reuse it. |
| 6B.7 | `Slider` | ✅ Done | `├────█────┤` in border-slot glyphs (tee end caps follow `borderStyle`); ←/→ step (custom `step`), Home/End to bounds, click/drag positions with rounding (window capture keeps drags); handle recolors to the accent while focused; silent `setValue`, `onValueChanged`. |
| 6B.8 | Date/Time/Calendar control | ✅ Done | `DatePicker` with three `Calendar`-backed modes: `.date` (`YYYY-MM-DD` segments), `.time` (`HH:MM` segments) — ↑/↓ step the focused field (Foundation does the arithmetic, so month lengths/leap years are correct), ←/→ move between fields — and `.calendar` (an always-visible month grid walked with arrows, PgUp/PgDn — or the clickable `▲`/`▼` steppers on the title row — changing month; month names are shown as short labels like `Jul`, independent of locale). In `.date` mode Space or clicking the `▾` drops a month-grid popup (the shared internal `CalendarView`, placed below/above by space, self-dismissing on focus loss) to pick a day. Injectable `calendar` (locale/timezone/firstWeekday) keeps it testable; `onDateChanged`, silent `setDate`. |
| 6B.9 | `LevelIndicator` | ✅ Done | `▮▮▮▯▯` capacity / `★★★☆☆` rating; filled cells in the accent, empty de-emphasized; `isEditable` enables ←/→, Home/End, and click-to-set (clicking the current level clears — the rating convention); silent `setValue`, `onValueChanged`. |
| 6B.10 | `Browser` (Miller columns) | ✅ Done | Side-by-side columns where selecting a row reveals its children in the next column (built lazily, once, on first selection); ↑/↓ navigate a column, ←/→ climb/descend, Return activates, expandable rows show a `›`, columns scroll horizontally to keep the focused one visible. The third `RowNavigationState` consumer — one per column. Fed by any `BrowserDataSource` (root + `childrenOf` over `BrowserItem`s carrying a `representedValue`), with a `FileSystemBrowserDataSource` (behind `FileSystemProvider`, directories-first sort, path payloads) and a `Browser(fileSystemRoot:provider:)` convenience for file browsing. `onSelectionChanged`/`onActivate`. |
| 6B.11 | `PathControl` | ✅ Done | Breadcrumbs with ` ▸ ` separators; click a crumb (or ←/→ + Return; focused crumb wears the accent) to receive its *prefix path* via `onPathSelected`; absolute/relative preserved; silent `setPath`. |
| 6B.12 | Disclosure triangle | ✅ Done | `DisclosureGroup`: `▸/▾ Title` header (header slot; accent triangle while focused); Space/Return/click toggles; content hides (dropping from focus order) and the intrinsic height changes so stacks reflow. Content's natural size falls back to its children's when the container itself has no intrinsic, and toggling invalidates the *whole* ancestor layout chain (stack → scroll view → …), so nesting depth doesn't matter. Silent `setExpanded`, `onExpansionChanged`. |
| 6B.13 | `Toolbar` | ✅ Done | Header-slot strip of labeled/icon command buttons (`[ ⚙ Settings ]`). A single focus stop: ←/→ move between visible items (skipping disabled), Home/End jump, Return/Space or click activates. When the strip is too narrow, trailing items greedily collapse into a `»` overflow button — the last focus slot — whose menu (the shared context-menu `MenuDropdown`, placed below/above) lists them. `ToolbarItem` carries title/icon/enabled/action; themable via header/border slots. Items default to the color-based `.tinted` `ControlStyle` (accent label, no brackets), with `.bordered` for the classic `[ … ]` look. |
| 6B.14 | Context menu | ✅ Done | `TUIView.contextMenu: Menu?`; right-click walks the hit chain to the nearest menu and the window presents it at the pointer (below/above by space) via the shared `MenuDropdown`; ↑/↓/Return, Esc, and focus-loss (outside click) dismiss; `Window.presentContextMenu(_:at:)`/`dismissContextMenu()` public for keyboard-driven use. Bonus: `MenuDropdown` now closes on focus loss everywhere, so menu-bar dropdowns dismiss on outside clicks too (6.8's v1 limitation removed) — and neither path steals focus from what was clicked. |

## Phase 6C — Editor v2: selection, clipboard, undo, find 🔄 100% (code complete, on `feature/editor-v2`; verification pending)

Driven by OmegaCLIDE (the IDE dogfood — see its PLAN Phase 3): an editor
without selection, copy/paste, undo, and find is not an editor. The document
engine moved out of the view into a pure, unit-tested `TextEditBuffer`
(rule 43: a real responsibility split, not a cosmetic one) — the view now
owns only input translation, painting, and the viewport.

| # | Item | Status | Notes |
|---|------|--------|-------|
| 6C.1 | `TextEditBuffer` | 🔄 Code complete | Pure editing engine: lines/cursor/selection state, ordered-range normalization, word/line selection, selection-aware insert/delete through ONE `replace` primitive, undo/redo as recorded invertible operations (typing runs coalesce; movement/paste/Return break the run; redo stack clears on new edits), `matches(of:)`/`replaceAll` search. Mutations report an `EditImpact` (`line`/`from`) so the view invalidates exactly the highlight-cache lines that changed. 14 unit tests, no rendering. |
| 6C.2 | Selection in `SyntaxTextView` | 🔄 Code complete | Shift+arrows/Home/End/Page extend; plain movement collapses (←/→ collapse to the selection's edge, platform-style); `^A` selects all; mouse drag selects (scrollbar grabs keep priority), double-click selects the word, triple-click the line (the 8.16 debounced `.click` counts). Selection paints in the theme's `selection` slot (+bold focused); a selected blank line shows one selected cell so multi-line selections read continuously. |
| 6C.3 | Clipboard + `Pasteboard` | 🔄 Code complete | Per-app `Pasteboard` (`app.pasteboard`, no globals) reached via the new `TUIView.owningWindow` / `Window.app` backpointers; copies forward to the terminal's system clipboard through the new optional `TerminalDriver.setClipboard` (default no-op) — `ANSIDriver` emits OSC 52, `HeadlessDriver` records for tests. Both chord families: `^C`/`^X`/`^V` and Ctrl+Insert / Shift+Delete / Shift+Insert (`Key.insert` + `CSI 2~` added to the decoder). `^C` is consumed only when a selection exists; editor-hosting apps should set `stopsOnControlC = false`. Read-only editors still select and copy. |
| 6C.4 | Undo / redo | 🔄 Code complete | `^Z` undo / `^Y` redo / Alt+Backspace alias; `canUndo`/`canRedo` for menu enablement; paste and Return are discrete steps; undo restores cursor *and* selection. |
| 6C.5 | Find / replace / goto API | 🔄 Code complete | `findMatches(of:caseSensitive:)` highlights every match (selection slot, dimmed; current match full) and stays live across edits; `findNext`/`findPrevious` wrap and select; `replaceCurrentMatch`/`replaceAllMatches`; `clearFind`; `scrollTo(line:column:)` centers the target (the goto-line / jump-to-diagnostic hook). The IDE's find bar is UI over exactly this surface. |
| 6C.6 | Tests | 🔄 Code complete | `TextEditBufferTests` (14: selection normalization, coalescing runs, undo/redo contracts, multi-line ops, find/replace) + `EditorSelectionTests` (10: chords both families, ^C-bubbles-without-selection, read-only copy, find wrap, paste-as-one-undo-step) — all keyboard-driven through `keyDown`, clipboard through an injected `Pasteboard`. |
| 6C.7 | Focus descent for composites | 🔄 Code complete | Found by the IDE (its shell focused a `DirectoryTree` — a wrapper that refuses focus — so keys went nowhere and its headless test hung): `makeFirstResponder` on a refusing view now descends depth-first to the first visible focusable descendant; a view with no focusable subtree still refuses. Composite controls become focus-forwarding for free. `FocusDescentTests` (3). |

Deliberately deferred: bracketed paste (reading the *system* clipboard is a
driver input feature), `TextView` parity via the shared buffer, and
column/block selection.

## Phase 7 — Styling & Theming 🔄 100% (code complete; verification pending)

| # | Item | Status | Notes |
|---|------|--------|-------|
| 7.1 | Style model | ✅ Done | Semantic `Theme` slots — `base`, `accent`, `selection`, `header`, `border`, `placeholder` — plus `borderStyle` (`none`/`single`/`rounded`/`double`/`heavy`, honored by `drawBox`, Panel/Dialog/FloatingWindow chrome, and menu dropdowns) and a three-color palette initializer that derives the rest; controls consult slots instead of hard-coding flags. |
| 7.2 | Theme cascade | ✅ Done | `TUIView.theme` override, nearest ancestor wins, root default `.standard` (exactly the pre-theme look, so it's behavior-preserving). Application is mechanical: the `Painter` carries a base style and substitutes theme colors wherever a drawn cell is `.standard` — the theme rides painter derivation like translation/clipping. `Window`/`Panel` fill their backgrounds. Reset-safe: every slot is a complete style; assigning `theme` repaints (test-proven via `renderIfNeeded`). |
| 7.3 | Built-in themes | ✅ Done | `standard`, `mono`, `dark`, `light`, plus Terminal.app-profile homages: `homebrew`, `grass`, `ocean`, `redSands`, `manPage`, `novel`, `pro`, `silverAerogel`; `Theme.builtIn` name/theme registry drives the demo's Theme menu. |
| 7.4 | CSS-like layer | ✅ Done | Design doc `Docs/StyleSheets.md` + v1. **Optional** (no sheets → exactly the theme behavior, unchanged) and **logical** (selectors are identity — type/`#identifier`/`.styleClasses`/`:focused` + descendants; properties are theme slots and text attributes only, never layout). Tolerant parser, id>class>type specificity with source-order ties, sheets cascade outer→inner, resolution lands in `effectiveTheme` so controls and the painter need no stylesheet awareness. Properties cover foreground/background for base and every slot, text attributes, accent, and `border:` styles. |

## Phase 8 — Demo & Polish 🔄 ~30%

| # | Item | Status | Notes |
|---|------|--------|-------|
| 8.1 | Demo app | 🔄 In Progress | Gallery (cells, view tree, layout, controls) + `--interactive` + `--events` driver viewer; grows with each control (AICoding rule 40). `--interactive` is now two **repeatable window factories**: a *manual* example (the original hand-wired tabbed window, incl. the Controls v2 "New" tab) and a *declarative* example built with TUIBuilder (the default at launch). File ▸ New spawns copies (^N/^M/^B); closing a window just dismisses it (^W / close box) — the app quits only via File ▸ Quit (^Q) or Ctrl+C. Theme menu restyles the top-most example. A third window type, **Contact Book** (^B), is the flagship for Phases 12+14: a global JSON-seeded store of US presidents, a builder-built master/detail (list + `✚ Add` on the left, a bound `Form` + notes + Save/Revert on the right rebuilt per selection), `@Bound` `$`-projections, `load()`/`save()`, and a Table window to confirm saves. Data is global, so edits survive closing/reopening a window within a run. A fourth, **Demo Source** (^D), browses the demo's own source: a directory `TreeView` + `SplitView` + closable folder `TabView`, each tab a breadcrumb over a read-only `SyntaxTextView`. **Structure:** `main.swift` is just the mode dispatch; `DemoApp` owns the desktop/menu shell; each window factory is a `DemoApp` extension in its own file under `Declarative/` (declarative + Contact Book + Demo Source) or `Traditional/` (manual example + event viewer), with the shared model in `ContactStore.swift` and the static gallery in `Gallery.swift`. |
| 8.2 | Headless demo test | ⏳ Pending | The demo renders identically through the headless driver — the phase exit criterion. |
| 8.3 | API review pass | ✅ done (2026-07-04) | Reviewed against the Swift API Design Guidelines. Surface: 1,084 public/open declarations vs ~1,500 internal — public < implementation ✓. Naming scan clean: no `get`-prefixed accessors, booleans read as assertions, silent-setter convention (`setX`, `select(_:notify:)`) consistent, only intentional typealiases (`Grid`, `Toggle`), zero force-unwrap chains. Fixes: removed `Theme.blendColors` (unused public wrapper over the internal `TerminalColor.blend`); `Dialog` promoted `public`→`open` to match `Window`/`FloatingWindow` (external apps can subclass-with-`body` the way `FileDialog` does). |
| 8.4 | Docs complete | ✅ done (2026-07-04) | Every public/open declaration now carries a `///` doc comment — a scanner pass found 170 gaps (theme slots, `bind` overloads, `ValueControl` witnesses, result-builder methods, Codable inits) and all were filled in house style; scanner now reports 0 missing of 1,084. `Architecture.md` brought current: full shipped control set, the four newer systems (theme matrix / stylesheets / TUIBuilder / data binding, each linking to its dedicated doc), multi-click input, `RichText` no longer "planned"; remaining-work note points at 8.10–8.12 and 8.2. Dedicated docs already current: Themes.md, StyleSheets.md, TUIBuilder.md, DataBinding.md, ControlsUML.md. |
| 8.16 | **Multi-click (double/triple) with guard time** | ✅ done (2026-07-04) | **Done via option (a):** low-level `.press`/`.release`/`.drag` stay immediate (drags, scrollbar grab, cursor placement unaffected); a new debounced `MouseInput.Action.click` carries `clickCount` (1/2/3, capped at 3). `App` tracks left press→release pairs at the same cell (`clickSlop = 1`), coalescing clicks within `multiClickInterval` (default 280 ms, configurable) via a one-shot guard timer on the existing `schedule(after:)`/`TimerSource` path — so the single-click event never fires ahead of a double. `MouseInput` gained `clickCount`. **Revised (2026-07-04, after "single fires before double"):** the first cut kept row *selection* on the raw press, so a double-click still ran the single-click action (`onSelectionChanged`/preview) before the open. Fixed by moving *all* click-driven behavior in the selection controls onto the debounced `.click`: `ListView`/`TableView`/`TreeView`/`Browser` now **select** on `.click` count 1 and **activate** on count ≥ 2 (TableView header sorts on the settled click; TreeView's disclosure toggles once; TreeView toggles a branch / activates a leaf on a double). The raw press only drives non-semantic gestures (scrollbar grab/page, focus, window move/resize) — nothing that fires a single-click action ahead of a possible double. **Tradeoff:** click-to-select now waits out `multiClickInterval` (~280 ms) before it highlights — the accepted guard latency; tune `App.multiClickInterval` lower for a snappier feel. **Second revision (same day):** a double still ran *both* callbacks — the count-2 click moved the selection via the notifying path, so `onSelectionChanged` (the single-click action, e.g. Demo Source's open-in-current-tab) fired right before `onActivate`. Now a count ≥ 2 click moves the highlight *silently* (the `select(_:notify:)` path) and fires ONLY `onActivate` — a double is only ever the double action. Tests: `multiClickGuardCoalescesPressesIntoClickCounts` (App-level, `ManualTimerSource`), `listDoubleClickActivatesTheRow`, `treeDoubleClickActivatesLeavesAndTogglesBranches`, `browserClickSelectsAndDoubleClickActivates`. **VTG path still open:** if `VectorTerminalSDK` ever adds a native click-count, the driver can populate `MouseInput.clickCount` directly and skip the client guard — the framework fallback stays for plain terminals. **Original design notes:** Today a left press dispatches immediately, so a single click can't be told apart from the first of a double. Add **click-count** detection in the input/routing layer: consecutive left presses on the *same target near the same position* within a **guard interval** coalesce into count 2, then 3 (reset on timeout, a different button/target, or movement past a drag threshold). Because you can't know a click is single until the guard elapses, the single-click *semantic* event is **held for the guard interval** before dispatch — accepted latency, like desktop OSes. **Design choice to make:** either (a) keep low-level `.press`/`.release`/`.drag` immediate for responsiveness (window drags, scrollbar grab, cursor placement) and add a *separate* debounced `click(count:)` semantic event, or (b) delay press dispatch wholesale (simpler event model, laggier). Leaning (a). Uses the `App` timer for the guard (~250–300 ms, configurable); `MouseInput` gains `clickCount`. **Cap at 3** — double = activate/open, triple = select-line/all; there's no established use for 4/5 (Apple's `clickCount` is unbounded but real UIs stop at 3), so the counter may keep counting internally but nothing should depend on >3. Replaces the current timing-free "re-click the selected row = activate" stand-in in TreeView/ListView. **VTG check (2026-07-04):** `VectorTerminalSDK`'s `VTGMouseEvent` has a synthesized `click` type + hit regions but **no click-count / double-click field** — so multi-click counting must live in *this* framework's input layer regardless (VTG only removes the "was it a drag?" question, not "how many clicks?"). Keep the debounce shared (works on plain terminals now, feeds off VTG `down`/`up`/`click` later). If VTG ever adds a native count, the driver can populate `MouseInput.clickCount` directly and skip the client-side guard on VTG terminals — the same "native beats fallback" rule VTG uses for pixel-vs-cell coords. Alternative: add click-count to the VTG protocol itself (cleaner, no client timer) — but plain terminals still need the fallback, so the framework path stays either way. |

| 8.17 | **New windows must inherit the selected app theme** | ✅ demo fix (2026-07-04) | Bug (from a Turbo screenshot): after picking Turbo from the Theme menu, a window opened *afterward* via File ▸ New came up in the standard theme. Root cause was demo-side, not framework: `App.applyTheme` cascades by clearing each **existing** window's `theme` override to `nil` so it inherits the desktop — but the demo window factories (`ContactBook`, `DeclarativeExample`) hardcoded `window.theme = .standard`, so a freshly built window re-introduced the override and ignored the desktop's Turbo. Fix: drop those per-window overrides so new windows inherit the app theme (the desktop) like the cascade intends; `themeContext` stays. Note: the demo's launch default is `desktop.theme = .dark` (`DemoApp.swift`), so the initial windows now come up dark rather than standard — change that one line if a different default is wanted. **Possible framework follow-up:** `applyTheme` could also stamp windows presented later (e.g. track the app theme and apply on `present`), so a hardcoded per-window override isn't silently wrong — but the cascade already covers the common case. |

| 8.18 | `Menu.removeAllItems()` (dynamic menus) | ✅ done (2026-07-05) | Driven by OmegaCLIDE's Window menu (live list of open projects): menus whose contents track state clear and rebuild before the next open — dropdowns read `items` at open time, so no further plumbing was needed. `MenuItem.title`/`isEnabled` were already mutable; this was the one missing primitive. |
| 8.19 | `DirectoryTree` expansion state API | ✅ done (2026-07-05) | Driven by OmegaCLIDE session restore: `expandedPaths` (parents-first snapshot) + `expand(path:)` (expands ancestors along the way; lazy children load per level; foreign paths ignored). Editor cursor/scroll needed NO new API — `cursorPosition`, the `BorderScrollable` spans, `scrollTo`, and `setScrollOffset` already cover capture and restore. |

### Turbo / Borland theme — 8.5–8.8, 8.13–8.15 ✅ (done 2026-07-04, including 8.8's shadow/press animation)

Recreate the classic Turbo / Borland IDE look (Turbo Pascal, Turbo C, …) — royal-blue desktop,
cyan double-bordered dialogs with drop shadows, a gray menu bar, green
shadowed buttons, yellow static labels, **red accelerator letters**, and the
bottom F-key strip — as a built-in theme *plus* the few framework features an
authentic rendering needs. Serves as a strong end-to-end stress test of the
theming, chrome, and input layers.

**Standing constraint (Bobby):** solid colors, **never shade/hash patterns** —
the Borland desktop's dotted `▒` fill and its window/button shadows all become
solid fills.

Much of the palette is already expressible via the `Theme` slots +
`borderStyle: .double` + `Desktop.fillStyle`. The real work is the
interactive/rendering gaps below.

| # | Item | Priority | Notes |
|---|------|----------|-------|
| 8.5 | `.turbo` built-in theme | core | Blue desktop, cyan window base, gray/black menu bar, yellow static text, double borders. Likely needs a **filled-pill button color** and a distinct **menu-bar slot** beyond today's `base`/`accent`/`selection`/`header`/`border`/`placeholder`/`scrollbar` set. **Baseline done (2026-07-04):** `Theme.turbo` (EGA palette — yellow-on-blue base, white `.double` borders, gray/black `header` = menu bar + titles, cyan `selection`/`accent`, navy scrollbar) registered as "Turbo Pascal" in the picker; the demo's Theme menu now also paints the desktop with the theme's background (Borland blue) via `Desktop.fillStyle`. Reuses `header` for both menu bar and titles, and `selection` for rows and menu highlights — the dedicated menu-bar slot, filled-pill buttons (8.8), red accelerator hints (8.6), and border-embedded scrollbars (8.7) are the improvements from here. |
| 8.6 | **Keyboard accelerator hints** | ✅ done (2026-07-04) | The highlighted mnemonic letter (Borland's red letters) on menus and buttons, drawn in an accent color, activated by Alt+letter. **Done:** an `&`-marker convention (`Accelerator` parser in `Views/Accelerator.swift` — `"&File"`/`"S&ave"`, `&&` escapes) plus new theme slots `acceleratorColor`/`acceleratorAttributes`, set on **every** theme — not Turbo-only (Turbo = bright red `#FF5555` no underline; `standard`/`surface` = accent + `.underline`) and `ResolvedTheme.accelerator(over:)` which recolors the letter while keeping the surrounding surface's background — falling back to the face's own foreground (underline still marks it) when the accelerator color equals the fill, since surface themes derive both the default-button pill and the accelerator color from the accent (the invisible "S" on Dark's blue Save pill; locked by `mnemonicStaysVisibleOnAccentFilledButtons`). Wired into `MenuBar` titles (Alt+F opens the menu), `MenuDropdown` items (bare letter activates in an open menu, red highlight), and `Button` (Alt+letter via `handleHotKey`, red mnemonic). Demo menus/buttons/dialogs carry `&` markers. Tests: `AcceleratorTests`. |
| 8.7 | **Border-embedded scrollbars** | ✅ done (2026-07-04) | The Borland/Turbo trick: a window's scrollbars drawn *into its chrome*. **Done:** new `BorderScrollable` protocol (`ScrollSpan` per axis + clamped `setScrollOffset` + `showsOwnScrollbars`) in `Controls/BorderScrollbars.swift`; `Panel.embedScrollbars(for:vertical:horizontal:)` (forwarded by `FloatingWindow`) draws the vertical bar on the **right border** and the horizontal bar on the **bottom border**, reading the client's live spans every frame (the full-tree redraw makes that free). Bars use the solid `ScrollView.indicatorStyles` track/thumb plus `▴▾◂▸` arrow endpoints (step 1); track press pages; thumb drags proportionally; the resize corner and title buttons keep priority; bars paint after border/junctions so overlaps are deterministic. **Extents:** `BorderScrollbarExtent.fullEdge` / `.underClient` — the bottom bar defaults to `.underClient` (under the editor only, not the sidebar tree), the right bar to `.fullEdge` with `.underClient` proving partial runs work (per Bobby: full height now, partial supported for later). `SyntaxTextView` conforms; embedding flips `showsOwnScrollbars` off so the interior column/row returns to text. Demo Source embeds the active tab's editor, re-wiring on tab open/select/close. Unembedded windows are pixel-identical (bars draw only for a live client). **Bars are permanent chrome** (revised same day, from Bobby's grow/shrink report): they do NOT pop in and out with overflow — when the content fits an axis the thumb fills the track, exactly like the Borland IDE, so resizing past the content and back never "loses" a bar. Tests: `BorderScrollbarTests` (chrome placement + sidebar exclusion, page/arrow/drag interaction, partial vertical run, permanent-chrome across grow/shrink). Follow-up candidates: adopt on `ScrollView`/`ListView`/`TextView`. |
| 8.8 | Filled "pill" buttons + press animation | ✅ done (2026-07-04) | A filled-background button style (green pill). **Pills:** `Button.Role` (`.normal`/`.default`/`.destructive`); `.default`/`.destructive` fill as a pill from the theme's `defaultButton`/`destructiveButton` slots (Turbo = solid green / red; colorless themes = colored text), keeping that color through focus (bold) and press (inverse). `Dialog.addButton` gained `isDestructive:` and now sets `.default` on the default button; builder `.role(_:)` modifier. **Shadow + press animation (landed same day):** a **theme setting** — new `buttonShadowColor` slot (`.standard`/omitted = no shadow; only Turbo sets one, black). When set, every button's intrinsic grows one column + one row and the face casts a solid shadow **below, shifted one right** (below only — revised same day per the Turbo reference; no cell beside the face); a mouse **press animates the face onto the shadow position** (shadow hides, face keeps its color — the motion is the pressed cue, no inverse) and release pops it back, exactly per the spec ("the animation is conditional on the shadow"). Gated on frame room, so hand-framed 1-row buttons render flat. **Companion framework fix:** theme/`themeContext` changes now invalidate *layout* for the whole subtree, not just display — intrinsics are theme-dependent, and the old display-only dirtying left stale frames after a Theme-menu switch (truncated "Res…" faces, missing red mnemonics, shadows only appearing after a click). Locked by `themeSwitchRelayoutsThemeDependentIntrinsics`. `Dialog.preferredSize` measures the button row from intrinsics (re-`sizeToFit` after presenting under a themed app — see the demo's quit dialog). Tests: `defaultAndDestructiveButtonsFillFromTheirThemeSlots`, `turboButtonsCastADropShadowAndPressOntoIt`. |
| 8.13 | Themeable input-field well (background, not underline) | ✅ done (2026-07-04) | Editable controls drew a hardcoded `.underline` well; now they draw from the model's `field` slot (`fieldForeground`/`fieldBackground`/`fieldAttributes`). **Done:** `TextField.draw` renders its well, visible text, and cursor from `effectiveTheme.field` (placeholder overlays the placeholder foreground + `.dim` on the same well). `standard`/`surface` set `fieldAttributes = [.underline]` so today's look is unchanged; `.turbo` sets a blue well (`#0000AA`) with yellow text (`#FFFF55`), no underline. Test: `textFieldWellUsesTheThemeFieldSlot`. |
| 8.14 | **Context-matrix theme architecture** | ✅ done (2026-07-04) | **Shipped** as `Views/ThemeModel.swift` (+ built-ins rewritten in `Views/Theme.swift`): `Theme` = complete `base` `ThemePalette` + sparse per-context overlays; `resolved(for:)` → flat `ResolvedTheme` with the CellStyle conveniences; `TUIView.themeContext` (nil = follow parent) rides the same superview walk as `effectiveTheme`; everything Codable (JSON themes); rainbow-fixture tests guard the nil→base fallback per slot/context; Turbo is the multi-context example. Original spec: replace the single flat `Theme` with a *slot × context* matrix — a complete `base` palette plus sparse, nullable overlays for `desktop` / `contentWindow` / `secondaryWindows` / `modalWindows` / `accessoryView` (resolve = `context[slot] ?? base[slot]`; `base` has no nils). Rename slots to flat descriptive keys (`selectionForeground`, `fieldBackground`, …). Make `Theme`/`ThemePalette`/`TerminalColor` **Codable** so themes ship/load as JSON files. Windows carry a `themeContext`; the `Painter` resolves through it. **Full design in `Docs/Themes.md`.** This is what lets the menu/status bars be gray while the code editor is blue — the collisions the shipping single-theme has (`header` = bar + titles, `selection` = rows + menus). |
| 8.15 | CSS is an on-top layer + demo toggle | ✅ done (2026-07-04) | Also covered by the CSS Demo window (`Declarative/StyleTest.swift`): type/#id/.class/combined selector tests behind a None/Control/ID/Style/Complex picker, layering over whatever theme is active. Original spec: clarify (in code + demo) that stylesheets (`StyleSheet`) apply **on top of** the resolved theme — theme (base → context) → CSS by specificity → drawn cell — and are **not** themes. Change the demo so CSS is an independent **toggle alongside** the theme dropdown (today it's presented as a `Theme ▸ CSS` entry, as if CSS were a theme): pick any theme, then flip the stylesheet on/off to see it layer over whatever's active. **Disabling CSS is just `styleSheet = nil`** — no separate state; the toggle is `view.styleSheet = on ? sheet : nil`, and the theme underneath is never touched. **Done (2026-07-04):** the Manual Example already had an independent CSS `ToggleButton` beside the theme pop-up doing exactly `styleSheet = on ? sheet : nil`; relabeled the misleading "Theme ▸ CSS" wording to frame CSS as an on-top layer. Layering + nil-reverts locked by `stylesheetTogglesOnAndOffOverAChosenTheme`. |

Bobby's notes from the reference screenshots: expect a follow-up request to
swap any patterned fills for solid ones; the button press-down animation is a
low-priority flourish. The red keyboard-hint letters (8.6) — the feature most
likely missing — are now in, alongside filled pill buttons (8.8) and themeable
field wells (8.13). What remains of the Turbo look is border-embedded
scrollbars (8.7).

Follow-up fixes (2026-07-04, from a Turbo screenshot):
- **Outside-press dismisses open overlays.** A press on the desktop or another
  window left menu dropdowns / pop-up lists / context menus open (the overlay's
  own window never saw the press). Added `TUIView.dismissesOnOutsidePress`
  (overridden by `MenuDropdown`/`PopUpList`) + `Window.dismissOverlayIfPressOutside`,
  called from `App`'s press routing; the press still routes normally afterward.
  Test: `pressOutsideAnOpenMenuDismissesItButInsideSelects`.
- **Ordinary buttons get their own theme slot.** A `.tinted` button drew its
  label in the `accent`, which on Turbo (green on gray) was both low-contrast
  and indistinguishable from a label. Added a `button` slot
  (`buttonForeground`/`buttonBackground`), symmetric with
  `defaultButton`/`destructiveButton`; `ControlStyle.restingStyle` rests on it.
  Defaults preserve every theme's look — the background is the window's own, so
  the pill is invisible and reads as today's accent text (Mono → underline).
  Turbo sets a distinct dark-gray pill (`#555555`, white text) so Reset reads as
  a button. Test: `ordinaryButtonsRestOnTheThemeButtonSlot`.

### Window state — 8.9–8.12 (maximize / restore / minimize)

`FloatingWindow` today only moves and resizes by drag. Add explicit window-state
commands so windows behave like desktop windows.

| # | Item | Priority | Notes |
|---|------|----------|-------|
| 8.9 | Maximize / restore | core | A `FloatingWindow.windowState` (`.normal` / `.maximized`) with `maximize()`/`restore()`/`toggleMaximize()`. Maximize fills the desktop (respecting the menu-bar strip and global status row); restore returns to the saved "normal" frame. Trigger via a title-bar affordance (e.g. a `▢` box next to `[x]`), a double-click on the title row, and/or a keyboard shortcut. Save the pre-maximize frame so restore is exact. |
| 8.10 | Minimize | core | `.minimized` state: the window collapses off the desktop to a compact representation. Options to decide at design: a title-only bar docked to a screen edge, or an entry in a taskbar/dock strip along the bottom (reusing `StatusBar`), with a click/shortcut to restore. Keep the normal frame for restore. |
| 8.11 | Normal size | core | An explicit "restore to normal" that returns a maximized *or* minimized window to its saved `.normal` frame — the middle button of the classic min/normal/max trio. |
| 8.12 | Chrome + shortcuts | needed | Title-bar buttons for the trio (drawn in the Panel top border like `[x]`), a menu (e.g. a Window menu) exposing the same commands, and standard keys. Coordinate with `App` so maximized windows follow terminal resizes (like `fillsScreen`) and restore cleanly. |

Depends on nothing new; it is `FloatingWindow` + `App` state plus Panel-border
affordances. Minimize's docked representation may want a small new view type.

**Status (2026-07-04):** 8.9 / 8.11 / most of 8.12 **done**. `FloatingWindow`
has `windowState` (`.normal` / `.maximized`), `maximize()` / `restore()` /
`toggleMaximize()`, and `maximizeInsets` (reserve edges — the demo's Demo Source
keeps the menu-bar strip + status row visible). `Panel` draws a `[+]` / `[=]`
maximize box left of `[x]` (with `onMaximize`, and the title reserves room for
it); grabbing the title of a maximized window hands geometry back to the user;
`App` re-flows maximized windows on terminal resize. Tested in
`WindowStateTests`. **Still pending: 8.10 (minimize)** — needs the docked/taskbar
representation decision — and the optional Window-menu + keyboard shortcuts in
8.12 (the title-bar `[+]` button is the current trigger).

## Phase 9 — Tutorial ✅ 100%

A step-by-step "Building with TUIKit" tutorial (`Docs/Tutorial/`), written
for someone who has never used the framework. Each chapter is a short read
ending in a runnable milestone; the code for every milestone lives in a
`TUIKitTutorial` executable target so it compiles (and is tested headlessly)
forever — a tutorial that drifts from the API is worse than none.

**The tutorial app is built the declarative way (TUIBuilder) throughout** —
that is the recommended, front-page style. The traditional hand-wired
approach (`addSubview`, frames/anchors, manual event wiring) appears exactly
once, in Chapter 6, as an appendix for people who prefer the old school —
it shows the same app both ways and notes that both produce the identical
`TUIView` tree.

| # | Item | Status | Notes |
|---|------|--------|-------|
| 9.1 | Outline & ground rules | ✅ done (2026-07-04) | `Docs/Tutorial/README.md`: the growing To-Do app, the runnable-milestone rule (every snippet is a verbatim excerpt of the compiling `TUIKitTutorialMilestones` code), the declarative-first policy (Ch1–5 TUIBuilder; Ch6 is the traditional appendix), and the chapter table. |
| 9.2 | Ch. 1 — Hello, terminal | ✅ done (2026-07-04) | App + driver, zero-frame Window, `setContent`/builder basics, `app.run { }` sugar, quitting (Ctrl+C, Quit button, Alt+Q mnemonic). |
| 9.3 | Ch. 2 — Layout | ✅ done (2026-07-04) | Intrinsic vs flexible children, VStack/HStack, Panel, Divider, Spacer — the shell (header, two panes, status) with zero hand-computed frames. |
| 9.4 | Ch. 3 — Controls & events | ✅ done (2026-07-04) | The declarative to-do form: controls as plain values, one `addTask()` path, semantic events (`onSubmit`/`onSelectionChanged`/`onActivate` incl. the single- vs double-click debounce), TabView/Tab, `.role(.default)`, `makeFirstResponder`. |
| 9.5 | Ch. 4 — Focus, keys & mouse | ✅ done (2026-07-04) | The hot → focused → Tab → cold routing order; `Chapter4Window.handleHotKey` gives Ctrl+N from anywhere; mnemonics recap; mouse comes free. |
| 9.6 | Ch. 5 — Testing your app | ✅ done (2026-07-04) | HeadlessDriver as a full driver: the boot/send/snapshot pattern, quoting the REAL CI tests (keyboard walkthrough, hot-key + resize reflow); no `@testable` anywhere — the tutorial provably uses only public API. |
| 9.7 | Ch. 6 — Traditional approach | ✅ done (2026-07-04) | Shipped as specified — `Chapter6.swift` rebuilds the Ch3 form hand-wired (construct → anchor → wire → `addSubview`), and `chapter6MatchesChapter3Behavior` proves the two styles behave identically. Original spec: the old-school appendix: rebuild one milestone from the earlier chapters with hand-wired views (`addSubview`, frames/anchors, manual event closures) instead of TUIBuilder. Purely for readers who prefer imperative construction — the chapter states up front that the declarative style from Chapters 1–5 is the recommended path, that everything in TUIKit works identically both ways (builders emit the same `TUIView` tree), and when dropping down is genuinely useful (dynamic view graphs, custom containers). Mirrors the demo's `Traditional/` vs `Declarative/` split. |
| 9.8 | `TUIKitTutorial` target + CI test | ✅ done (2026-07-04) | Three targets: `TUIKitTutorialMilestones` (library, public-API-only so tests can render chapters), `TUIKitTutorial` (runner; no-arg prints the chapter listing), `TUIKitTutorialTests` (landmark render per chapter + Ch3 keyboard walkthrough + Ch4 hot-key/resize + Ch6≡Ch3 equivalence). |

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

**Status (2026-07-11):** the core shipped on `feature/vtg-chrome` (docs:
`Docs/VTGChrome.md`; tests: `VTGChromeTests`, 12 green). The first chrome
pass covers the pieces Bobby asked for — a *pretty titlebar* (gradient,
rounded top corners, centered title, circular close/maximize buttons) and
*rounded-corner buttons* — via the new **Ambiance** built-in theme
(Ubuntu-inspired: aubergine gradient desktop, dark titlebar with the orange
close circle at the LEADING side, light gradient pills with an orange focus
glow). **Note:** VectorTerminalSDK requires macOS 16, so the package's
platform floor moved 15 → 16 (flagged in NEEDS_HUMAN.md). Verification on a
real VectorTerminal is still pending — everything below is headless-proven.

| # | Item | Status | Notes |
|---|------|--------|-------|
| 10.1 | Capability detection & fallback contract | 🔄 Code complete | `ANSIDriver.begin()` probes `capabilities?` + `glyphSize?` (400 ms budget, on the output queue, BEFORE the input read source starts so the probe owns its APC responses); no glyph metrics → chrome off. `TerminalDriver` gains defaulted `supportsGraphicsChrome`/`presentChrome` so every other driver is untouched. `TUIKIT_VTG=0` opts out. Fallback proven by tests: chrome off → zero commands, pre-Phase-10 cells. |
| 10.2 | VTG driver integration | 🔄 Code complete | `VectorTerminalSDK` (1.5.6+) is the new in-house dependency, confined to the driver layer. The canvas writes through an `FDSink` on the driver's existing output queue (serialized with cell presents; EAGAIN-safe), wrapped in `startFrame`/`endFrame` per chrome frame; identical consecutive frames write nothing; `end()` clears the retained scene. Canvas state is queue-confined (`VTGState`), honoring the never-block rule (probe waits on GCD, not a cooperative thread). |
| 10.3 | Cell↔pixel geometry | 🔄 Code complete | Framework side stays pixel-free: chrome geometry is **fractional cells** (`ChromeRect`/`ChromePoint`; scalar sizes in cell heights). The driver-owned `CellPixelMapper` (pure, tested) converts with the probed glyph metrics, rounding edges independently so gradient strips stay seamless. |
| 10.4 | Internal chrome surface | 🔄 Code complete | `ChromeSurface` (`painter.chrome`, present only when chrome is enabled) mirrors `Painter`: same origin/clip derivation, so the clipping contract holds for chrome (test-proven). Typed `ChromeCommand`s (rounded rects, circles, lines, `verticalGradient` = base + corner-inset strips) with view-scoped retained ids (`renderTree` stamps view identity); `ChromeSceneReconciler` (pure, tested) plans each frame — unchanged → nothing, same id order → in-place updates of changed shapes only, reordered (window raise/open/close) → full rebuild, because retained objects keep creation-time stacking and an in-place update would stack chrome differently than the cells above it. Public-but-passive: apps never need it, controls use it internally. |
| 10.5 | Control & window chrome pass | 🔄 First pass | Shipped: `Desktop` (backdrop gradient + window shadows), `Panel` window chrome (vector titlebar w/ theme-set `buttonPlacement` — hit-testing follows the visual side), `Button` (rounded gradient pill, focus glow, press flips gradient; role pills derive from the cell slots). Themes style it all via the new Codable `ThemePalette.vector: VectorChrome?` (titleBar/button/desktop/windowShadow). Remaining candidates: field wells, scrollbar thumbs, tab folders, menu bar. |
| 10.6 | VTG input routing | ✅ Done (no-op by design) | VectorTerminal emits standard SGR mouse reporting, which the Phase 2 decoder already routes as cell-coordinate `MouseInput` — no VTG-native event path needed. Revisit only if pixel-precision gestures ever matter. |
| 10.7 | Headless VTG testing | 🔄 Code complete | `HeadlessDriver(supportsGraphicsChrome: true)` records `presentedChrome`/`chromePresentCount`. `VTGChromeTests` (12): mapper rounding/scalars, reconciler, gradient-inside-arcs geometry, chrome clipping, Ambiance titlebar (incl. leading-close hit test) + pills + backdrop/shadow ordering, chrome-off fallback (cells + trailing `[x]` hit test), App activation both modes, theme JSON round-trip. |
| 10.8 | Demo & fallback proof | ⏳ Pending | Ambiance is in `Theme.builtIn`, so the demo's Theme menu already offers it. Still to do: run the untouched demo inside a real VectorTerminal and confirm full chrome + identical behavior vs. a plain terminal (the phase exit criterion) — needs a human with the VectorTerminal app (see NEEDS_HUMAN.md). |

## Phase 11 — Controls v3 ⏳ 0% (rev 2)

**Rev 2 — after 1.0**, alongside the VTG work. 11.1/11.3/11.4 folded into Phase 16 (control parity), where their design is now specified; 11.2 Sheets and 11.5 Tooltips stay here.

| # | Item | Status | Notes |
|---|------|--------|-------|
| 11.1 | `SearchField` | → 16.2 | TextField variant: hint icon, clear affordance, incremental `onSearch` as you type, Esc clears. |
| 11.2 | Sheets | ⏳ Pending | Window-attached modal: a dialog that anchors to (and visually hangs from) a specific window's title bar instead of centering on screen; blocks only that window in a non-modal stack. |
| 11.3 | `ImageView` | → 16.20 | Raster display: cell-art/braille approximation in plain terminals; real raster via the VTG layer (Phase 10) when the terminal supports it. |
| 11.4 | `TokenField` | → 16.15 | Tag pills inside a text field: typing + Return mints a token, Backspace removes, tokens navigable with ←/→; `onTokensChanged`. |
| 11.5 | Tooltips | ⏳ Pending | Hover text after a delay (mouse-move events already decoded; uses the 6B.6 timer story); per-view `toolTip` property; renders as a small floating panel that never takes focus. |

## Phase 12 — TUIBuilder (declarative layer) 🔄 33%

An **optional** SwiftUI-shaped, **non-reactive** builder over the controls
(`Sources/TUIKit/Builder/`). Design doc: `Docs/TUIBuilder.md`. Controls take
defaults (declare only differences); parents lay children out; the manual
imperative API stays a first-class peer. Builds a plain `TUIView` tree once — no
state graph, no diffing.

| # | Item | Status | Notes |
|---|------|--------|-------|
| 12.1 | Core: `Component` / `Composable` / `@NodeBuilder` | ✅ Done | `Component` = `makeView()` currency (every `TUIView` conforms); `Composable` = compounds with a `body` (split from `Component` to avoid colliding with `Dialog.body`); `NodeBuilder` supports lists, `if`/`else`, `for`. 4 builder tests. |
| 12.2 | Containers + `Spacer` | ✅ Done | Result-builder `convenience init`s on `VStack`/`HStack`/`ScrollView`/`Panel`; `Spacer(minLength:)`. Default `.fill` cross-alignment = "line up in the parent." |
| 12.3 | Modifiers | ✅ Done | Structural (`Configured`: `padding`/`frame`/`fill`/`centered`/`anchors`/`id`/`styleClass`/`theme`/`hidden`/`configure`) + typed per-control chainable setters (`onActivate`/`onChange`/`onSubmit`/`onSelectionChanged`/`onValueChanged`/`style`/`bold`/…) + `Ref<T>`. |
| 12.4 | Hosting (`TUIView.setContent`, `App.run { }`) | ✅ Done | `setContent { }` replaces a view's children with one fill-anchored root (several → a `VStack`); `App.run { }` runs a window whose content is the built tree. Both tested (incl. headless `run`). |
| 12.5 | `Form`/`Field` + `ZStack` | ✅ Done | `Form { Field("Name") { … } }` lowers to a `GridView` (fixed right-aligned label column + flexible control column) and computes its own intrinsic size, so the labels line up and controls fill with **zero** layout code — principle #2 made real. `ZStack` overlays fill-anchored children. Tested (label alignment across rows, overlap order). |
| 12.6 | Demo: declarative example window | ✅ Done | The `--interactive` default window is built with the DSL (`Form` rows + toggle + slider→progress + buttons), hosted via `setContent`. Proves compounds/controls/`Form` compose with defaults. |
| 12.7 | `Grid`/`GridRow` + `Tab`/`SplitView` DSL | ✅ Done | `Grid(columns:) { GridRow { … } }` with `.gridSpan(columns:rows:)` (cells fill columns left-to-right); `TabView { Tab("…") { … } }`; `SplitView(.horizontal) { first; second }`. `Grid`/`Toggle` are typealiases to `GridView`/`ToggleButton`. Tested (cell placement + spans, tab titles, two-pane split). |

## Phase 13 — TUIView base rename ✅

Rename the framework's base class `View` to **`TUIView`** so a program can
`import SwiftUI` and `import TUIKit` together without the two `View`s colliding
— important now that TUIBuilder (Phase 12) gives TUIKit a SwiftUI-shaped call
site. Only the base class is renamed; `*View` control subclasses
(`ScrollView`, `TableView`, `TabView`, …) keep their names and module-qualify
against SwiftUI if ever needed. No back-compat `typealias View = TUIView` — it
would reintroduce the very ambiguity we're removing.

| # | Item | Status | Notes |
|---|------|--------|-------|
| 13.1 | Rename `View` → `TUIView` in the framework | ✅ Done | Class, all inheritance, type annotations, params, and `[View]`/`View?` across `Sources/`. Method/property names with lowercase `view` (`superview`, `subviews`, `addSubview`, `makeView`) are unchanged. File `Views/View.swift` → `Views/TUIView.swift`. |
| 13.2 | Update tests + demo | ✅ Done | Same token rename across `Tests/` and `Demo/`; a demo heading string stays user-facing. |
| 13.3 | Update docs | ✅ Done | `Architecture.md`, `ControlsUML.md`, `TUIBuilder.md`, `StyleSheets.md` base-class references. |

## Phase 14 — Data In / Out (form binding) 🔄

A **non-reactive** data layer (design doc: `Docs/DataBinding.md`) under
`Sources/TUIKit/Data/`. Two surfaces on one foundation; control sources
untouched (all conformances are extensions), so it's optional and removable.
`setAnyValue`/`pull` always use the control's **silent** setter, so data-in
never re-fires events — the "safe to repeat" property.

| # | Item | Status | Notes |
|---|------|--------|-------|
| 14.1 | `ValueControl` foundation | ✅ Done | `anyValue()`/`setAnyValue()` + `ValueError` + lenient `Coerce` (numeric/string). One extension per value control (String/Bool/Int/Int?/Date/Color/Double). |
| 14.2 | `name` + dotted-path lookup | ✅ Done | `TUIView.name` (distinct from stylesheet `identifier`); `named(_)`, `view(named:)`, `value(for:)`/`setValue(_:for:)` resolve `"address.city"` over **all** descendants (hidden included), first match per segment. |
| 14.3 | Bulk dict I/O | ✅ Done | `formValues() -> [String:Any]` (keyed by full dotted path) / `applyValues(_:)` (unknown keys ignored, mismatches throw). |
| 14.4 | `Binding` + per-control `bind` | ✅ Done | `Binding<T>` (get/set), `Bindings` (`@dynamicMemberLookup` → `$model.x`, **no macro**), `FieldBinding` storage on `TUIView`, `Bindable` protocol with key-path + closure overloads; every value control conforms. `.named`/`.bind` chain in the builder. |
| 14.5 | `load()`/`save()` + `live` | ✅ Done | Recursive, idempotent tree sync (`pull`/`push`); `bind(live:)` composes with the control's existing change event (user handler still runs). |
| 14.6 | `@Bound` macro | ✅ Done | `@Bound var name = ""` on a class → a `$name` `Binding` projection (`field.bind(model.$name)`); the type is **inferred** from the literal initializer (`""`/`0`/`0.0`/`false`), non-literals annotate. Implemented in a new `TUIKitMacros` compiler-plugin target on **`swift-syntax`** (`603.0.0+`) — the one non-in-house dependency, confined to the plugin so the library runtime stays dependency-free. Slower builds are an accepted trade for the ergonomics. |
| 14.7 | Tests + docs | ✅ Done | 7 headless tests (round-trip/coerce, silent, dotted paths, dict I/O, key-path load/save idempotence, closure binding, live); `Docs/DataBinding.md`. |

## Phase 15 — TUICodeEditor ⏳ 0% (plan ready)

A second product target: a source-code editor on par with SwiftyCodeEditor's
core (Bobby, 2026-08-10 — headline gaps: syntax coloring and the gutter),
with deliberate CLI concessions. E0 decided (Bobby, 2026-08-10): **Option B —
port SwiftyCodeEditor's core rather than depend on it** ("a CLI tool dependent
on a GUI tool just seems wrong"), every ported file carrying a provenance
header (source path, upstream commit `5bbc08c`, divergences) so periodic
refresh sweeps are a diff, not archaeology.

The ported logic lands in **`CodeEditorCore`** — a new Foundation-only package
at `UILess/Code/CodeEditorCore`, sibling to this one — so the non-UI half is a
clean library the GUI editor *could* adopt later to collapse the duplication.
SwiftyCodeEditor is not restructured by this plan; no split is forced on it.
Full plan and parity matrix: **`Docs/CodeEditorPlan.md`**.
`SyntaxTextView` stays for plain-text duty; the IDE swaps editors at E8.

## Phase 16 — Control Parity (ActiveUI gap fill) 🔄 89%

Source: **`CONTROL_PARITY.md`** — every ActiveUI catalog page mapped to its
TUIKit twin (33 ✅ / 31 🟡 / 11 ❌ / 6 ➖ as of 2026-08-21). This phase is the
fill plan for the 🟡 and ❌ columns. Decided (Bobby, 2026-08-21):

- **Basic usability, not parity.** Each control ships the shape and the 80%
  use. Missing filters, modes and options are acceptable — name them in the
  class doc comment so nobody hunts for them.
- **Cells first, always render something.** Where cells genuinely cannot do
  the job, the cell form is an *honest placeholder* — a framed
  "VTG graphics required" notice (Canvas is the prime example) — never a
  blank, never a crash. Under VTG it is the real thing. Existing
  `suppressesVectorChrome` gallery pattern shows both side by side.
- **Placeholder + menu** (ImageView is the model): the cell form is a framed
  card (name, dimensions, format) with a context menu — Open in Viewer,
  Copy, Paste — so the control is *usable* over SSH; the VTG form draws the
  pixels.
- **Big subsystems are sibling packages**, like `TUIWebBrowser`:
  `TUITerminal` first (OmegaCLIDE needs it), `TUIDiagram` and `TUIBoards`
  later if wanted.
- **Editors lean on what exists.** `MarkdownView` keeps RichSwift rendering;
  Edit flips the same pane to `SyntaxTextView` source (with a Markdown
  highlighter) and back. Not WYSIWYG — "you're on SSH, good enough".
- Every item: gallery spot in the same commit (Maintenance Rules), headless
  tests, CSS slots for any new colour, `Docs/ControlsUML.md` updated.

Dependencies: 16.11 Wizard and 16.19 Sidebar build on 16.1 Navigator;
16.20 ImageViewer follows ImageView; 16.7 HelpLink is Link with a glyph;
16.12 Gauge shares threshold colouring with the LevelIndicator upgrade.

### Wave A — small, in-package (one sitting each; closes most of the 🟡 column) ✅ complete 2026-08-21

| # | Item | Status | Notes |
|---|------|--------|-------|
| 16.1 | `Navigator` | ✅ Done (2026-08-21) | Push/pop stack of views, title per level, header row `◂ Back  Title`, Esc/Backspace pops, `push(_:title:)`/`pop()`/`popToRoot()`, `onDepthChanged`. The piece phone-width terminals, drill-down settings and wizards all need. |
| 16.2 | `SearchField` | ✅ Done (2026-08-21) | `TextField` subclass: `⌕` glyph, Esc clears (and reports), `onSearch` live as you type + `onCommit` on Return; `debounce` via the App timer (default 0 = live). Absorbs 11.1. |
| 16.3 | `RangeSlider` + `Slider` ticks | ✅ Done (2026-08-21; horizontal only — `Slider` keeps the vertical case) | Two thumbs, `minimumGap`, Tab moves between thumbs, `lowerValue`/`upperValue` bindings. `Slider` gains `tickMarks: Int` (drawn as `┼` on the track) and `snapsToTicks`. |
| 16.4 | `ViewThatFits` | ✅ Done (2026-08-21) | Container that lays out the first child whose intrinsic size fits the bounds (axis: `.horizontal`/`.vertical`/`.both`); re-picks on resize. 80 vs 250 columns makes this more useful than on desktop. |
| 16.5 | `PageView` | ✅ Done (2026-08-21) | `ZStack` + `●○○` dots + `◂ ▸` arrows, ←/→ keys, `onPageChanged`. |
| 16.6 | `Accordion` | ✅ Done (2026-08-21) | Coordinates existing `DisclosureGroup`s: `.exclusive` (one open) or `.shared` (open ones split the space). No new section control. |
| 16.7 | `Link` + `HelpLink` | ✅ Done (2026-08-21; HelpLink = `Link.help(anchor:baseURL:)`; OSC 8 deferred — needs a cell-level URL attribute) | Underlined label emitting OSC 8 hyperlinks on terminals that render them; Enter/click calls `onOpen(url)` or, when nil, opens via `open`/`xdg-open`. `HelpLink` = `Link` with a `?` glyph and an anchor. |
| 16.8 | `StatusBar` flash + priority | ✅ Done (2026-08-21) | `flash(_ text:, for:)` timed message that temporarily replaces the lowest-priority segments; `StatusBarSegment.priority` decides truncation order when narrow. Finishes the existing control. |
| 16.9 | `Canvas` | ✅ Done (2026-08-21; the first "VTG graphics required" placeholder) | `Canvas { painter, chrome in … }` — draw closure, no subclassing. Cell form: if the app gives `cellDraw` it runs; otherwise the framed "VTG graphics required" placeholder. VTG form: the chrome closure draws. First user of the placeholder pattern. |
| 16.10 | `PasteButton` | ✅ Done (2026-08-21) | `Button` that reads `Pasteboard` on activate and hands the text to `onPaste`; disabled look when empty. |

### Wave B — medium ✅ complete 2026-08-21

| # | Item | Status | Notes |
|---|------|--------|-------|
| 16.11 | `Wizard` | ✅ Done (2026-08-21) | Steps with titles on a `Navigator`; `Back`/`Next`/`Finish` footer; per-step `validate() -> String?` blocks Next with the message in the footer; `next(from:) -> StepID` for branching; progress `Step 2 of 5`. In-package (ActiveUI's is a sibling; here it is small once Navigator exists). |
| 16.12 | `Gauge` + `LevelIndicator` thresholds | ✅ Done (2026-08-21) | Styles `.bar` (cells + VTG), `.ring`/`.dial` (VTG via sectors; cells fall back to `.bar` with the value — no placeholder needed, a bar *is* the honest form). `warningThreshold`/`criticalThreshold` colour bands, shared with `LevelIndicator` (new `warningAccent`-style slots already exist). |
| 16.13 | `Matrix` | ✅ Done (2026-08-21) | Grid of cells as one control: `.radio` (one selected) / `.highlight` (many); arrows move, Space toggles; `onSelectionChanged`. Keyboard navigation is the work. |
| 16.14 | `Toolbox` | ✅ Done (2026-08-21; its own control, not a Toolbar mode) | Exclusive tool palette docked to an edge: `ToolbarItem`s in `.radio` mode, vertical or horizontal, icon+caption. Built on `Toolbar`. |
| 16.15 | `TokenField` | ✅ Done (2026-08-21; no ←/→ token walking yet) | Return mints a token from typed text, Backspace on an empty tail removes the last, ←/→ walk tokens, `onTokensChanged`; optional `completions` from 16.16. Absorbs 11.4. |
| 16.16 | `CompletionList` (public) | ✅ Done (2026-08-21; attaches to any TextField, field keeps focus; editor attach later) | Promote the internal `PopUpList`: attach to any `TextField`/`TextView`/`SyntaxTextView`, items + filter, ↑/↓/Return/Esc; the code editor's completion UI lands on it. |
| 16.17 | `FlowStack` | ✅ Done (2026-08-21) | Wrapping stack (the missing `AUIStack` mode): rows fill then wrap, `spacing`/`lineSpacing`, alignment. Tag clouds, button rows that reflow. |
| 16.18 | `Form` sections | ✅ Done (2026-08-21; `Section` in the `FormBuilder` DSL) | `Section("Title") { … }` in `FormBuilder` and `form.addSection(_:)`; header row styled on the header slot; label column still shared across sections. |
| 16.19 | `MasterDetail` | ✅ Done (2026-08-21; `MasterDetail` + `SidebarList`, tiles or pushes by width. Renamed from `Sidebar` per Bobby: the TUIKit sidebar IS `SlideOut`, the full-height panel that slides out of a window edge) | One-call assembly over `SplitView` + `ListView`/`TreeView` + detail; `adaptive` below a width threshold pushes the detail on a `Navigator` instead of tiling. Rows gain icon + title + subtitle (`SidebarList` row style). |
| 16.20 | `ImageView` + `ImageViewer` | ✅ Done (2026-08-21; card + menu in cells, pixels under VTG) | **Placeholder + menu.** Cells: framed card `🖼 logo.png · 640×480 · PNG` with context menu Open in Viewer / Copy / Paste (paste replaces the image from the pasteboard path or data). VTG: `chrome.image` fitted/filled/centred, tint ignored. `ImageViewer` = `FloatingWindow` hosting an `ImageView` with zoom/pan (VTG) or the card (cells). Absorbs 11.3. |
| 16.21 | `Scroller` (public) | ✅ Done (2026-08-21) | The border scrollbar as a standalone control driving any `ScrollSpan`; `onScroll`. |
| 16.22 | `Preferences` | ✅ Done (2026-08-21; UserDefaults / JSON file / ephemeral; `TUIFavorites` move left for later) | Thin typed store over `UserDefaults` (Apple) / a JSON file in `XDG_CONFIG_HOME` (Linux); `@Bound`-compatible so forms bind straight to it. `TUIFavorites` moves onto it. |
| 16.23 | `CollectionView` | ✅ Done (2026-08-21; no recycling) | Selection model, sections with headers, arrow navigation and `onActivate` over a `GridView` in a `ScrollView`; item views supplied by a closure. No recycling until a demo needs it. |
| 16.24 | `MarkdownView` edit mode | ✅ Done (2026-08-21; `isEditing` flips to a `SyntaxTextView` with `MarkdownHighlighter`) | `isEditing` flips the pane between RichSwift rendering and a `SyntaxTextView` with a new `MarkdownHighlighter` (headings, emphasis, code, links); `onSourceChanged`; toolbar/accelerator to toggle. Not WYSIWYG by decision. |
| 16.25 | `Document` model | ✅ Done (2026-08-21; `DocumentController`) |
| 16.29 | `PreferencesDialog` | ✅ Done (2026-08-21, added per Bobby: a dialog presenting preference pages — a `Toolbox` strip across the top (`.toolbar`) or a `SidebarList` beside them (`.split`); bind the pages to a `Preferences` store) | `DocumentController`: open/save/save-as via `FileDialog`, dirty tracking, recents, window title `•` marker, close-confirm `Dialog`. OmegaCLIDE and the browser both reinvent this today. |

### Wave C — sibling packages (own repos under `UILess/Code`, consume TUIKit by path like `TUIWebBrowser`)

| # | Item | Status | Notes |
|---|------|--------|-------|
| 16.26 | **`TUITerminal`** | ⏳ Pending — first | A terminal emulator as a TUIKit view, for OmegaCLIDE's build/run and shell panes. Engine decision like 15/E0: Bobby already owns a Swift emulator core — `SwiftTerm` in `~/AIResearch/GraphicalTerminal/Code/SwiftTerm` (`HeadlessTerminal.swift`, parser, buffers, `LocalProcess` pty) — so **depend on or port its headless core** (no AppKit), render its buffer into cells, forward TUIKit key/mouse input as bytes, resize → `TIOCSWINSZ`, scrollback, OSC 52 passthrough, `onProcessExited`. **Nested VTG is planned, not out of scope** — Bobby is adding a nested mode to the VTG protocol; the TUIKit-side proposal is `Docs/VTGNestedMode.md` (context object `nest`/`nestMove`/`nestDelete`, wrapped commands `nested,id=P;…`, wrapped replies). Host prerequisites, buildable against a fake before the terminal lands: `ChromeCommand.Shape.nested` + `ChromeSurface.nested`, driver surfaces `nested,…` replies as a `TerminalInput` event (today every APC is swallowed), glyph metrics/capabilities exposed to views. Fallback if the protocol lags: parse the child's VTG with SwiftTerm's `VectorTerminalGraphicsParser` and redraw it as `ChromeCommand`s (child layers collapse, no child scroll/alpha/viewport). |
| 16.27 | `TUIDiagram` | ⏳ Later | Nodes + edges; VTG polylines/rounded rects draw it, cells use box-drawing and `─►`; layout (layered/force) is the project. Mirrors `ActiveUIDiagram`. |
| 16.28 | `TUIBoards` | ⏳ Later | Kanban over `SplitView` columns + `ListView` cards + the existing drag machinery; limits, collapse. Mirrors `ActiveUIBoards`. |

**Out of scope** (➖ in the parity doc): StatusItem, VisualEffectView,
ShareLink, GradientRing, controlSize, Drawn controls (TUIKit's default
condition), ScrollView magnification, NSToolbar user customization, an
animated anything.

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
- **Border weight (Bobby, 2026-08-21): double lines mean TOP LEVEL — the
  frames of windows whose parent is the desktop. Every border nested
  inside a window — group boxes, placeholders, calendars, tick marks —
  draws single, and so do dialogs (a dialog belongs to a window; only the
  rare dialog that belongs to none sets `.double` itself).**
  `BorderStyle.inner` is the mapping; `Panel` applies it automatically
  unless it is a window's frame; Turbo's `modalWindows` context is single.
- **Every new control gets a gallery spot, in the same commit.**
  `swift run TUIKitGallery` (Demo/TUIKitGallery) is the control showroom:
  folder tabs group the controls, the Theme menu proves them under every
  theme, and anything with a VTG rendering shows its VTG and ANSI forms
  side by side (via `suppressesVectorChrome`), the way the Charts tab
  does. A control that isn't in the gallery is invisible to the person
  deciding whether it already exists.
