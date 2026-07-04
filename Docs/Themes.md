# TUIKit Theme Reference & Design

> **Status: IMPLEMENTING — chunks 1–3 landed** (model + `Codable` + resolution;
> the big swap to `ResolvedTheme`/context-aware `effectiveTheme`; view-tree
> context tests + demo context wiring; CSS clarified as an on-top toggle
> (8.15)). Remaining: field well (8.13), pill buttons (8.8). Design for the
> next-generation theme system.
>
> **Decisions locked (2026-07-04):**
> 1. **Big-bang replacement** — the flat `Theme` is replaced outright: rename
>    every slot, migrate all controls, wire window contexts, update the demo, in
>    one change. No compatibility facade.
> 2. **Built-ins stay Swift** (`static let`s); the types are **`Codable`** so
>    custom themes load from JSON. Move built-ins to JSON later if desired.
> 3. **No implicit window→context mapping** — every view/window defaults to
>    `themeContext == nil` (→ `base`); contexts are set **explicitly** (the demo
>    marks its editor `contentWindow`, its chrome `desktop`, dialogs `modal`, …).
> 4. **JSON round-trips from day one** — the first commit includes encode→decode
>    equality tests and a load-from-`.json`-file test.
> 5. Resolution rides the existing weak `superview` walk (like `effectiveTheme`).
> 6. Tests use a **synthetic "rainbow" fixture** (every context/slot a distinct
>    sentinel) so `nil → base` never masks a mis-resolution.
> 7. **Consumption via `ResolvedTheme` conveniences** — `effectiveTheme` returns
>    a resolved value type exposing `.selection` / `.header` / `.border` / …
>    CellStyle helpers (plus `.field` / `.defaultButton` / `.destructiveButton` /
>    `.accent` / …), *derived from* the context-resolved flat slots. Control draw
>    code stays terse; the flat slots remain the source of truth (storage, JSON,
>    and what CSS writes into).

## Why change

The current theme is a single flat palette (`base`, `accent`, `selection`,
`header`, `border`, `scrollbar`, `placeholder`). That can't express what
Borland/Turbo actually does, where the **same role is styled differently
depending on where it appears**: the menu/status bars are gray, the code editor
is blue-on-yellow, dialogs are gray with **blue input wells**, and so on. One
`header` slot can't be both the gray menu bar *and* a blue editor title.

The fix is to make theming **contextual**: a theme is a matrix of
*slot × context*. Each context is a parallel palette; a view resolves a slot
through its own context, falling back to a complete `base`.

Three layered concepts, from bottom to top:

```
   base palette            (complete; the ultimate fallback)
        │  overridden per-context by →
   context palette         (desktop / contentWindow / … ; sparse, nullable)
        │  overridden per-view by →
   CSS stylesheet          (NOT a theme — an on-top layer; see "CSS")
        ↓
   the cell style a control finally draws with
```

## Contexts

A **context** identifies *where* a view lives. Every view resolves its slots
through one context. Windows carry a context; their subtrees inherit it unless a
child sets its own (e.g. an accessory panel).

| Context | Covers | Turbo treatment |
|---------|--------|-----------------|
| `base` | The complete fallback, used when the context is unknown **or** when a context leaves a slot `nil`. **`base` may not contain any `nil`.** | Gray chrome/dialog look (black on light gray) — the majority surface. |
| `desktop` | The desktop surface: menu bar, status bar, **and the desktop backdrop itself**. It's essentially a fixed-size window, so it carries its **own full slots** — its backdrop is *not* derivable from `base` (once `base` is gray). | Light-blue backdrop; menu/status bars gray (`header`). |
| `contentWindow` | The primary content window (the "document" — e.g. the code editor). | **Blue** window, **yellow** text, white double border. |
| `secondaryWindows` | Secondary windows — typically **non-modal** dialogs/panels. | Gray (inherits `base`). |
| `modalWindows` | **Modal** dialogs (alerts, sheets). | Gray (inherits `base`); modal chrome adds a drop shadow later. |
| `accessoryView` | Views **attached to** the content window (inspectors, tool strips, breadcrumb/tab bars). | Echoes `contentWindow` (blue) so it belongs to the editor it's attached to. |

**Resolution rule:** `resolve(slot, context) = context[slot] ?? fallback(context)[slot]`.
Every context has a **fallback parent**, which is `base` for all of them *except*
`accessoryView`, whose fallback is `contentWindow` (which itself falls back to
`base`). So an accessory that sets nothing echoes the editor it hangs off, and a
`nil` anywhere ultimately bottoms out at the complete `base`. An unknown/unset
context resolves entirely against `base`.

### Determining a view's context (at render time)

A view carries an **optional** context: `themeContext: ThemeContext?`, where
**`nil` means "follow the parent"** (inherit the nearest ancestor that sets
one; the root fallback is `base`). This mirrors how `theme` already cascades —
most views set nothing, and a window/root establishes the context for its
subtree. Windows set it by type (`contentWindow` / `secondaryWindows` /
`modalWindows`), `Desktop`/`MenuBar`/`StatusBar` set `desktop`, and an accessory
panel can opt into `accessoryView`.

**Open implementation choice (decide when we build):** how the renderer resolves
the inherited context.

1. **Walk up** the parent chain from the view (nearest non-`nil`
   `themeContext`). TUIKit *already* keeps a weak `superview` link and
   `effectiveTheme` already walks it, so this is free and consistent — an
   `effectiveThemeContext` computed exactly like `effectiveTheme`.
2. **Push down** during the render traversal: `SceneRenderer` already descends
   the tree top-down, so it can carry the "current context" as it recurses and
   swap it whenever a view sets its own — no per-view upward walk, no reliance
   on the parent link during resolution.

Both produce identical results; it's a performance/coupling call.

**The special case that likely settles it:** a **layout or refresh requested
*from* a child** whose `themeContext` is `nil`. That child cannot know its
context locally — it has to resolve *upward* at that moment. Pure push-down only
works if every such request re-renders the whole tree top-down from the root; if
a child-initiated `setNeedsLayout`/`setNeedsDisplay` resolves context locally
(the way controls already read `effectiveTheme` inside their own `draw`), it
needs the parent walk. Since `effectiveTheme` *already* rides the existing weak
`superview` link this exact way, context resolution most naturally uses the same
mechanism — which is the argument for keeping the parent link. This is the
scenario to design against, not the whole-tree render.

**Because the answer must be identical either way, we want regression tests that
lock the *observable* behavior regardless of which mechanism we pick:**

- A view with `themeContext == nil` renders with its nearest ancestor's context.
- Setting a context on a subtree root re-styles that whole subtree, and only it.
- Sibling subtrees with different contexts don't leak into each other.
- The root/`nil`-everywhere case resolves to `base`.
- Changing a window's `themeContext` (or moving a view between parents)
  re-resolves on the next render.
- **A `nil`-context child that triggers its *own* `setNeedsLayout` /
  `setNeedsDisplay` still resolves to its ancestor's context** — the
  child-initiated-refresh case that drives the parent-link question.

**Test-fixture caveat — critical:** `nil → base` fallback can *mask* these
failures. If a fixture theme leaves a context equal to `base` (as **Standard**
does everywhere, and as **Turbo** does for `desktop` and the dialog contexts),
then a bug that resolves to the *wrong* context — or that wrongly falls back to
`base` — still yields the base value, and the test passes. Real themes are
therefore unsafe fixtures. These tests must run against a **synthetic "rainbow"
theme where `base` and every context set every slot to a *distinct* sentinel
value.** Then any mis-resolution is always observable. Assert against those
distinct sentinels — never against a real theme where a context happens to
coincide with `base`.
- An accessory view overriding to `accessoryView` inside a `contentWindow`
  wins for its subtree; its children (nil) inherit the `accessoryView`
  *context*, not `contentWindow`.
- **Slot-level fallback:** an `accessoryView` slot left `nil` resolves to
  `contentWindow`'s value (its fallback parent), **not** `base`. The rainbow
  fixture must give `contentWindow` and `base` *distinct* sentinels so echoing
  the wrong one is observable. (Two separate mechanisms are under test here:
  which *context* a view inherits, and how a context's `nil` *slots* resolve.)

## Slots (renamed — flat & descriptive)

Slots become **flat, self-describing keys** so a palette is a plain dictionary
(JSON-friendly, no nested `CellStyle`). Colors split into explicit
`…Foreground` / `…Background` pairs.

| Old (today) | New flat slot keys |
|-------------|--------------------|
| `base` | `foreground`, `background` |
| `accent` | `accent`, `warningAccent`, `errorAccent` |
| `selection` | `selectionForeground`, `selectionBackground` |
| `header` | `headerForeground`, `headerBackground` |
| `border` | `borderForeground`, `borderBackground`, `borderStyle` (window/panel **frames**) · `dividerStyle` (**interior** lines — dividers, split bars, separators; usually `single` even when frames are `double`) |
| `scrollbar` | `scrollbarThumb`, `scrollbarTrack` |
| `placeholder` | `placeholderForeground`, `placeholderBackground` |
| *(new — see 8.13)* | `fieldForeground`, `fieldBackground` — the editable "well" |
| *(new — buttons)* | `defaultButtonForeground`, `defaultButtonBackground` (the Return/highlighted button) · `destructiveButtonForeground`, `destructiveButtonBackground` (dangerous actions) |

**Text attributes** (bold / dim / inverse / underline) that some slots carry are
kept out of the color grid as small per-role sets, defaulting to empty:
`headerAttributes`, `selectionAttributes`, `placeholderAttributes`,
`fieldAttributes`. (Today: `headerAttributes = [bold]`,
`placeholderAttributes = [dim]`, and Standard's `selectionAttributes =
[inverse]`.)

A color value is one of: a hex string `"#RRGGBB"`, a named color `"brightCyan"`,
or `null` (inherit `base`; illegal in `base`). `borderStyle` is one of
`single | rounded | double | heavy | none`.

## Turbo Pascal — the matrix

`base` is complete; each context lists only its **overrides** (everything else
is `→ base`). Hex uses the EGA/VGA palette.

### `base` (complete — the gray chrome/dialog baseline)

| Slot | Value |
|------|-------|
| `foreground` | Black `#000000` |
| `background` | Light Gray `#AAAAAA` |
| `accent` | Green `#00AA00` *(Borland action/OK green)* |
| `warningAccent` | Amber `#FFAA00` |
| `errorAccent` | Red `#FF0000` |
| `selectionForeground` | Black `#000000` |
| `selectionBackground` | Cyan `#00AAAA` |
| `headerForeground` | Black `#000000` |
| `headerBackground` | Light Gray `#AAAAAA` |
| `headerAttributes` | `[bold]` |
| `borderForeground` | White `#FFFFFF` |
| `borderBackground` | Light Gray `#AAAAAA` |
| `borderStyle` | `single` *(menus/interior; floating frames override to `double`)* |
| `scrollbarThumb` | Dark Gray `#555555` |
| `scrollbarTrack` | Gray `#7F7F7F` |
| `placeholderForeground` | Dark Gray `#555555` |
| `placeholderBackground` | Light Gray `#AAAAAA` |
| `placeholderAttributes` | `[dim]` |
| `fieldForeground` | Yellow `#FFFF55` |
| `fieldBackground` | Blue `#0000AA` |
| `defaultButtonForeground` | White `#FFFFFF` |
| `defaultButtonBackground` | Green `#00AA00` *(Borland default/OK button)* |
| `destructiveButtonForeground` | White `#FFFFFF` |
| `destructiveButtonBackground` | Red `#AA0000` |

> Note the key Borland detail: even on gray dialogs, **input fields are blue
> wells with yellow text** (`fieldForeground`/`fieldBackground`).

### `contentWindow` (overrides — the blue code editor)

| Slot | Value |
|------|-------|
| `foreground` | Yellow `#FFFF55` |
| `background` | Blue `#0000AA` |
| `headerForeground` | White `#FFFFFF` |
| `headerBackground` | Blue `#0000AA` |
| `borderForeground` | White `#FFFFFF` |
| `borderBackground` | Blue `#0000AA` |
| `borderStyle` | `double` *(floating window frame)* |
| `scrollbarThumb` | Light Cyan `#55FFFF` |
| `scrollbarTrack` | Navy `#00006E` |
| `placeholderForeground` | Cyan `#00AAAA` |
| `placeholderBackground` | Blue `#0000AA` |
| *(all others)* | `→ base` |

### `desktop` (overrides — menus, status bar, backdrop)

The menu/status bars use `header` (gray, from `base`); the **backdrop** is the
desktop's own `background` — a light blue that can't come from the now-gray
`base`, which is exactly why `desktop` needs its own slots.

| Slot | Value |
|------|-------|
| `background` | Light Blue `#5555FF` *(the backdrop behind windows)* |
| `foreground` | White `#FFFFFF` |
| *(all others)* | `→ base` (gray `header` for the bars, etc.) |

### `secondaryWindows` (non-modal dialogs)

| Slot | Value |
|------|-------|
| `borderStyle` | `double` *(a floating window frame)* |
| *(all others)* | `→ base` (gray) |

### `modalWindows` (modal dialogs)

| Slot | Value |
|------|-------|
| `borderStyle` | `double` *(a floating window frame)* |
| *(all others)* | `→ base` (gray); modal drop-shadow is separate chrome |

### `accessoryView` (attached to the content window)

| Slot | Value |
|------|-------|
| *(all)* | `→ contentWindow` (blue editor look, then `base`) — an accessory belongs to its editor |

## Standard — the matrix

Standard adds no color: `base` is the terminal's own palette + video
attributes, and **every context inherits `base`** (no per-context styling).

| Slot | `base` |
|------|--------|
| `foreground` / `background` | `null`-equivalent → terminal default |
| `accent` | Bright Cyan `#00FFFF` *(named)* |
| `warningAccent` / `errorAccent` | Yellow `#FFFF00` / Red `#FF0000` *(named — error/warning stay colored even in Standard)* |
| `selectionForeground` / `selectionBackground` | — ; `selectionAttributes = [inverse]` |
| `headerForeground` / `headerBackground` | — ; `headerAttributes = [bold]` |
| `borderForeground` / `borderBackground` | — |
| `borderStyle` | `single` |
| `scrollbarThumb` / `scrollbarTrack` | White `#E5E5E5` / Bright Black `#7F7F7F` *(named)* |
| `placeholderForeground` / `placeholderBackground` | — ; `placeholderAttributes = [dim]` |
| `fieldForeground` / `fieldBackground` | — ; `fieldAttributes = [underline]` |
| `defaultButton` fg / bg | Bright Green `#00FF00` / — *(named fg; buttons stay bordered/tinted)* |
| `destructiveButton` fg / bg | Bright Red `#FF0000` / — *(named)* |

(Because "terminal default" is a real thing here, `base` for Standard uses the
`.standard` sentinel color rather than a hex — it means "leave the terminal's
color." This is the one theme where `base` legitimately carries the sentinel.)

## JSON shape (Codable)

Themes are `Codable`, so they can ship as JSON files (bundle resources or
user-supplied) and load with `Theme(contentsOf:)` / `JSONDecoder`. `base` is
required and complete; the five contexts are optional and sparse.

```jsonc
{
  "name": "Turbo Pascal",
  "base": {
    "foreground": "#000000",
    "background": "#AAAAAA",
    "accent": "#00AA00",
    "warningAccent": "#FFAA00",
    "errorAccent": "#FF0000",
    "selectionForeground": "#000000",
    "selectionBackground": "#00AAAA",
    "headerForeground": "#000000",
    "headerBackground": "#AAAAAA",
    "headerAttributes": ["bold"],
    "borderForeground": "#FFFFFF",
    "borderBackground": "#AAAAAA",
    "borderStyle": "double",
    "scrollbarThumb": "#555555",
    "scrollbarTrack": "#7F7F7F",
    "placeholderForeground": "#555555",
    "placeholderBackground": "#AAAAAA",
    "placeholderAttributes": ["dim"],
    "fieldForeground": "#FFFF55",
    "fieldBackground": "#0000AA",
    "defaultButtonForeground": "#FFFFFF",
    "defaultButtonBackground": "#00AA00",
    "destructiveButtonForeground": "#FFFFFF",
    "destructiveButtonBackground": "#AA0000"
  },
  "contentWindow": {
    "foreground": "#FFFF55",
    "background": "#0000AA",
    "headerForeground": "#FFFFFF",
    "headerBackground": "#0000AA",
    "borderForeground": "#FFFFFF",
    "borderBackground": "#0000AA",
    "scrollbarThumb": "#55FFFF",
    "scrollbarTrack": "#00006E",
    "placeholderForeground": "#00AAAA",
    "placeholderBackground": "#0000AA"
  }
  // desktop / secondaryWindows / modalWindows / accessoryView omitted → all base
}
```

**Type sketch (for implementation):**

- `struct ThemePalette: Codable` — one field per slot, **all optional**
  (`TerminalColor?`, `BorderStyle?`, `[Attribute]?`). Used for `base` and every
  context.
- `struct Theme: Codable { let name: String; let base: ThemePalette; let desktop, contentWindow, secondaryWindows, modalWindows, accessoryView: ThemePalette? }`.
- `enum ThemeContext { case desktop, contentWindow, secondaryWindows, modalWindows, accessoryView, unknown }`.
- `TerminalColor` gains `Codable` (encode as `"#RRGGBB"` / named string /
  `"standard"`); `BorderStyle` and `Attribute` already have `String` raw values.
- **Validation on load:** `base` must have every field non-`nil` (except the
  Standard-style `.standard` sentinel, which is allowed). Fail decode otherwise.
- Resolution helper: `theme.resolve(_ slot:, in context:) -> value`, and the
  `Painter` grows context-awareness (a view's context selects the palette).
- Built-in themes become JSON resources plus a small registry; `Theme.builtIn`
  loads them.

## CSS is a layer, not a theme

Stylesheets (`StyleSheet`, `Docs/StyleSheets.md`) are **applied on top of** the
resolved theme — they are not themes and don't belong in the theme picker.
Cascade order, final:

```
   theme (base → context)  →  CSS rules (by specificity)  →  drawn cell
```

A CSS rule sets specific properties for matched views; unmatched properties keep
their theme-resolved value. So CSS and theme are **orthogonal**: you pick a
theme *and* optionally enable a stylesheet, and both apply.

**Disabling CSS = setting the stylesheet to `nil`.** There is no separate
"CSS off" state — the on-top layer is just `TUIView.styleSheet: StyleSheet?`.
Enabling applies the sheet; disabling sets it back to `nil`. Either way the
theme underneath is untouched, so toggling CSS never changes the selected theme:

```swift
view.styleSheet = cssEnabled ? demoSheet : nil   // the whole toggle
```

**Demo change (planned):** the demo currently exposes "CSS" as if it were a
theme (a `Theme ▸ CSS` entry). Change it to an independent **CSS toggle** that
sits **alongside** the theme dropdown — pick any theme, then flip the stylesheet
on/off (set it or `nil` it) to see it layer over whatever theme is active.

## Open questions / TBD

- ~~`accessoryView`: inherit `base` or echo `contentWindow`?~~ **Resolved:**
  fallback is `contentWindow` (then `base`).
- ~~Does `desktop` need its own backdrop slot?~~ **Resolved:** yes — `desktop`
  carries its own full slots (it's a fixed-size window-like surface), so its
  backdrop is an explicit `background`, not derived from `base`. This supersedes
  the demo's "lighten `base`" trick.
- ~~Per-context `accent`?~~ **Resolved:** yes, `accent` (plus `warningAccent`
  and `errorAccent`) are full slots, so a context can tune them (cyan in the
  editor, green in dialogs). All three fall back through the normal chain.
- Exact context-per-window-type mapping: which `FloatingWindow`s are
  `contentWindow` vs `secondaryWindows`; is a `Dialog` always `modalWindows`;
  which chrome is `desktop`. (The *resolution mechanism* — walk-up vs push-down
  — and its regression tests are settled under "Determining a view's context".)

---

## Appendix: today's theme (as shipped)

The single flat palette currently in `Theme` (pre-redesign), for reference.
This is what the code uses right now.

| Slot | Turbo Pascal (shipping) | Standard |
|------|-------------------------|----------|
| `base` fg / bg | Yellow `#FFFF55` / Blue `#0000AA` | — *(terminal default)* |
| `accent` | Light Cyan `#55FFFF` | Bright Cyan `#00FFFF` |
| `selection` fg / bg | Black `#000000` / Cyan `#00AAAA` | — *(inverse)* |
| `header` fg / bg | Black `#000000` / Light Gray `#AAAAAA` *(bold)* | — *(bold)* |
| `border` fg / bg / style | White `#FFFFFF` / Blue `#0000AA` / `double` | — / — / `single` |
| `scrollbar` thumb / track | `#55FFFF` / `#00006E` | White / Bright Black |
| `placeholder` fg / bg | Cyan `#00AAAA` / Blue `#0000AA` *(dim)* | — *(dim)* |

The shipping single-theme reuses `header` for both menu/status bars and titles,
and `selection` for rows and menu highlights — exactly the collisions the
context matrix above resolves.
