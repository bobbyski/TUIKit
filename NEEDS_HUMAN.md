# NEEDS_HUMAN — Review Checklist (TUIKit)

Per `Documents/AICoding rules.md`: files over 500 code lines and overly
complicated functions are logged here for human review, with an alert to
Bobby whenever an entry is added.

## Open Entries

### Right-edge band that widens when a window moves one column — UNRESOLVED
- VTG-only visual defect seen in OmegaCLIDE. Five reproduction attempts failed
  because `HeadlessDriver` reports `supportsGraphicsChrome == false`, so
  `Desktop.draw`'s chrome branch — the only code that paints beside a window —
  is never exercised by any test. That blind spot is the real problem.
- Full investigation, ruled-out list, and ranked next steps: **`RESIZE_ERROR.md`**.
- Prime suspect: `ChromeSceneReconciler.plan` returns `.update` with NO
  deletions, so a retained shape that MOVES is redrawn without its old
  geometry being deleted. Hinges on VectorTerminalSDK's `canvas.rect(id:)`
  semantics (replace vs append) — one question decides it.
- Fixed in passing (a real defect, NOT confirmed as the cure): window shadows
  were keyed by subview index, which is not stable identity across
  activate / close / maximize. Now keyed by window identity.
- [ ] Reviewed by human
- [ ] Human accepted

### `Package.swift` — platform floor raised macOS 15 → 16 (Phase 10)
- Added: 2026-07-11 — **Bobby: this changes who can build TUIKit.**
  `VectorTerminalSDK` (the Phase 10 VTG chrome dependency) declares
  `.macOS("16.0")`, and SwiftPM refuses a lower-floor dependent, so TUIKit's
  minimum moved from 15 to 16 to take the dependency at all.
- Suggested remedy: confirm macOS 16 is acceptable for TUIKit 1.x, or lower
  VectorTerminalSDK's platform requirement upstream (it's in-house, so
  cheap to check whether it truly needs 16).
- [ ] Reviewed by human
- [ ] Human accepted (as-is or with the noted remedy)

### Phase 10 exit criterion — needs a run inside a real VectorTerminal
- Added: 2026-07-11 — All VTG chrome behavior is headless-proven
  (`VTGChromeTests`, 12 green), but nothing has drawn on an actual
  VectorTerminal yet. Please run `swift run TUIKitDemo --interactive`
  inside VectorTerminal, pick **Ambiance** from the Theme menu, and
  eyeball: gradient titlebar with rounded top corners, orange close circle
  at the LEFT (click it), rounded gradient buttons with an orange focus
  glow, aubergine gradient desktop, window shadows. Then the same in
  Terminal.app to confirm the plain-cell fallback (that equivalence is
  10.8, the phase exit criterion). `TUIKIT_VTG=0` is the escape hatch if
  the probe misbehaves; plain terminals that never answer APC queries pay
  the probe timeout (~400 ms) once at startup — worth feeling in
  Terminal.app to decide whether the budget should shrink.
- [ ] Reviewed by human
- [ ] Human accepted (as-is or with the noted remedy)

### `Demo/TUIKitDemo/Traditional/ManualExample.swift` — 626 lines (~527-line factory)
- Added: 2026-07-04 — `makeManualExample(index:)` is the demo's kitchen-sink
  *manual* window: it wires every Phase 6 control by hand across several tabs,
  so it is intentionally one large factory. Splitting `main.swift` gave each
  demo window its own file (`Declarative/` + `Traditional/`); this one window
  is simply big.
- Suggested remedy: if it keeps growing, break the tabs into helper methods
  (`manualControlsTab()`, `manualDataTab()`, `manualDocsTab()`) in the same
  file, or per-tab files — but keep the "one window, discoverable in one place"
  property that makes it useful as a tutorial.
- [ ] Reviewed by human
- [ ] Human accepted (as-is or with the noted remedy)

### `Sources/TUIKit/Controls/SyntaxTextView.swift` — 653 CODE lines after Editor v2 (comments excluded)
- Added: 2026-07-04 — Phase 6C moved the document engine OUT (to
  `TextEditBuffer`, ~470 lines, pure and unit-tested) but added selection
  overlays, clipboard chords, and the find surface, so the view is over the
  500-line threshold again. Its remaining responsibilities are input
  translation, painting, viewport/scrollbars, and the find state.
- Suggested remedy: the scrollbar geometry + drawing (~150 lines, shared
  shape with `ScrollView`) is the natural next extraction — a reusable
  `ScrollbarGeometry` helper would also de-duplicate `ScrollView`; the find
  state could become a small `FindSession` type if it grows options.
- [ ] Reviewed by human
- [ ] Human accepted (as-is or with the noted remedy)

<!-- Entry template:
### <path> — <reason>
- Added: <date> — <why this needs human eyes>
- Suggested remedy: <split proposal / simplification>
- [ ] Reviewed by human
- [ ] Human accepted (as-is or with the noted remedy)
-->

## Watchlist (below threshold, worth awareness)

### `Sources/TUIKit/Terminal/ANSIInputDecoder.swift` — 221 code lines
- Escape-sequence decoding is where terminal libraries traditionally rot
  into giant switch statements. Landed at 221 code lines as a state machine
  with per-state consumers; if terminal-quirk support pushes it past 300,
  split the sequence tables (tilde keys, SS3 map) from the decode loop.
