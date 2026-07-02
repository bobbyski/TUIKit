# NEEDS_HUMAN — Review Checklist (TUIKit)

Per `Documents/AICoding rules.md`: files over 500 code lines and overly
complicated functions are logged here for human review, with an alert to
Bobby whenever an entry is added.

## Open Entries

*None. Largest file as of 2026-07-01 is well under the threshold.*

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
