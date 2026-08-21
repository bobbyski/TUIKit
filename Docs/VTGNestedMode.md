# VTG nested mode — proposal from the TUIKit side

Status: proposal (2026-08-21). Audience: the GraphicalTerminal / VectorTerminal
protocol work. Origin: Phase 16.26 `TUITerminal` — a terminal-emulator pane
inside a TUIKit app — wants the apps it hosts to keep their VTG graphics.

## The problem in one paragraph

A TUIKit app hosting a child terminal pane renders the child's *text* itself
(it is an emulator), but the child's VTG commands describe pixels in the
child's own canvas: origin at the pane's top-left, ids in the child's own
namespace, layer state (default layer, scroll, clip, alpha, viewport) the
child believes it owns. Today the host scene has one global layer state and
creation-order stacking inside each layer, layer −1 (under text — where chrome
lives) accepts `clipLayer` but not `scrollLayer`, and nothing namespaces ids.
So a child's graphics cannot simply be forwarded: they land at the wrong
origin, collide with host ids, and fight the host for layer state.

## What exists that this builds on

From `VTGLayerModel` (SwiftTerm) and the SDK:

| Facility | Layers | Notes |
|---|---|---|
| Retained objects by id, update-in-place keeps creation-order stacking | all | TUIKit's reconciler already depends on this |
| `clipLayer` / `clearLayerClip` | −1 … 4 | rectangular, layer-global |
| `scrollLayer` (pixel offset), `setLayerAlpha` | 1 … 4 only | overlays; −1 deliberately excluded |
| `setViewportMode` / `setViewportScale` | 1 … 4 | fixed-resolution coordinate spaces |
| `startFrame` / `endFrame` / `cancelFrame`, replies `frameStarted` / `frameCommitted` | — | replies carry the frame id |
| hit regions + VTG mouse events | — | events carry region ids |

## Proposed additions

### 1. A context object

```
VTG;nest,id=P,x=<px>,y=<px>,width=<px>,height=<px>[,layer=-1]
VTG;nestMove,id=P,x=,y=,width=,height=
VTG;nestDelete,id=P
```

`nest` creates a **retained context** — an origin, a clip rectangle, an id
namespace, and **its own copy of the layer state** (default layer, per-layer
scroll/clip/alpha/viewport, pending frames). It is an ordinary retained object
in the host's namespace: it stacks by creation order like any primitive,
`setLayer(id:)` can move it, and a host that deletes-and-redraws its scene
(TUIKit's rebuild plan) re-stacks it correctly without knowing what is inside.

`nestMove` repositions or resizes the context without resending its children
— the host pane scrolled, or the window was dragged. This is the per-pane
equivalent of `scrollLayer`, and it works for under-text content.

`nestDelete` drops the subtree (pane closed, child exited).

### 2. Wrapped commands

```
VTG;nested,id=P;<child command, verbatim>
```

The host forwards each of the child's VTG sequences wrapped in the context it
belongs to. Wrapping is **stateless** — no mode switch, no "begin/end raw"
window — so host frames and child frames interleave safely, and the host's
own drawing never needs to know a child is mid-batch. The host already has to
extract APC sequences from the child's byte stream (it must keep them out of
the text it emulates), so wrapping costs it nothing extra.

Inside a context the terminal:

- translates coordinates by the context origin and clips to its rectangle
  (including overlay-layer content — a child HUD must not spill out of the
  pane);
- prefixes ids with the context (`P/` or any internal scheme — the child never
  sees host ids and the host never sees child ids);
- applies child `setDefaultLayer`, `scrollLayer`, `clipLayer`,
  `setLayerAlpha`, viewport and frame commands to the **context's** layer
  state, not the global one;
- renders child layer −1 under the terminal text *within the context's
  stacking slot*, and child overlays above the text, clipped.

Contexts compose: `nested,id=A;nested,id=B;…` addresses a context inside a
context (a pane hosting an app that hosts a pane). Depth can be capped small.

### 3. Wrapped replies

```
VTG;nested,id=P;frameCommitted,id=…
VTG;nested,id=P;mouse,…              (hit-region events, child coordinates)
VTG;nested,id=P;capabilities,…       (probe answers, if the host forwards probes)
```

Every reply generated for a command that arrived wrapped goes back wrapped the
same way, so the host routes it to the right child by stripping the wrapper
and writing the inner sequence to that child's pty. Hit-region mouse events
are reported in the **child's** coordinate space.

Probes (`capabilities?`, `glyphSize?`) may be forwarded wrapped, or answered
by the host from its own cached answers — glyph metrics are identical either
way. Forwarding keeps the child's view of the terminal honest (e.g. a
capability the host itself never asked about).

### 4. Capability advertisement

`capabilities` gains `nested=1` (and a `nestDepth=N` if depth is capped) so a
host knows whether to forward graphics or fall back to the translation path
below.

## What the TUIKit host needs, independent of the terminal

Small, and buildable ahead of the terminal against a fake:

1. `ChromeCommand.Shape.nested(id:rect:)` + `ChromeSurface.nested(_:rect:)` —
   the context object emitted as part of a view's frame, so the reconciler
   orders, moves (`nestMove` on update) and deletes it with everything else.
2. The driver surfaces `nested,id=…;…` replies as a `TerminalInput` event
   routed to the owning view, instead of swallowing every APC as it does today.
3. Glyph metrics and capabilities exposed to views (the driver has them), so
   `TUITerminal` can answer or forward the child's probes.
4. In `TUITerminal`: extract APC sequences from the child's output, wrap, and
   write them inside the host's frame; unwrap replies and write them to the
   child's pty.

## Fallback if the protocol lags

`TUITerminal` can parse the child's VTG with SwiftTerm's
`VectorTerminalGraphicsParser` (pure Foundation, typed primitives), convert
to `ChromeCommand`s in cell units and draw through `ChromeSurface`. Stacking,
clipping, diffing and frames then come from TUIKit's own pipeline. Costs: the
child's layers collapse onto the host's two planes; no child scroll / alpha /
viewport; all-or-nothing visibility when the pane is partially scrolled (the
existing `covers` rule); vector text and sprites need new chrome shapes.
Usable, second-best — the nested mode is the right home for this.
