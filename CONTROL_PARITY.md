# Control parity: ActiveUI → TUIKit

An audit of every page in the ActiveUI catalog demo
(`~/AIResearch/ActiveUI/Code/ActiveUICatalog`, the `CatalogEntry` list — 85
pages as of 2026-08-20) against what TUIKit ships today. Purpose: see what the
TUI side does *not* have, so the next additions are a decision rather than a
guess. Each entry names the TUIKit equivalent where one exists, how close it
is, and what the gap is.

**The fill plan is PLAN.md → Phase 16** (28 items in three waves; design principles decided 2026-08-21). This document stays the audit; the phase table carries status.

Statuses:

| Mark | Meaning |
|---|---|
| ✅ | Equivalent exists; same job, idiomatic to a terminal |
| 🟡 | Partial — the job is coverable by assembling existing pieces, or the control exists with notable gaps |
| ❌ | Missing — nothing does this job today |
| ➖ | Not applicable in a terminal (no sensible TUI twin); not a gap |

TUIKit inventory used: `Sources/TUIKit` (public classes), `Sources/TUICodeEditor`,
and the sibling repo `Code/TUIWebBrowser`. The gallery (`Demo/TUIKitGallery`)
is the showcase — PLAN rule: every new control gets a gallery spot.

---

## Controls

| ActiveUI | What it is | TUIKit equivalent | Status | Gap / notes |
|---|---|---|---|---|
| AUIButton | Push button | `Button` | ✅ | Plus `onLongPress`, `contextMenu`, theme button slot |
| controlSize | One size property across native controls | — | ➖ | Cells have one size; density is the theme's business |
| AUIToggle | Checkbox bound to a Bool | `Checkbox`, `ToggleButton` | ✅ | Both bindable (`Binding`) |
| AUIPasteButton | Button that reads the clipboard and hands it over | `PasteButton` | ✅ | Wave A (16.10): wraps a `Button`; `onPaste` / `onEmpty` |
| AUIShape | Circles, capsules, rounded rects as views | `ChromeSurface` (rect/circle/polygon/sector) | 🟡 | Vector shapes exist **under VTG only**, and only inside a `draw()`. No shape *view*, no cell-mode rendering |
| AUICanvas | Draw-it-yourself view (Core Graphics) | `Canvas` | ✅ | Wave A (16.9): `drawCells` / `drawChrome` closures; chrome-only canvases show the framed "VTG graphics required" placeholder on plain terminals |
| AUIBezierPath | Chained path — lines, curves, arcs | `ChromeCommand.polyline/.polygon/.sector` | 🟡 | Polylines/polygons/sectors only; no general curve path, VTG only. (VTG protocol has `path` with cubics — `ChromeSectorPath` already emits it) |
| AUIGradientRing | Animated gradient border with blurred glow | `verticalGradient` chrome | ➖ | Decorative; no animation story in chrome. Skip |
| AUIImageView | Images and symbols, scaled/tinted/framed | `ImageView` | ✅ | Wave B (16.20): card + menu in cells, pixels under VTG |
| AUIImageViewer | Zoom/pan image view with drop | `ImageViewer` | ✅ | Wave B (16.20): zoom/pan keys under VTG |
| AUIGauge | Dial, ring, bar or needle gauge | `Gauge` | ✅ | Wave B (16.12): bar in cells, ring/dial under VTG, thresholds |
| AUIProgressBar | Determinate + indeterminate + spinner | `ProgressIndicator` | ✅ | Determinate and indeterminate styles |
| AUILevelIndicator | Capacity, rating, relevancy with thresholds | `LevelIndicator` | ✅ | Wave B (16.12): `warningLevel` / `criticalLevel` |
| AUIActivitySpinner | Small spinner for unmeasured work | `ProgressIndicator` (indeterminate) | ✅ | |
| Drawn controls | Twelve drawn twins so a theme can replace native chrome | every TUIKit control | ➖ | Everything in TUIKit is drawn and themed already — this page is TUIKit's default condition |
| AUITextField | Single-line text with commit + key reporting | `TextField` | ✅ | `onCommit`; placeholder; clipboard editing |
| AUISearchField | Magnifier, cancel button, two reports | `SearchField` | ✅ | Wave A (16.2): `⌕`, `✕`/Esc clear, live `onSearch` (optional debounce), `onCommit` |
| AUITokenField | Committed text becomes removable tokens | `TokenField` | ✅ | Wave B (16.15); no ←/→ token walking yet |
| AUIComboBox | Text field with a suggestion list | `ComboBox` | ✅ | |
| AUICompletionList | Floating suggestion list that follows a field | `CompletionList` | ✅ | Wave B (16.16): attaches to any `TextField`; the field keeps focus |
| AUIPromptField | Prompt box with a send button (chat composer) | `TextView`/`TextField` + `Button` | 🟡 | Assemble; no grow-to-limit composer control |
| AUIPicker | One choice: pop-up / segments / radios | `PopUpButton`, `SegmentedControl`, `RadioGroup` | ✅ | Three controls rather than one with a style switch |
| AUIRadioGroup | Stacked radio buttons | `RadioGroup` | ✅ | |
| AUISegmentedControl | Inline segments | `SegmentedControl` | ✅ | |
| AUIDatePicker | Date/time as stepper field or calendar | `DatePicker` (+ internal `CalendarView`) | ✅ | |
| AUIStepper | Increment/decrement with or without value | `Stepper` | ✅ | |
| AUISlider | Range value, ticks, snapping, two-thumb variant | `Slider`, `RangeSlider` | ✅ | Wave A (16.3): `tickMarks` + `snapsToTicks`; the two-thumb variant is `RangeSlider` |
| AUIRangeSlider | Two thumbs bounding a span | `RangeSlider` | ✅ | Wave A (16.3): `minimumGap`, Space switches thumbs; horizontal only |
| AUIColorWell | Swatch that opens the colour panel | `ColorPicker` | ✅ | Inline chooser over all `TerminalColor` families rather than swatch + panel |
| AUILabel | Static text | `Label` | ✅ | Plus `RichText` runs |
| AUITextEditor | Multi-line editable text, rich text, line limit | `TextView` (+ `TextEditBuffer`) | 🟡 | Plain text with wrap; `RichText` is display-only. No rich editing, no grow-to-line-limit |
| AUILink | Clickable link opening a URL | `Link` | ✅ | Wave A (16.7): `onOpen` or the platform opener. OSC 8 hyperlinks deferred (need a cell-level URL attribute) |
| AUIShareLink | System share sheet | — | ➖ | |
| AUIHelpLink | Round `?` opening help at an anchor | `Link.help(anchor:baseURL:)` | ✅ | Wave A (16.7): the `(?)` dress of `Link` |
| AUIPathControl | File path as clickable components | `PathControl` | ✅ | Breadcrumb bar |

## Layout, navigation & chrome

| ActiveUI | What it is | TUIKit equivalent | Status | Gap / notes |
|---|---|---|---|---|
| AUIMenu | Menus, menu buttons, context menus | `MenuBar`, `Menu`, `MenuItem`, `contextMenu`, `PopUpButton` | ✅ | Accelerators route app-wide; long-press falls back to the context menu |
| AUIControlGroup | Related controls banded with one label | `Panel` + `HStack`, `Form` `Section` | 🟡 | A titled `Panel` is the band; no dedicated control |
| AUIToolbar | NSToolbar — items, overflow, customization | `Toolbar` | ✅ | Items, flexible views, overflow `»`, display modes, long-press. User customization ➖ |
| AUIToolbox | Tool palette — radio group with pictures, docked | `Toolbox` | ✅ | Wave B (16.14) |
| AUIStatusBar | Readouts, priority truncation, flashed messages | `StatusBar` (+ `StatusBarSegment`) | ✅ | Wave A (16.8): `flash(_:for:)`, `priority` decides what narrows first |
| AUIStatusItem | Menu bar extra | — | ➖ | No system menu bar in a terminal |
| AUIGrid | Aligned columns, spanning cells, adaptive count | `GridView` (+ `GridBuilder`, spans) | ✅ | Row/column spans. Adaptive column count: not checked/likely ❌ |
| AUISplitView | User-resizable panes | `SplitView` | ✅ | Settable axis, draggable divider |
| AUIViewThatFits | First child that fits | `ViewThatFits` | ✅ | Wave A (16.4): axis horizontal / vertical / both |
| AUIForm | Labelled rows, shared label column, sections | `Form` (+ `FormBuilder`, `Field`, `Section`) | ✅ | Wave B (16.18): `Section` headers |
| AUITabView | Tabbed content | `TabView` | ✅ | Folder tabs |
| AUIMasterDetailView | Master list driving a detail page, adaptive | `MasterDetail` | ✅ | Wave B (16.19): tiles wide, pushes narrow |
| AUISidebarList | Source list — icon, title, wrapping subtitle rows | `SidebarList` | ✅ | Wave B (16.19): icon + title + subtitle rows |
| AUISidebar | THE sidebar — list + content + chrome, one API | `SlideOut` (+ `MasterDetail`) | ✅ | The TUIKit sidebar is `SlideOut`: a full-height panel sliding out of the window's edge, revealed by shifting the content aside, with `◂`/`▸` toggles on the border (OmegaCLIDE's left pane). The list-drives-detail idiom is `MasterDetail` |
| AUINavigator | Push/pop stack with a title per level | `Navigator` | ✅ | Wave A (16.1): `◂ Back` header, Esc/Backspace/Enter pops, focus follows the top |
| AUIFolderPanel | Tabbed document strip | `TabView` | ✅ | Literally the folder-tab container |
| AUIMatrix | Grid of cells behaving as one control (radio/highlight) | `Matrix` | ✅ | Wave B (16.13) |
| AUIScrollView | Scrolling with pinch magnification | `ScrollView` | ✅ | Both axes; scrollbars. Magnification ➖ |
| AUIScroller | Scroll bar as its own control | `Scroller` | ✅ | Wave B (16.21) |
| AUISpacer | Flexible space along one axis | `Spacer` | ✅ | |
| AUIDivider | Self-orienting hairline | `Divider` | ✅ | Connects into borders (`DividerConnection`) |
| AUIVisualEffectView | System materials / translucency | — | ➖ | |
| AUIPreferences | Defaults system wrapper | `Preferences` | ✅ | Wave B (16.22): UserDefaults / JSON file / ephemeral |
| AUIIconStrip | Icon-over-caption pane selector | `Toolbar` (`.both` mode), `SegmentedControl` | 🟡 | No dedicated strip |
| AUIPreferencesWindow | Paged settings window | `PreferencesDialog` | ✅ | 16.29: pages behind a `Toolbox` strip (`.toolbar`) or a `SidebarList` (`.split`) |
| AUIWindow | Levels, size bounds, titlebar accessories, autosave | `Window`, `FloatingWindow` | ✅ | Resize/move/close/maximize chrome. Frame autosave ❌ |
| AUIApplication | Run entry, menu bar, appearance | `App`, `Desktop`, `MenuBar`, themes | ✅ | |
| AUIPanel | Floating / utility / HUD / non-activating | `FloatingWindow`, `Dialog` | ✅ | HUD/non-activating ➖ |
| AUIView | The root every control inherits | `TUIView` | ✅ | |
| AUIBox | Titled group box | `Panel` | ✅ | |
| AUIWizard | Multi-step flows, validation, branching | `Wizard` | ✅ | Wave B (16.11): on `Navigator` |
| AUIPageView | Paged content — dots, arrows, swipe | `PageView` | ✅ | Wave A (16.5): dots + arrows, ←/→, PageUp/Down, click |
| AUIAccordion | Titled sections opening one at a time or sharing | `Accordion` | ✅ | Wave A (16.6): `.exclusive` / `.shared` over `DisclosureGroup`s |
| AUIZStack | Layered children | `ZStack` | ✅ | |
| AUIStack | Rows/columns that wrap, distribute, align | `HStack`, `VStack`, `FlowStack`, `AbsoluteLayout` | ✅ | Wave B (16.17): `FlowStack` wraps |

## Companions

| ActiveUI | What it is | TUIKit equivalent | Status | Gap / notes |
|---|---|---|---|---|
| AUIMarkdownEditor | Markdown editor — ribbon, ruler, source pane | `MarkdownView` (`isEditing`) | ✅ | Wave B (16.24): flips to a highlighted source editor; not WYSIWYG by decision |
| AUISourceEditor | Code editor — gutter, syntax, folding, diff, merge | `TUICodeEditor.CodeEditorView`, `DiffView`, gutter bands | ✅ | Phase 15: folding (E6) and merge (E7) still open per PLAN |
| AUITerminal | Terminal emulator running a real shell | `App.suspended {}` hands the TTY to a child | 🟡 | Different shape: hand-over, not an embedded pane. An in-window pty widget is a large build |
| AUICanvas / AUIBezierPath | (see Controls) | | | |
| AUIImageViewer | (see Controls) | | | |
| AUIOutlineView | Disclosure tree, any view per row | `TreeView`, `DirectoryTree` | 🟡 | Title rows; no arbitrary view per row |
| AUIBrowser | Miller columns | `Browser` (+ `FileSystemBrowserDataSource`) | ✅ | |
| AUIChart | Bars, lines, areas, sectors against shared axes | `BarChart`, `LineChart` (areas), `PieChart`, `ScatterChart`, `TimelineChart`, `Sparkline` | ✅ | Cells + VTG for every chart. Annotation marks (rule/rect/annotated) ❌; one-chart-many-marks composition ❌ (one class per shape) |
| AUIWebBrowser | Browser — chrome, tabs, find, zoom | `TUIWebBrowser` (sibling repo) | ✅ | Separate package by design |
| AUIDiagramView | Nodes and edges, auto-placed | — | ❌ | Large; VTG polylines make it drawable, layout is the work |
| AUICollectionView | Scrolling grid of uniform items, sections | `CollectionView` | ✅ | Wave B (16.23): sections, selection; no recycling |
| AUIBoardView | Kanban — draggable cards, limits, collapse | — | ❌ | |
| AUIDocument | Document type — open/save/registration | `DocumentController` | ✅ | Wave B (16.25): open/save/save-as, dirty title, close confirm, recents |

## TUIKit controls with no ActiveUI page

For completeness — things the TUI side has that the catalog does not list
(either terminal-specific or covered by a broader ActiveUI page):

`DirectoryTree`, `DirectoryList`, `FileDialog`, `Glob` (file-system browsing);
`SlideOut` / `SlideOutChrome` (edge panels); `Ribbon` (grouped toolbar);
`SyntaxTextView` + `SyntaxHighlighters` (HTML/CSS/JS lexers, provider seam);
`Sparkline`, `TimelineChart` (would be `AUIChart` marks); `Dialog` (modal with
default/cancel); `Desktop`; `TUIFavorites`; `Pasteboard`; `StatusBarSegment`;
the theme/CSS system (`Theme`, `StyleSheet`, contexts) and the VTG chrome layer
(`ChromeSurface`, `ChromeCommand`, `VectorChrome`).

---

## Summary

| | Count |
|---|---|
| ✅ equivalent | 65 |
| 🟡 partial / assemble | 8 |
| ❌ missing | 2 |
| ➖ not applicable | 6 |

(Two catalog pages — AUICanvas/AUIBezierPath and AUIImageViewer — appear in
both the Controls and Companions groups above and are counted once; AUIScroller is 🟡 in the table and listed below because the public control is absent.)

### Missing outright (❌)

AUIDiagramView · AUIBoardView — both planned as sibling packages (PLAN 16.27,
16.28), alongside AUITerminal (16.26, partial today via `App.suspended`).

Wave A (PLAN 16.1–16.10) and Wave B (16.11–16.25), both shipped 2026-08-21,
closed every in-package gap; what remains 🟡 is either assembled from parts
(ControlGroup, PromptField, IconStrip, BezierPath, Shape,
OutlineView row views, Terminal, Canvas-level Bezier) or a sibling-package
item.

### Suggested order, if we add

Ranked by how much a *terminal* app wants it, against build cost. Nothing here
is decided — this is the menu.

**Small, obviously useful — ✅ all shipped as Wave A (2026-08-21)**

1. **Navigator** — push/pop view stack with a title per level. Unblocks phone-width layouts, wizards, settings drill-downs. The one structural piece almost every TUI reinvents.
2. **SearchField** — `TextField` plus magnifier glyph, Esc-to-clear, live and committed reports.
3. **RangeSlider** — `Slider` with a second thumb and a minimum gap.
4. **ViewThatFits** — first child whose intrinsic size fits; terminals vary from 80 to 250 columns, so this is more useful here than on desktop.
5. **PageView** — `ZStack` + dots + `←/→`.
6. **Accordion** — coordination over existing `DisclosureGroup`s (exclusive open, space sharing).
7. **Link** — OSC 8 hyperlink label that opens or hands over the URL; HelpLink falls out of it.
8. **StatusBar flash + priority truncation** — finish the existing control's gaps.
9. **Canvas view** — `TUIView` that takes a draw closure (`Painter` and optional `ChromeSurface`), so apps draw without subclassing.
10. **PasteButton** — `Button` + `Pasteboard`, for symmetry.

**Medium, high showcase value — ✅ all shipped as Wave B (2026-08-21)**

11. **Wizard** — steps, validation, branching, on top of Navigator. Installer and setup TUIs are a core terminal use case.
12. **Gauge** — ring/dial under VTG (sectors already exist), bar in cells; thresholds shared with LevelIndicator.
13. **LevelIndicator thresholds** — warning/critical colour bands.
14. **Matrix** — grid of cells as one control with radio/highlight modes (keyboard navigation is the work).
15. **Toolbox** — exclusive tool palette docked to an edge.
16. **TokenField** — tokens from committed text; To:-field idiom.
17. **CompletionList (public)** — promote the internal pop-up list so any field, and the code editor, can attach one.
18. **Flow (wrapping) stack** — the missing `AUIStack` mode; tag clouds, button rows that reflow.
19. **Form sections** — headers within `Form`.
20. **Sidebar / MasterDetail** — one-call assembly over `SlideOut` + `SplitView`, adaptive to width (push via Navigator when narrow).
21. **ImageView** — `chrome.image` under VTG with a half-block cell fallback; ImageViewer (zoom/pan) after it.
22. **Scroller (public)** — expose the border scrollbar as a control that drives something else.
23. **Preferences** — thin `UserDefaults`-backed store with a mimic for Linux.
24. **CollectionView** — selection model, sections, recycling over `GridView`.

**Large or questionable for a terminal**

25. **BoardView** (kanban, drag) — doable with the existing drag machinery, but a big control.
26. **DiagramView** — VTG can draw it; automatic layout is the real project.
27. **MarkdownEditor** — editor + live preview split over `SyntaxTextView` + `MarkdownView`.
28. **Document model** — open/save/dirty/recents; ties into `FileDialog`.
29. **Terminal pane** — an in-window pty emulator. Large; `App.suspended` covers the common need.
30. Skip: StatusItem, VisualEffectView, ShareLink, GradientRing, controlSize, Drawn controls (TUIKit's default condition), ScrollView magnification, NSToolbar user customization.

When any of these lands: gallery spot (PLAN rule), headless tests, cells-first
with VTG as the optional upgrade, theme slots through CSS.
