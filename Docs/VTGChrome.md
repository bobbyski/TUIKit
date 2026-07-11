# VTG Vector Chrome (Phase 10)

TUIKit's rendering is cells all the way down — and stays that way. When the
terminal happens to be a **VectorTerminal** (it speaks the VTG escape
protocol), the framework *additionally* draws a thin layer of vector shapes
on the graphics plane **under** the text: gradient titlebars with rounded
top corners, circular window buttons, rounded gradient button pills, a
desktop backdrop, window shadows. Nothing else changes:

- **No new API for apps.** There is no app-facing vector drawing surface and
  no vector control set. Apps cannot tell (except visually) which mode they
  run in.
- **Cells are the universal fallback.** A plain terminal renders exactly the
  pre-Phase-10 cells. A TUIKit app never *requires* VTG.
- **Behavior is identical in both modes.** Focus order, key routing, and
  semantic events do not consult the chrome. Hit-testing follows the visual
  (the Ambiance close circle sits at the *left* of the titlebar, so that is
  where clicks close), but every affordance exists in both modes.

## The pipeline

```text
  view.draw(painter)
     ├── painter.set/write/fill…            → CellBuffer      (always)
     └── painter.chrome?.rect/circle/…      → [ChromeCommand] (VTG terminals only)
                                                   │
  SceneRenderer.render : buffer + chromeCommands   │
                                                   ▼
  App: driver.present(buffer) ; driver.presentChrome(commands)
                                                   │
  ANSIDriver: CellPixelMapper (cells→pixels) + ChromeSceneReconciler (stale ids)
              → VectorTerminalSDK → APC escape sequences
```

- `ChromeSurface` (`painter.chrome`) is the vector sibling of `Painter`: it
  rides the same origin translation and ancestor clipping, so the Phase 3
  clipping contract holds for chrome. It exists only while the frame is
  chrome-enabled — views guard with `if let chrome = painter.chrome`.
- Geometry is **fractional cells** (`ChromeRect`, `ChromePoint`): x in cell
  widths, y in cell heights; scalar sizes (corner radius, line width) in
  cell heights. Pixels appear only inside the driver, where the begin-time
  `glyphSize?` query fixed the metrics (`CellPixelMapper`).
- Commands carry **retained-scene ids**, scoped per view (`renderTree`
  stamps the view identity; draw calls add a short key like `"titlebar"`).
  `ChromeSceneReconciler` plans each frame: identical → write nothing;
  same id order → update only the changed shapes in place; reordered ids
  (a window was raised/opened/closed) → delete-all-and-redraw, because
  retained objects keep their creation-time stacking and an in-place
  update would stack chrome differently than the cells composited above.
  VTG ids allow only ASCII letters/digits/`-`/`_`, so keys must too.
- `VerticalGradient` is built from a rounded base rect plus horizontal
  strips (VTG has no gradient primitive); strips inset themselves where
  they cross a rounded corner, so nothing paints outside the arc.

## Showing through the text plane

The under-text plane is visible only where a cell keeps the **terminal's
default background**. Chrome-drawing views therefore write those cells
through a neutral-based painter (`painter.withBase(CellStyle())`), which
defeats the theme's `.standard` substitution. That is the whole trick behind
the titlebar: the top row's cells go transparent, the gradient bar shows
through, and the title stays crisp native text on top.

## Theming

Chrome styling lives in the theme, beside the cell palette:
`ThemePalette.vector: VectorChrome?` with optional `titleBar`, `button`,
`desktop`, and `windowShadow` sections (all Codable — themes still ship as
JSON). No `vector` block → no chrome, even on a VTG terminal.

**Ambiance** (`Theme.ambiance`) is the reference: an Ubuntu homage with an
aubergine gradient desktop, dark rounded titlebars whose orange close circle
sits leading (`buttonPlacement: .leading`), and light gradient button pills
with an orange focus glow. On a plain terminal the same theme is a light-gray
surface theme with a dark header bar — fully usable, just not glossy.

## Detection & drivers

- `ANSIDriver.begin()` probes `capabilities?` (400 ms budget) *before* its
  input read source starts, then queries `glyphSize?`; without exact glyph
  metrics chrome stays off. Set `TUIKIT_VTG=0` to skip probing entirely.
  All VTG bytes flow through the driver's output queue, serialized with
  cell frames, wrapped in `startFrame`/`endFrame` for tear-free updates.
- `HeadlessDriver(supportsGraphicsChrome: true)` simulates a VTG terminal:
  it records `presentedChrome` for assertions. `VTGChromeTests` proves the
  mapper, reconciler, clipping, the Ambiance passes, and the both-modes
  behavior contract without any terminal.
- Mouse input is unchanged (10.6): VectorTerminal emits standard SGR mouse
  reporting, which the existing decoder already routes in cell coordinates.

## Current chrome pass (10.5 scope so far)

| Piece | Chrome | Fallback cells |
|---|---|---|
| `Desktop` | full-screen vertical gradient + per-window soft shadows | `fillCharacter`/`fillStyle` fill |
| `Panel` (window chrome only) | gradient titlebar, rounded top, centered title, circular close/maximize | bordered top row, `[x]`/`[+]` |
| `Button` | rounded gradient pill, focus glow stroke, press inverts gradient | tinted/bordered text, selection focus |

Inner panels (group boxes) deliberately keep cell borders. Remaining 10.5
candidates: text-field wells, scrollbar thumbs, tab folder shapes, menu bar.

## Known limits (v1)

- A rounded chrome rect that is partially clipped clamps its bounds but
  keeps its radius — a sliced arc can look subtly flattened at the clip
  edge. Windows are rarely half-offscreen; revisit with damage regions.
- Window shadows draw at desktop level (a window cannot paint outside its
  own frame), so between two *overlapping* windows the upper one's shadow
  does not fall on the lower one's titlebar.
- One glyph-size probe per run: a mid-run terminal font change would
  misalign chrome until restart. (A resize re-probe is a cheap follow-up.)
