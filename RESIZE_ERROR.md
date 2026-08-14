# RESIZE_ERROR — the widening bar at a window's right edge

**Status: NOT FIXED.** One real defect found and fixed along the way (window
shadow identity, below), but it is *not confirmed* to be the cause. Five
attempts, all unable to reproduce. This is a map for whoever picks it up.

Written 2026-08-10 by Claude. Every file below is in this repo (`TUIKit`)
unless marked otherwise.

## The symptom

Bobby, in OmegaCLIDE on a VectorTerminal (graphics layers ON):

> "The screen doubles the width of the scrollbar and loses a column of
> characters."
> "it is now 3 wide" (after maximizing)
> "the bar expands when i drag the right side to within 3 columns from the right"
> "it is not maximize that is doing it, just widening the window"
> **"i moved it one column only"**

A green/cyan band sits at the right edge of the project window. Nudging the
window's right edge by **one column** makes it visibly wider. Repeat, and it
grows again. Two screenshots exist showing 1-column vs ~3-column bands with
the window differing by a single column of width.

## The decisive observation

**A bar cannot get wider when a window moves one column. A GHOST can.**

Every cell-layer bar in this codebase is exactly one column, drawn at
`bounds.size.width - 1`. If the window shifts one column right, the bar moves
one column right. Seeing *two* columns of bar means the old one is still on
screen — stale retained geometry, not a wider bar.

That reframes the whole thing: this is a **VTG retained-scene reconciliation**
problem, not a scrollbar-width problem. Which is why nothing in the cell layer
ever reproduced it.

## Prime suspect (unverified): `.update` redraws without deleting

`Sources/TUIKit/Terminal/ChromeRendering.swift` — `ChromeSceneReconciler.plan`
(line ~88):

```swift
guard previous.map(\.id) == current.map(\.id) else {
    return .rebuild(delete: deletions)     // ids changed → delete all, redraw all
}

let changed = zip(current, previous).compactMap { new, old in
    new == old ? nil : new
}

return .update(draw: changed)              // ← same ids: NO deletions
```

`Sources/TUIKit/Terminal/ANSIDriver.swift` — `presentChrome(_:)` (line 353):

```swift
case .update(let changed):
    deletions = []                         // ← nothing is deleted
    draws = changed
...
for id in deletions { canvas.delete(id: id) }
for command in draws { Self.draw(command, on: canvas, mapper: mapper) }
```

So when a retained shape **moves** — same id, new geometry — the driver draws
the new shape and never deletes the old one.

**Whether that leaves a ghost depends entirely on VectorTerminalSDK's
semantics for `canvas.rect(id:…)`:**

- If drawing with an existing id **replaces** that shape → no ghost, and this
  hypothesis is wrong.
- If it **appends** a new shape → the old geometry stays → ghost → exactly the
  reported symptom.

**This is the first thing to check.** It is a one-line question to the SDK and
it decides everything.

If it appends, the fix is in `plan(...)`: a command whose *geometry* changed
must be deleted before being redrawn, i.e. `.update` needs to carry deletions
for moved shapes (a colour-only change can stay a plain redraw).

## What actually paints there

Only one thing draws *outside* a window's frame at its right edge, and it is
VTG-only — which is why the symptom never appears in a plain terminal or in
any headless test:

`Sources/TUIKit/App/Desktop.swift`:

- `draw(_:)` line 44 — on a VTG terminal with a theme that has
  `vector.desktop`, takes a completely different branch: vector gradient
  backdrop, transparent cells over it, then `drawWindowShadows(chrome)` at
  line 62, then **returns**. The plain-terminal path (`painter.fill`) never
  runs.
- `drawWindowShadows(_:)` line 72 — for each non-fullscreen window, draws a
  retained rect offset **`+0.3` cells right and `+0.18` down**, at the
  window's full size. That is a sliver hugging the right edge and the bottom
  — precisely where the band appears.

Note the shadow is skipped for `window.fillsScreen` and for hidden windows, so
maximizing/closing removes shapes from the scene — another way to leave stale
geometry.

## What I changed (kept, but unconfirmed as the cure)

`Desktop.drawWindowShadows` keyed shapes by **subview index**:

```swift
chrome.rect("shadow-\(index)", …)      // BEFORE
```

Indices are not stable identity: `App.activate` re-adds a window to the front
(reordering `subviews`), closing one renumbers the rest, and maximizing makes
a window emit no shape at all. An id can therefore hand one window's retained
shape to a *different* window, and the reconciler's `previous.map(\.id) ==
current.map(\.id)` comparison sees a matching id list while the shapes
underneath have swapped owners.

Now keyed by window identity:

```swift
chrome.rect("shadow-\(UInt(bitPattern: ObjectIdentifier(window).hashValue))", …)
```

This is a genuine latent defect regardless of the visual bug. It does **not**
address the `.update`-without-delete path above, which is why I do not claim
it as the fix.

Test touched: `Tests/TUIKitTests/VTGChromeTests.swift` →
`ambianceDesktopDrawsBackdropGradientAndWindowShadow` asserted the literal id
`_shadow-0`, pinning the broken scheme. It now asserts the behaviour (a shadow
draws beneath the titlebar) instead.

## What was ruled OUT (don't re-investigate)

Each of these was measured, not assumed.

| Ruled out | Evidence |
|---|---|
| Scrollbar width in the cell layer | `Panel.drawEmbeddedScrollbars` (`Panel.swift:467`) writes exactly one cell at `bounds.size.width - 1` (line 475). Rendered and measured at widths 60/64/72/76/96 — always 1 column, always the last column. |
| Maximize geometry | `FloatingWindow.maximizedFrame` (`FloatingWindow.swift:198`) fills bounds minus insets correctly. A maximized window's frame right edge == screen last column, verified at three widths. |
| Maximized windows not re-filling after a resize | I added a re-maximize branch to OmegaCLIDE's clamp, then tested whether the regression test failed without it. It did not — they already re-fill. **I deleted that change** rather than ship a no-op. |
| The editor drawing a second bar | `Panel.embedScrollbars` (`Panel.swift:125`) restores the *previous* client's `showsOwnScrollbars = true` on switch, which is a real path to two adjacent bars. OmegaCLIDE's `ProjectWorkspace.rewireEmbeddedScrollbars` now silences **every** pane, not just the active one. Symptom persisted → not this. |
| Glyph width (`▴ ▾ ◂ ▸ ◢` rendering double-wide) | Plausible for arrows, but box-drawing borders share the same East-Asian-ambiguous class and render correctly, and the band is uniform along its whole length, not just at the arrow rows. |
| Terminal reporting more columns than it can show | Proposed a ruler script (`/tmp/ruler.sh`, since deleted) to test this. Never run — superseded by the one-column observation, which points at ghosting instead. |

## Reproduction attempts that all came back clean

All headless, all rendering real frames through `SceneRenderer`:

1. Maximized project window at width 60, then resized to 76 — bar 1 column,
   last column, both times.
2. Right-edge sweep: window right edge at screen−0/1/2/3/4 columns, sampling
   the background colour of the last 6 columns per row.
3. Multi-tab open to force `embedScrollbars` client switching.
4. Real `omegaclide` under a pty (`script -q /dev/null …`) — correct.

**None of these exercise the VTG path.** `HeadlessDriver` reports
`supportsGraphicsChrome == false`, so `Desktop.draw`'s chrome branch — the
only code that paints beside a window — never executes. That is the blind spot
that made five attempts useless, and it is the single most important thing to
fix about the test setup.

## Suggested next steps, in order

1. **Ask VectorTerminalSDK**: does `canvas.rect(id:)` with an existing id
   replace that shape, or append a new one? This decides the prime suspect
   outright.
2. If it appends → make `ChromeSceneReconciler.plan` emit deletions for
   commands whose geometry changed, and add a reconciler test:
   *a shape that moves is deleted before it is redrawn.* That test needs no
   VTG terminal — `plan` is pure.
3. **Close the test blind spot**: a fake `ChromeSurface`/canvas that records
   `rect`/`delete` calls, driven through a `HeadlessDriver` variant reporting
   `supportsGraphicsChrome == true`. Then "resize a window by one column and
   assert no stale shape remains" becomes an ordinary test, and this class of
   bug stops being invisible.
4. Only if all that comes back clean: instrument
   `ANSIDriver.presentChrome` to log `deletions`/`draws` ids per frame, resize
   by one column in the real terminal, and read the log.

## Quick confirmation available to Bobby

Toggling **Hide Graphics Layers** in the terminal should make the band
disappear entirely if this is VTG chrome. I asked twice and never got that
datum; it remains the cheapest single confirmation.
