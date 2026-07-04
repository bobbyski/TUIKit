# NEEDS_HUMAN — Review Checklist (TUIKit)

Per `Documents/AICoding rules.md`: files over 500 code lines and overly
complicated functions are logged here for human review, with an alert to
Bobby whenever an entry is added.

## Open Entries

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
