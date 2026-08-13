# TUICodeEditor — Build Plan

A new source-code editor for TUIKit, on par with
[SwiftyCodeEditor](../../../../../AIResearch/SwiftyTextEditor/Code/SwiftyCodeEditor)'s
core text editor. SwiftyCodeEditor's own architecture doc promises that
"platform adapters should be free to create a polished Mac feel, **terminal
feel**, Windows feel, or Linux feel while sharing the same editor model" —
this plan is that terminal feel, built for real.

Scope per Bobby: **the core text editor only** — not FreebirdStudio's agent
panes, project browsing, or build UI. Concessions for a CLI editor are
allowed where a terminal genuinely cannot match AppKit; each one is recorded
in the Concessions table, not silently dropped.

The two headline gaps (Bobby, 2026-08-10): **syntax coloring** and **the
gutter**. Both get their own phases and drive the architecture.

## Dashboard

```
Overall Progress  ███████████████████████░░░░░░░░░  73%   (39 / 53 items)

Layers:  CodeEditorCore (new package, no UI)  →  TUICodeEditor (TUIKit product)
         SwiftyCodeEditor untouched; may adopt the core later, or never.

Built 2026-08-10: 21 files, 79 new tests (56 core + 23 view), all green.
OmegaCLIDE now edits through it — 133 IDE tests pass unmodified.
REMAINING: E5 tag-sync + bracket highlight, E7 diff/merge views (optional),
E9 damage tracking.

E0 · Model-source decision      ██████████ 100%  ✅ Decided: Option B (port), 2026-08-10
E1 · Document & command core    ██████████ 100%  🔄 Code complete (48 core tests)
E2 · Tokenization engine        ██████████ 100%  🔄 Code complete — multi-line comments/strings work
E3 · CodeEditorView             ██████████ 100%  🔄 Code complete, folding-aware
E4 · The gutter                 ██████████ 100%  🔄 Bands: breakpoints/ribbon/diagnostics/fold/numbers
E5 · Editing behaviors          ████████░░  80%  🔄 Indent, pairs, word-wise, tab-indent; tag sync + bracket highlight left
E6 · Code folding               ██████████ 100%  🔄 Code complete — token-driven detection, fold map, band, render-through
E7 · Diff & merge surfaces      ░░░░░░░░░░  0%  ⏳ Pending (parity tail; optional for OmegaCLIDE 1.0)
E8 · OmegaCLIDE adoption        ██████████ 100%  🔄 Swapped in; git ribbon + build diagnostics wired
E9 · Performance & large files  ██████░░░░  60%  🔄 Gates in place (10k lines, keystroke ≤3 lines); damage tracking left
```

## Why a new editor rather than growing SyntaxTextView

`SyntaxTextView` (996 lines) earned its keep: selection, clipboard, undo,
in-buffer find/replace, embedded border scrollbars, mouse support. Two of its
foundations, however, are the wrong shape for parity, and both are
load-bearing:

1. **Per-line stateless highlighting.** RichSwift colors each line in
   isolation, with a per-line cache keyed on the line's text. A `/* block
   comment */` spanning lines, a Swift `"""` string, a Python docstring — all
   are impossible by construction, because line N's color depends on state
   entering line N. Fixing this means a stateful tokenizer with per-line
   entry states and cache invalidation from the edit point forward — a
   different engine, not a patch.

2. **A single-purpose gutter.** The gutter is line numbers baked into
   `draw()`. Parity needs stacked, independently-toggleable bands — numbers,
   git change ribbon, diagnostics, fold controls, and (Phase 9B of the IDE)
   breakpoints — each with its own click behavior. That is a pluggable
   sub-layout, not a wider number column.

The new editor is a separate control so the migration is a swap, not a
rewrite-in-place: `SyntaxTextView` keeps working (output panes, diffs-as-text,
any third-party user) until E8 retires it from the editor role.

## Layering — the non-UI half is its own library

Bobby, 2026-08-10: *"Write the non UI part in a library that we can maybe port
back to the gui editor to limit drift"* — and *"I just don't want to force a
split on the GUI editor yet."* Both halves of that shape the design:

```text
   CodeEditorCore          ← NEW standalone package. Foundation only.
   (no UI of any kind)       Document, commands, undo, tokenizer, folding,
        │                    diff/merge, diagnostics, behaviors, snapshots.
        ├──────────────┐
        ▼              ▼
   TUICodeEditor    (SwiftyCodeEditor — UNCHANGED, may adopt later, or never)
   cells, gutter,
   keys, mouse
```

- **`CodeEditorCore`** — a new package at
  `UILess/Code/CodeEditorCore`, its own git repo, sibling to `TUIKit` and
  `UILessFramework` (the established layout here). Foundation only: no
  AppKit, no SwiftUI, no TUIKit. Everything that can be decided without
  knowing what a pixel or a cell is lives here, which is most of the editor.
- **`TUICodeEditor`** — a second product in the TUIKit package, depending on
  `TUIKit` + `CodeEditorCore`. Cells, the banded gutter, key routing, mouse,
  scrollbars. Grammars and diff engines stay out of the base `TUIKit` library
  that a form-and-menus app links.
- **`SwiftyCodeEditor` — untouched.** No split forced on it, now or as a
  scheduled phase. The library is merely *shaped* so that adopting it later is
  a delete-and-import rather than a rewrite; whether that ever happens is
  Bobby's call, not this plan's.

**Honest about drift:** a shared library only removes duplication once
*something* adopts it. Until SwiftyCodeEditor does — if it ever does — there
are still two copies, and the E0 provenance headers plus the periodic refresh
sweep remain the mechanism that keeps them honest. What the library buys today
is that the second copy is a clean, importable artifact instead of code fused
to a terminal view.

### Keeping the door open (design constraints, not obligations)

Cheap to honor now, and the whole reason adoption could ever be a delete:

| Constraint | Why |
|---|---|
| Same type names and semantics as SwiftyCodeEditor's `Core/` + `Syntax/` (`TextDocument`, `EditorCommand`, `SyntaxToken`, `TwoWayTextDiff`, `EditorBehaviorPreferences`, …) | Adoption becomes deleting two directories and adding an import; call sites do not move. |
| No terminal concepts in the API — no `CellStyle`, no `TerminalCell`, no `Point` | The core emits **scopes** and neutral colors; each UI maps them to `CellStyle` or `NSAttributedString` attributes. |
| `EditorRenderSnapshot` is the rendering contract | Already SwiftyCodeEditor's own boundary; both UIs draw from the same shape. |
| Everything `Sendable`, pure, testable headlessly | Tokenizing off the main thread is a stated upstream goal; free if the core never touches UI. |
| Platform floor no higher than SwiftyCodeEditor's, and Linux-clean | The GUI editor could adopt without an OS bump; TUIKit's Linux target stays reachable. |
| CI guard: a source scan failing the build on `import AppKit/SwiftUI/TUIKit` | Same trick as OmegaCLIDE's `#if os(...)` quarantine test — the boundary is enforced, not just documented. |

## E0 — The one decision that shapes everything ✅ DECIDED

Where does the platform-neutral model come from?

| | Option A — depend on SwiftyCodeEditor | Option B — port the core into TUIKit |
|---|---|---|
| Mechanics | `TUICodeEditor` adds a package dependency on SwiftyCodeEditor; its `Core/` + `Syntax/` layers (verified Foundation-only, no AppKit imports) become the model. Local path while co-evolving, tags later — the exact pattern OmegaCLIDE already uses for TUIKit. | Re-implement `TextDocument`, `EditorCommand`, `SyntaxToken`, `TwoWayTextDiff`, `EditorLineChangesBuilder`, `FoldRegionDetector` inside `TUICodeEditor`, same names and semantics. |
| For | Parity **by construction** — one model backs the Mac editor and the terminal editor; folding/diff/ribbon fixes land once and both IDEs get them. Dogfoods SwiftyCodeEditor's adapter architecture exactly as its docs intend. Its pure-logic tests come along free. | TUIKit stays fully self-contained for third-party consumers; no version coupling between two pre-1.0 packages. |
| Against | TUIKit (published, pre-release) gains a dependency on a 30%-complete private package; SwiftyCodeEditor's macOS-15 `platforms:` needs widening for TUIKit's Linux ambitions (trivial — core is Foundation-only — but it's a change in *that* repo). | Two copies of the same non-trivial logic (diff classification, fold detection, tokenizer state) that **will** drift; every future editor feature is built twice. |

**Decision: Option B — port** (Bobby, 2026-08-10). Rationale: *"a CLI tool
dependent on a GUI tool just seems wrong"* — TUIKit stays self-contained for
its consumers, whatever the duplication cost. The recommendation had been A
for drift reasons; B was chosen with eyes open, so the drift risk is managed
explicitly instead of avoided:

**The provenance rule (mandatory for every ported file).** Each file whose
logic originates in SwiftyCodeEditor carries a header comment naming exactly
what was copied, from where, at which upstream commit, and how it has since
deliberately diverged — so a periodic refresh sweep is a `diff` against
upstream plus a re-port of wanted deltas, not archaeology:

```swift
// PORTED from SwiftyCodeEditor — refresh periodically against upstream.
//   source:   Sources/SwiftyCodeEditor/Core/TextDocument.swift
//   repo:     AIResearch/SwiftyTextEditor  @ 5bbc08c (2026-08-10)
//   diverges: CaretMovement adds wordLeft/wordRight/pageUp/pageDown
//             (terminal navigation; consider upstreaming)
```

Baseline for the initial port: **`5bbc08c`** ("DebuggerCore: a debugger with
no user interface in it"). A refresh sweep is E-phase-neutral maintenance:
run `git log 5bbc08c..HEAD -- Sources/SwiftyCodeEditor/{Core,Syntax}` in the
upstream repo, re-port what matters, and bump every touched header's commit.
Upstream fixes to ported logic should be OFFERED back to SwiftyCodeEditor
when they are not terminal-specific — divergence comments mark the
candidates.

**Refinement (same day): B, structured as a shared library.** Rather than
porting into `TUICodeEditor` directly, the ported logic lands in a standalone
`CodeEditorCore` package (see Layering, above). This keeps the CLI free of any
GUI dependency — the point of choosing B — while leaving the *option* of the
GUI editor adopting it later to collapse the duplication for good. No change
is required of SwiftyCodeEditor for this plan to proceed.

- [x] Bobby decided: **B**, ported into a standalone `CodeEditorCore` library

## Parity matrix

What "on par" means, feature by feature. ✔ = has it today.

| Capability | SwiftyCodeEditor | SyntaxTextView | Plan |
|---|---|---|---|
| Platform-neutral document + semantic commands | ✔ | — (raw keyDown) | E1 |
| Undo/redo | — (planned) | ✔ | E1 (as command journal on the new core) |
| Selection, clipboard, mouse (incl. double/triple click) | ✔ | ✔ | E3 |
| Find/replace in buffer | — (planned) | ✔ | E3 |
| **Stateful multi-line tokenization** (block comments, `"""` strings) | ✔ (protocol allows; native highlighters line-based) | ✗ | **E2 — must beat both** |
| **Grammar catalog** (Swift, SWFX, JSON, asm, XML/plist, C-family, ObjC…) | ✔ | RichSwift's fixed set | E2 |
| Monaco/Monarch converted grammars | ✔ (regex subset + JS host boundary) | ✗ | E2 (regex subset; JS host is a non-goal) |
| Scope-based theming (`keyword.control` → style) | ✔ | ✗ (RichSwift decides) | E2 |
| **Git change ribbon in gutter** (added/modified/deletedAbove) | ✔ | ✗ | E4 |
| **Diagnostics in gutter** (severity glyphs + line styling) | ✔ | ✗ | E4 |
| Line annotations / annotation bands | ✔ | ✗ | E4 |
| Breakpoint band | — | ✗ | E4 (API now; IDE Phase 9B consumes) |
| Auto-close pairs, expand-on-Return, closing-tag sync | ✔ | ✗ | E5 |
| Tab/Shift-Tab indents selection; configurable indent unit | ✔ | ✗ | E5 |
| Auto-indent on newline | ✔ | ✗ | E5 |
| Word-wise caret movement/selection | ✔ | ✗ | E5 |
| Bracket-pair matching highlight | ✔ | ✗ | E5 |
| Current-line highlight | ✔ | ✗ | E5 |
| Behavior preferences (Codable, per-project) | ✔ | ✗ | E5 |
| Code folding (brace + tag detection, fold UI) | ✔ (detector) | ✗ | E6 |
| Two-way diff view w/ context elision | ✔ | ✗ | E7 |
| Three-way merge w/ hunk resolution + banner | ✔ | ✗ | E7 |
| Changeset selector | ✔ | ✗ | E7 |
| Border-embedded scrollbars (Borland look) | n/a | ✔ | E3 (BorderScrollable conformance) |
| Minimap | — (planned) | ✗ | Concession (below) |
| Completion/hover providers | — (planned) | ✗ | Non-goal here — IDE Phase 9 (LSP) owns it; E4 reserves the popup anchor API |

## CLI concessions

Honest limits of a character grid, decided up front:

| AppKit affordance | Terminal answer |
|---|---|
| Proportional fonts, font weights per scope | Cell styles only: color, bold, underline, dim, inverse. Scope map targets those. |
| Minimap | Skipped. A braille-dot minimap is a fun Phase-later novelty, not parity-critical. |
| Pixel-smooth scrolling, rubber-banding | Line-quantized scrolling (already the norm here). |
| Hover tooltips on mouse-rest | Popup panel on an explicit key (the TUIKit popup machinery), not on hover timing. |
| Squiggly underlines for diagnostics | Underline + severity color on the offending range; glyph in the gutter carries the severity. |
| Click targets smaller than one cell | Every interactive element (fold toggle, ribbon mark, breakpoint dot) is a full cell. |

## Phases

Which layer each phase builds in — the core is deliberately the larger share,
because that is what makes it worth having:

| Phase | `CodeEditorCore` | `TUICodeEditor` |
|---|---|---|
| E1 Document & commands | document, positions, commands, undo journal, revisions | — |
| E2 Tokenization | protocol, grammars, state machine, cache, scope→neutral-color theme | scope→`CellStyle` mapping |
| E3 Editor view | find/replace engine, render snapshots | the view, caret, selection, mouse, scrollbars |
| E4 Gutter | change-ribbon + diagnostics models, band *data* | band layout, glyphs, click routing |
| E5 Behaviors | every behavior as pure text→`EditorTextOperation` | key bindings that invoke them |
| E6 Folding | detector, fold map | fold band UI, render-through |
| E7 Diff & merge | diff/merge engines, hunk resolution | diff/merge views |
| E8 OmegaCLIDE adoption | — | the swap |
| E9 Performance | cache/damage algorithms | render damage |


### E1 — Document & command core (`CodeEditorCore`)

| # | Item | Notes |
|---|---|---|
| E1.0 | Package scaffold | New repo `UILess/Code/CodeEditorCore`, Foundation-only, `swiftLanguageModes: [.v6]`, platform floor matching SwiftyCodeEditor's so it stays adoptable. CI source-scan test failing on `import AppKit`/`SwiftUI`/`TUIKit`. |
| E1.1 | Model port | Port `TextDocument`, `TextPosition`/`TextSelection`, `EditorCommand`/`CaretMovement`, `EditorTextOperation` — same names and semantics, provenance headers per the E0 rule. Local additions: `wordLeft`/`wordRight`/`pageUp`/`pageDown` on `CaretMovement`, recorded as divergences (upstreaming candidates). Port the matching upstream tests alongside. |
| E1.2 | Command journal undo | Undo/redo as inverse-operation journal over `EditorTextOperation`, replacing SyntaxTextView's snapshot undo; coalescing rule: consecutive single-character inserts on one line collapse into one undo step. |
| E1.3 | Revision counter | Monotonic document revision, the key every cache below (tokens, folds, ribbon) invalidates against. |
| E1.4 | Tests | Command round-trips (each command's undo restores text AND selection); journal coalescing; position arithmetic at line boundaries and EOF. Pure logic, no view. |

### E2 — Tokenization engine (headline gap #1)

The design center: **line tokens with carried state**.

```text
state[0] ──▶ tokenize(line 0) ──▶ tokens[0], state[1]
state[1] ──▶ tokenize(line 1) ──▶ tokens[1], state[2]   ← a /* opened above
...            edit at line k: states ≥ k+1 stale; retokenize forward
               until an emitted state equals the cached one, then stop.
```

| # | Item | Notes |
|---|---|---|
| E2.1 | `StatefulHighlighting` protocol | `tokenize(line:entering: State) -> (tokens: [SyntaxToken], exiting: State)`; `State: Equatable` so retokenization can stop at the first fixed point. Wraps SwiftyCodeEditor's line-based `SyntaxHighlighting` for grammars that carry no state. |
| E2.2 | Native stateful grammars | Swift (block comments, `"""`, `#if` regions), Python (docstrings), JS/TS (template literals, JSX left out), C-family. These are the languages OmegaCLIDE ships; each is a hand-written tokenizer with golden-file tests, not regex soup. |
| E2.3 | Catalog + Monarch subset | Adopt `SyntaxHighlighterCatalog` + `RegexSyntaxHighlighter` for the long tail (JSON, XML/plist, asm, SWFX, Markdown). The Monaco **JS host bridge is a non-goal** — converted-grammar JSON only. |
| E2.4 | Scope → theme mapping | `EditorTheme`: ordered longest-prefix map from token scope (`comment.block.documentation`) to `CellStyle`, resolved through the TUIKit `Theme` so Modern Turbo / Borland / Ambiance each ship an editor palette. Unknown scopes fall back up the dot-path — Monaco's own rule. |
| E2.5 | Token cache | Per-line `(revision, entryState) → tokens`; edit invalidates from the edited line to the state fixed point. Perf gate: single-character edit in a 5,000-line file retokenizes < 50 lines typical. |
| E2.6 | Tests | Golden tokens per language incl. the multi-line cases RichSwift cannot do; fixed-point early stop (edit inside a comment retokenizes 1 line; opening `/*` at line 0 retokenizes to EOF); scope fallback chain. |

### E3 — CodeEditorView

| # | Item | Notes |
|---|---|---|
| E3.1 | Viewport snapshot rendering | Adopt the `EditorRenderSnapshot` idea: view asks core for visible lines' tokens+styles, draws cells. Renders **through the fold map** (E6) from day one so folding isn't a retrofit. |
| E3.2 | Caret, selection, current line | Selection paints inverse; current-line background from theme; cursor via terminal cursor positioning (not a drawn cell) so it blinks natively. |
| E3.3 | Feature parity port | Clipboard (Pasteboard + OSC 52), find/replace (moves to core so it's testable without a view), mouse incl. double-word/triple-line, wheel, `BorderScrollable` for the Borland border bars. Every ported behavior keeps its existing test, retargeted. |
| E3.4 | `onChanged`-compatible surface | The adapter API OmegaCLIDE's `EditorPane` consumes today (`text`, `setText`, `language`, `isEditable`, `scrollTo`, `cursorPosition`, scroll offsets) — so E8 is a swap, not a rework. |
| E3.5 | Tests | Headless render snapshots: tokens→cells, selection inverse, viewport clipping, embedded-bar geometry (one column, last column — the invariant from the 2026-08-10 session, pinned here too). |

### E4 — The gutter (headline gap #2)

```text
 bp ribbon fold num │ code
 ●  ▌      ▾   12 │ func draw() {
    ▌          13 │     …
 ⚠             14 │ }
```

| # | Item | Notes |
|---|---|---|
| E4.1 | Band architecture | `GutterBand` protocol: fixed width, `cells(for line:) -> [TerminalCell]`, `onClick(line:)`. Editor stacks enabled bands; width is the sum. Bands toggle per `EditorBehaviorPreferences`. |
| E4.2 | Line-number band | Right-aligned, dim; width tracks line count; relative-number option deferred. |
| E4.3 | Change-ribbon band | `EditorLineChangesBuilder` (added ▌green / modified ▌yellow / deletedAbove ▔red) against a `comparisonText` baseline the host supplies. Pure classification already unit-tested upstream — the band only paints the map. |
| E4.4 | Diagnostics band | Severity glyph per line (✖ error, ⚠ warning, ● info; worst wins), plus range underline in the text; `diagnosticsAreStale` dims the band rather than hiding it (SwiftyCodeEditor's semantic, kept). Click → `onSelectDiagnostic(line)`. |
| E4.5 | Breakpoint band | Present/absent dot, click toggles, pure callback surface — no debugger knowledge here. Exists NOW so IDE Phase 9B doesn't need an upstream round-trip later. |
| E4.6 | Fold band | ▸ collapsed / ▾ foldable / blank; click toggles (consumes E6's model). |
| E4.7 | Tests | Band stacking widths; per-band click routing (click column decides which band fires); ribbon/diagnostic cell snapshots; worst-severity-wins. |

### E5 — Editing behaviors

All governed by `EditorBehaviorPreferences` (adopted as-is: Codable, defaults
on, IDE stores it per project in `.omegaIDE/`).

| # | Item | Notes |
|---|---|---|
| E5.1 | Auto-indent on Return | Copy leading whitespace; language hook adds a level after `{`/`:`. |
| E5.2 | Pair closing + expand-on-Return | `(`→`()`, skip-over on typing the close, `{` + Return → indented line between braces. Off when a selection exists — typing `(` around a selection wraps it instead. |
| E5.3 | Tab indents selection | Tab/Shift-Tab shift selected lines by the indent unit; without selection, Tab inserts the unit. |
| E5.4 | Closing-tag sync | Editing `<div` renames the matching `</div` (XML/HTML grammars only). |
| E5.5 | Word-wise movement | Alt+←/→ move, +Shift extends; identifier-character classes shared with double-click word selection. |
| E5.6 | Bracket matching | Caret adjacent to a bracket highlights its partner (scan bounded, via token stream so brackets in strings/comments don't match code brackets). |
| E5.7 | Tests | Behavior matrix per preference flag (each behavior provably OFF when disabled); pair-wrap vs pair-insert; tag sync only in markup. |

### E6 — Code folding

| # | Item | Notes |
|---|---|---|
| E6.1 | Region detection | Adopt `FoldRegionDetector` (braces + markup tags) fed by the token stream so braces inside strings never open regions — an upstream improvement it needs anyway. |
| E6.2 | Fold map | Core-side visible-line ↔ document-line mapping; every view/gutter/scrollbar computation goes through it (laid in E3.1). Folded region renders as first line + ` … ` suffix cell-styled dim. |
| E6.3 | Commands | Fold/unfold at caret, fold-all, unfold-all; caret movement through a fold lands on the fold line, edits inside a folded region auto-unfold it. |
| E6.4 | Tests | Map arithmetic under nested folds; edit-inside-fold unfolds; detector golden files (braces, tags, strings-with-braces). |

### E7 — Diff & merge surfaces (parity tail)

SwiftyCodeEditor's biggest chunk beyond the editor proper (all ported under the E0 provenance rule — `TwoWayTextDiff`, `ThreeWayTextDiff`, `MergeConflictController` carry headers). **Optional for
OmegaCLIDE 1.0** (the IDE reads diffs as text today); required for full
package parity. Ordered last on purpose.

| # | Item | Notes |
|---|---|---|
| E7.1 | Inline two-way diff view | `comparisonText` + working text through `TwoWayTextDiffBuilder`; deleted lines render dim/red interleaved; context elision with `⋯ N unchanged lines ⋯` dividers (the `DiffElisionDividerView` idea, one cell row here). |
| E7.2 | Three-way merge view | Ancestor/ours/theirs via `ThreeWayTextDiff`; per-hunk take-ours/take-theirs/take-both keyed resolution; conflict banner strip; `MergeConflictController` adopted whole. |
| E7.3 | IDE hookup | GIT window's Return-on-conflicted-file opens the merge view instead of a text diff. |
| E7.4 | Tests | Hunk resolution round-trips (every resolution sequence yields a conflict-marker-free result); elision boundaries; scroll-to-hunk. |

### E8 — OmegaCLIDE adoption

| # | Item | Notes |
|---|---|---|
| E8.1 | EditorPane swap | `SyntaxTextView` → `CodeEditorView` behind the E3.4 surface; find bar, Functions menu, session scroll state, dirty tracking unchanged. |
| E8.2 | Ribbon wired to git | Baseline from `git show HEAD:path` via `GitClient` (new `show` method — CLI-only rule holds), refreshed on save and on git panel refresh. |
| E8.3 | Diagnostics wired | Build's `DiagnosticsParser` results flow into the gutter band for open files; strip count unchanged. |
| E8.4 | Retirement | `SyntaxTextView` demoted to plain-text duty (output window), deprecation note in its doc comment; removal decision deferred to TUIKit 1.0. |
| E8.5 | Tests | The existing headless shell suite must pass unmodified after the swap — that suite IS the regression net. Plus: ribbon appears after an edit, diagnostic glyph appears after a failed build. |

### E9 — Performance & large files

| # | Item | Notes |
|---|---|---|
| E9.1 | Targets | 10k-line file: open < 200 ms, keystroke render < 16 ms, edit-retokenize bounded by fixed point not file size. Measured in CI with a generated file, thresholds asserted loosely (2× headroom) so CI noise doesn't flake. |
| E9.2 | Damage tracking | Only lines whose tokens/fold/selection state changed re-render; scrolling redraws only entering lines. |
| E9.3 | Soak | Scripted 10k-edit session under the headless driver; memory plateau asserted (journal trimming, cache bounds). |

## Test strategy

Same regime as everything else here: **every phase headless-provable**, pure
logic separated from cells. Golden token files per grammar; render snapshots
for the view and gutter; the OmegaCLIDE shell suite as the end-to-end net at
E8. No test touches the disk or a real terminal.

## Non-goals

- Monaco **JavaScript** extension host (converted-grammar JSON only).
- Completion, hover, semantic tokens — the IDE's LSP phase supplies those
  *into* this editor's surfaces (popup anchor, diagnostics band); the editor
  does not speak LSP itself.
- Minimap, multiple carets: revisit after E9 as novelty/stretch.
- FreebirdStudio features beyond the editor package (explicitly out, per Bobby).
- **Restructuring SwiftyCodeEditor.** No phase here changes that package. Its
  adoption of `CodeEditorCore` is an option the design keeps cheap, never a
  scheduled dependency of this work.
