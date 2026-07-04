# TUIKit Style Sheets

The stylesheet layer (PLAN 7.4) puts CSS-shaped selectors on top of the
semantic theme system. Two commitments define it:

1. **Optional.** Nothing in TUIKit requires a stylesheet. `TUIView.styleSheet`
   is `nil` by default; with no sheets in the ancestor chain,
   `effectiveTheme` is exactly the inherited theme, and rendering is
   bit-for-bit what it was before this layer existed. Apps that are happy
   with `window.theme = .ocean` never touch it.
2. **Logical.** Selectors address what a view *is* — type, `#identifier`,
   `.styleClasses`, `:focused` — never where it sits. Properties write into
   the semantic `Theme` slots and text attributes, never layout. Geometry
   stays with anchors, stacks, and grids.

## Identity hooks

Every `TUIView` carries the selector hooks:

| Property       | CSS equivalent | Example                          |
|----------------|----------------|----------------------------------|
| Swift type     | element name   | `Button`, `ListView`, `Panel`    |
| `identifier`   | `id=`          | `saveButton.identifier = "save"` |
| `styleClasses` | `class=`       | `label.styleClasses = ["warning"]` |

## Grammar

```css
/* comments allowed */
Button            { color: brightWhite; bold: true; }
.warning          { color: brightYellow; }
#save             { accent: green; }
ListView.sidebar  { selection-background: #4477aa; }
TextField:focused { underline: true; }
Panel Label       { color: cyan; }        /* descendant */
Button, Stepper   { dim: false; }         /* alternatives */
Panel.tool        { border: double; border-color: cyan; }
Dialog            { border: rounded; }
.chromeless       { border: none; }
```

- A **compound** combines `Type`, `#id`, any number of `.class`es, and
  `:focused`, in that spirit: `ListView.sidebar#files:focused`.
- Whitespace between compounds means **descendant** (any depth).
- Commas separate alternative selectors for one rule.
- Parsing is tolerant: malformed rules and unknown properties are skipped.

## Properties (logical only)

| Property                                  | Writes to                  |
|-------------------------------------------|----------------------------|
| `color`, `background`                     | `theme.base` colors        |
| `bold`, `dim`, `italic`, `underline`      | `theme.base.flags`         |
| `accent`                                  | `theme.accent`             |
| `selection-color`, `selection-background` | `theme.selection`          |
| `header-color`, `header-background`       | `theme.header`             |
| `border-color`, `border-background`       | `theme.border`             |
| `placeholder-color`, `placeholder-background` | `theme.placeholder`    |
| `scrollbar-color`, `scrollbar-background` | `theme.scrollbar` (thumb / track) |
| `border`                                  | `theme.borderStyle`        |

Color values: the 16 ANSI names (`red` … `brightWhite`), `#rrggbb`,
`palette(n)`, `standard`. Flags take `true`/`false`. `border` takes
`none`, `single`, `rounded`, `double`, or `heavy` — panels, dialogs,
floating-window chrome, and menu dropdowns all follow it.

There are deliberately **no** layout, size, spacing, or position
properties.

## Cascade & resolution

`view.effectiveTheme` resolves as:

1. Inherited theme (nearest ancestor `theme`, else `.standard`).
2. Every sheet in the ancestor chain, **outermost first** — inner sheets
   override outer ones.
3. Within a sheet: matching rules sorted by **specificity**
   (`#id` = 100, `.class`/`:focused` = 10, type = 1, summed over the
   descendant chain), ties broken by **source order** (later wins).

Because the resolved result *is* the effective theme, every themed control
(and the painter's `.standard`-color substitution) picks stylesheet results
up with no stylesheet awareness of its own. `:focused` re-resolves
naturally on focus changes since focus dirties the view.

## Costs & caveats

- Resolution walks the ancestor chain per draw; with no sheets that walk
  is the same one themes always did. Rule matching is O(rules × chain) and
  uncached in v1 — fine at terminal scale; cache when profiling says so.
- Type selectors match the exact Swift class name (no subclass matching).
- Slot backgrounds derived by palette themes (e.g. `border` on `.ocean`)
  don't follow a stylesheet `background:` automatically — set the slot
  color explicitly if you change the background out from under a palette
  theme.
