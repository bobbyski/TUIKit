# Slide-Out Plan — edge panels that cost nothing when closed

**Status: PLAN ONLY. Nothing below is built yet.**

Written 2026-08-15. Supersedes a docking plan drafted the same day and
discarded before any code — see "Why not docks" below, which is the whole
reason this design looks the way it does.

Bobby, on the docking draft:

> "I dont want to loose the column - thats why i was thinking docked but I
> still loose one that way. Maybe instead of docks they should be slide out
> containers owned by the main window pane. so all windows would have the
> three slideouts they are just normally hidden"

That is the right instinct and it inverts the design. What follows is his
proposal worked out.

---

## Why not docks

A dock is permanent furniture. In a terminal, furniture is measured in
columns of text you no longer have. Here is OmegaCLIDE's project window today,
measured off a real rendered frame at a 114-column window:

| Consumer | Columns |
|---|---|
| window border (both sides) | 2 |
| sidebar | 20 |
| sidebar divider | 1 |
| editor gutter (breakpoints, ribbon, diagnostics, fold, numbers, separator) | 8 |
| **text left over** | **83** |

The docking draft would have made this **worse**, not better. Its central move
was "the centre region is itself a `Panel`", so the document's scrollbars ride
the document's own border rather than the window's — elegant, and it buys the
"outside the scroll bars" requirement for free, but a `Panel` has a border on
*both* sides. Two more columns gone, plus the dock separator. 83 → 80.

Bobby noticed the cost before a line was written. A dock that is open costs
its width; a dock that is *closed* still costs a separator or a stub. The only
arrangement that costs nothing is one that **is not there**.

---

## The design

Three slide-outs — leading, trailing, bottom — **owned by `Window`**, so every
window in every app has them without composing anything. Closed is the normal
state and closed costs **zero cells**: no separator, no stub, no reserved
column. The layout of a window with all three closed is byte-for-byte what it
is today.

Open, a slide-out **overlays** the content rather than displacing it:

```text
 closed — the whole window is document          open — it slides over
┌ proj ─────────────────────────────┐          ┌ proj ─────────────────────────────┐
│  1 │ import Foundation          ▴ │          │┌ Files ────┐mport Foundation    ▴ │
│  2 │                            █ │          ││ ▾ Sources │                    █ │
│  3 │ struct App {               ▾ │          ││   main.sw │ruct App {           ▾ │
│    │                              │          │└───────────┘                      │
└──────────────────────────◂ ▸ ─────┘          └──────────────────────────◂ ▸ ─────┘
```

Overlaying is what makes zero-cost possible, and it has a second benefit worth
stating: **the document does not reflow**. A docked panel opening and closing
re-wraps the editor, moves every soft-wrapped line, and scrolls the caret out
from under you. An overlay changes nothing underneath it.

The trade is real and it is the one thing to be honest about: while a
slide-out is open it covers part of the document. Two things pay for that:

* **Transient by default.** Activating a row (opening a file, jumping to a
  match) closes the slide-out and returns focus to the document. You reach for
  it, use it, and it is gone. That is the interaction a slide-out is *for*.
* **Pin to keep it.** A pinned slide-out stops overlaying and takes its space
  from the document — at which point it is a dock, and it costs a column,
  because the user asked for it. **One mechanism, two modes**: same geometry
  code, one flag. Nobody has to choose between the two designs; pinning is the
  choice, made per window, at the moment it matters.

Scrollbars need no new mechanism either. A slide-out is drawn inside the
window's content region, so the window's border — and the scrollbars embedded
in it — stay exactly where they are and stay usable. The trailing slide-out
stops one column short of the border rather than covering it, which is the
original "exist outside of the scroll bars" requirement, satisfied by not
touching them at all.

---

## API sketch

```swift
public enum SlideOutEdge: Hashable, Sendable { case leading, trailing, bottom }

@MainActor
public final class SlideOut {
    public let edge: SlideOutEdge
    public var title: String
    public let content: TUIView

    /// Columns (leading/trailing) or rows (bottom), clamped to the window.
    public var length: Int
    public var minimumLength: Int

    /// Open slide-outs overlay the content; a PINNED one takes its space
    /// from the content instead, which is what a dock is.
    public var isPinned: Bool

    /// Whether activating a row inside closes it. Default true, ignored
    /// while pinned.
    public var closesOnActivate: Bool

    public private(set) var isOpen: Bool
    public var onVisibilityChanged: (Bool) -> Void
    public var onLengthChanged: (Int) -> Void
}

public extension Window {
    @discardableResult
    func addSlideOut(_ edge: SlideOutEdge, title: String, content: TUIView, length: Int) -> SlideOut

    func slideOut(at edge: SlideOutEdge) -> SlideOut?
    func openSlideOut(_ edge: SlideOutEdge)    // opens AND takes focus
    func closeSlideOut(_ edge: SlideOutEdge)   // closes AND restores focus
    func toggleSlideOut(_ edge: SlideOutEdge)
}
```

Focus is not optional decoration here. Opening moves the first responder into
the slide-out and closing restores it to whatever had it before — a keyboard
user who opens a panel they cannot reach, or closes one and loses focus into
nothing, has a broken window. This is the same bug class as the docking
draft's D4 note, except with overlays it is on the main path rather than an
edge case, which is a good reason to prefer this design's version of it.

---

## Decisions already made (Bobby: "I don't have an answer because i don't know")

The three questions the docking draft left open, answered here so nothing is
blocked. All are cheap to reverse.

1. **No top edge.** Three were asked for; a fourth is API surface with no
   customer. The enum can grow.
2. **No collapsed stub.** The docking draft needed one for discoverability
   because a hidden dock is invisible. Closed slide-outs are invisible *on
   purpose* — that is the feature — so discovery comes from the menu and its
   shortcut, not from spending a permanent row on an affordance.
3. **View menu, not Window menu.** A slide-out is not a window: it has no
   title bar, cannot be raised or moved, and does not belong in a list of
   windows. The Window menu keeps real windows only.

---

## Phases

| # | Item | Status | Notes |
|---|------|--------|-------|
| S1 | `SlideOutEdge`, `SlideOut`, geometry | ✅ Done | `SlideOutLayout.resolve(region:requests:)` is a pure function — no window, no driver, no frame needed to test the edge cases. `Window` gained the storage, the API (`addSlideOut`/`open`/`close`/`toggle`), and `slideOutRegion`, which `FloatingWindow` narrows to the inside of its chrome: that one override is the whole of "outside the scroll bars", since a panel that never covers the border never covers the bars embedded in it. The content view is a subview of the WINDOW, not of its content area — it has to draw last, and `setContent` removes every subview of whatever it is called on, so an app rebuilding its content would otherwise take the slide-outs with it. 12 tests, including the premise (a window with three closed slide-outs renders cell-for-cell identically to one with none) and the bug the tests caught immediately: the trailing panel was positioned using the LEADING panel's width, which put it in the middle of the window. |
| S2 | Drawing & hit-testing | ✅ Done | Almost free: the content is wrapped in a `Panel`, so borders, title, theme slots and border welding all arrive with it — and an overlay without an opaque bordered box reads as corrupted text, which is why this could not wait for a later phase. Hit-testing needed no code at all: `TUIView.hitTest` walks `subviews.reversed()`, so a panel added after the window's chrome wins over what it covers. |
| S3 | Open / close / focus hand-off | ✅ Done | Opening moves the first responder into the panel and closing restores it to whatever had it before; `closeTransientSlideOuts()` closes the unpinned ones for the reach-for-it-use-it-gone case. Tested, including that a closed panel never holds focus and that toggling twice returns the window to its exact starting cells — no residue, which is what `RESIZE_ERROR.md` looks like when nobody tests for it. |
| S4 | Pinning | ✅ Done | `Window.applySlideOutContent(_:)` is the hook; `FloatingWindow` overrides it. The document lives in a CONTAINER inside the panel's content rather than being the panel's content, because the region slide-outs are laid out in must stay the full inside of the chrome — if those were the same view, a pinned panel would move out from under itself on every layout pass. Caret-keeping is still open (nothing scrolls the caret back into view when the document narrows). |
| S5 | Resize | ✅ Done | Drag the panel's inner border — the one the document is on the other side of, so the right edge of a leading panel and the left edge of a trailing one. Lives in `Window.routeMouse` as a PRE-PASS ahead of hit-test delivery, for the same reason `handleHotKey` runs before focus routing: the edge is the panel's own border and the panel would otherwise get first refusal. (`Panel` is `final`, so a subclass was not an option — which turned out to be the better design anyway, since the window owns the geometry.) The length is measured from the FIXED edge, because the panel's own frame moves as it resizes and a length measured against a moving edge chases the pointer. |
| S6 | Persistence surface | ⏳ | No file I/O in TUIKit: a small `Codable` state (per-edge length, pinned, open) plus `onLengthChanged`/`onVisibilityChanged`, the way `SplitView` reports `onDividerMoved` and lets the host store it. |
| S7 | Tests + tutorial chapter | ⏳ | See below. |

Out of scope: animation (a terminal redraws whole frames; "slide" is the
metaphor, not a tween), dragging a slide-out to another edge, and tearing one
off into a real window.

---

## OmegaCLIDE migration (after S7)

| Edge | Content | Replaces |
|---|---|---|
| leading | the existing Files + Structure `TabView` | the `SplitView` sidebar — **+21 columns of text when closed** |
| bottom | a `TabView`: Build output, Search results, Git | the RUN and SEARCH floating windows |
| trailing | — | nothing yet ("i don't need that one yet") |

`ProjectWorkspace.rewireEmbeddedScrollbars` and its comment about two bars
appearing side by side can go: with no sidebar sharing the border, the window
has exactly one scroll client.

**Do not migrate before S7.** `RESIZE_ERROR.md` — a bar at a window's right
edge that grows when the window moves one column — is still open, and its
postmortem is that *no test exercised the path that paints beside a window*.
Slide-outs paint at window edges. Adding a second edge-painter before that is
closed makes both harder to diagnose.

---

## Test strategy, and the trap to avoid

`RESIZE_ERROR.md` cost five failed reproductions because `HeadlessDriver`
reports `supportsGraphicsChrome == false`, so the branch that paints beside a
window never ran in a test. S7 is therefore not optional and must assert on
**rendered frames**, not `frame` arithmetic:

1. **Zero cost closed** — a window with three closed slide-outs renders
   cell-for-cell identically to one with none. This is the whole premise; it
   should be the first test written and the last one allowed to fail.
2. Overlay covers content and restores it exactly on close (no residue — the
   `.update`-without-delete ghost in `RESIZE_ERROR.md` is what residue looks
   like when nobody tests for it).
3. Pinned insets the content and the caret stays visible.
4. The window's embedded scrollbars are untouched in every mode, with a
   trailing slide-out open — the "outside the scroll bars" requirement,
   asserted directly.
5. Focus: open takes it, close restores it, a closed slide-out never holds it.
6. A tutorial chapter, because the tutorial is this project's anti-rot net.
