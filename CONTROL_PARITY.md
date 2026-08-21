# Control parity: ActiveUI → TUIKit

An audit of every page in the ActiveUI catalog demo
(`~/AIResearch/ActiveUI/Code/ActiveUICatalog`, the `CatalogEntry` list — 85
pages as of 2026-08-20) against what TUIKit ships today. Purpose: see what the
TUI side does *not* have, so the next additions are a decision rather than a
guess. Each entry names the TUIKit equivalent where one exists, how close it
is, and what the gap is.

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
| AUIPasteButton | Button that reads the clipboard and hands it over | `Button` + `Pasteboard` | 🟡 | Assemble in two lines; no dedicated control. Cheap to add |
| AUIShape | Circles, capsules, rounded rects as views | `ChromeSurface` (rect/circle/polygon/sector) | 🟡 | Vector shapes exist **under VTG only**, and only inside a `draw()`. No shape *view*, no cell-mode rendering |
| AUICanvas | Draw-it-yourself view (Core Graphics) | `TUIView.draw(_:)` with `Painter` + `ChromeSurface` | 🟡 | Needs a subclass; no closure-driven `Canvas { painter in … }` view. Cheap to add |
| AUIBezierPath | Chained path — lines, curves, arcs | `ChromeCommand.polyline/.polygon/.sector` | 🟡 | Polylines/polygons/sectors only; no general curve path, VTG only. (VTG protocol has `path` with cubics — `ChromeSectorPath` already emits it) |
| AUIGradientRing | Animated gradient border with blurred glow | `verticalGradient` chrome | ➖ | Decorative; no animation story in chrome. Skip |
| AUIImageView | Images and symbols, scaled/tinted/framed | `ChromeImageAsset`, `chrome.image`/sprites (VTG) | 🟡 | Pixels exist as chrome under VTG; no `ImageView` control, no cell fallback (half-block art) |
| AUIImageViewer | Zoom/pan image view with drop | — | ❌ | Would need ImageView first |
| AUIGauge | Dial, ring, bar or needle gauge | `ProgressIndicator`, `LevelIndicator` | 🟡 | Bar form covered. No dial/ring/needle; VTG sector machinery makes a ring gauge a small job |
| AUIProgressBar | Determinate + indeterminate + spinner | `ProgressIndicator` | ✅ | Determinate and indeterminate styles |
| AUILevelIndicator | Capacity, rating, relevancy with thresholds | `LevelIndicator` | 🟡 | Capacity (`▮▮▯`) and rating (`★★☆`) styles. **No warning/critical thresholds** |
| AUIActivitySpinner | Small spinner for unmeasured work | `ProgressIndicator` (indeterminate) | ✅ | |
| Drawn controls | Twelve drawn twins so a theme can replace native chrome | every TUIKit control | ➖ | Everything in TUIKit is drawn and themed already — this page is TUIKit's default condition |
| AUITextField | Single-line text with commit + key reporting | `TextField` | ✅ | `onCommit`; placeholder; clipboard editing |
| AUISearchField | Magnifier, cancel button, two reports | `TextField` | 🟡 | No search idiom (glyph, clear-on-Esc, live vs committed reports). Cheap to add |
| AUITokenField | Committed text becomes removable tokens | — | ❌ | |
| AUIComboBox | Text field with a suggestion list | `ComboBox` | ✅ | |
| AUICompletionList | Floating suggestion list that follows a field | `PopUpList` (internal, used by `ComboBox`) | 🟡 | Not public, not attachable to an arbitrary field. Editors want this |
| AUIPromptField | Prompt box with a send button (chat composer) | `TextView`/`TextField` + `Button` | 🟡 | Assemble; no grow-to-limit composer control |
| AUIPicker | One choice: pop-up / segments / radios | `PopUpButton`, `SegmentedControl`, `RadioGroup` | ✅ | Three controls rather than one with a style switch |
| AUIRadioGroup | Stacked radio buttons | `RadioGroup` | ✅ | |
| AUISegmentedControl | Inline segments | `SegmentedControl` | ✅ | |
| AUIDatePicker | Date/time as stepper field or calendar | `DatePicker` (+ internal `CalendarView`) | ✅ | |
| AUIStepper | Increment/decrement with or without value | `Stepper` | ✅ | |
| AUISlider | Range value, ticks, snapping, two-thumb variant | `Slider` | 🟡 | Single thumb, `step` snapping, H/V. **No tick marks, no two-thumb** |
| AUIRangeSlider | Two thumbs bounding a span | — | ❌ | |
| AUIColorWell | Swatch that opens the colour panel | `ColorPicker` | ✅ | Inline chooser over all `TerminalColor` families rather than swatch + panel |
| AUILabel | Static text | `Label` | ✅ | Plus `RichText` runs |
| AUITextEditor | Multi-line editable text, rich text, line limit | `TextView` (+ `TextEditBuffer`) | 🟡 | Plain text with wrap; `RichText` is display-only. No rich editing, no grow-to-line-limit |
| AUILink | Clickable link opening a URL | — | ❌ | Terminals support OSC 8 hyperlinks; `Label` + `open(1)` is the whole job. Cheap |
| AUIShareLink | System share sheet | — | ➖ | |
| AUIHelpLink | Round `?` opening help at an anchor | — | 🟡 | Would be `Link` with a fixed glyph once `Link` exists |
| AUIPathControl | File path as clickable components | `PathControl` | ✅ | Breadcrumb bar |

## Layout, navigation & chrome

| ActiveUI | What it is | TUIKit equivalent | Status | Gap / notes |
|---|---|---|---|---|
| AUIMenu | Menus, menu buttons, context menus | `MenuBar`, `Menu`, `MenuItem`, `contextMenu`, `PopUpButton` | ✅ | Accelerators route app-wide; long-press falls back to the context menu |
| AUIControlGroup | Related controls banded with one label | `Ribbon` groups, `Panel` + `HStack` | 🟡 | Ribbon bands are toolbar-only; no general labelled band for arbitrary controls |
| AUIToolbar | NSToolbar — items, overflow, customization | `Toolbar` | ✅ | Items, flexible views, overflow `»`, display modes, long-press. User customization ➖ |
| AUIToolbox | Tool palette — radio group with pictures, docked | — | 🟡 | `Toolbar`/`Ribbon` with toggle items approximates; no exclusive-tool palette control |
| AUIStatusBar | Readouts, priority truncation, flashed messages | `StatusBar` (+ `StatusBarSegment`) | 🟡 | Segments with min/max/percentage widths. **No priority truncation order, no flashed (timed) messages** |
| AUIStatusItem | Menu bar extra | — | ➖ | No system menu bar in a terminal |
| AUIGrid | Aligned columns, spanning cells, adaptive count | `GridView` (+ `GridBuilder`, spans) | ✅ | Row/column spans. Adaptive column count: not checked/likely ❌ |
| AUISplitView | User-resizable panes | `SplitView` | ✅ | Settable axis, draggable divider |
| AUIViewThatFits | First child that fits | — | ❌ | Natural for terminals (80 vs 200 columns). Cheap |
| AUIForm | Labelled rows, shared label column, sections | `Form` (+ `FormBuilder`, `Field`) | 🟡 | Labelled rows with shared column. **Sections: none** |
| AUITabView | Tabbed content | `TabView` | ✅ | Folder tabs |
| AUIMasterDetailView | Master list driving a detail page, adaptive | `SplitView` + `ListView` | 🟡 | Assemble; no adaptive push-vs-tile behaviour for narrow terminals |
| AUISidebarList | Source list — icon, title, wrapping subtitle rows | `ListView`, `TreeView` | 🟡 | Title rows only; no icon/subtitle row layout |
| AUISidebar | THE sidebar — list + content + chrome, one API | `SlideOut` + `SplitView` | 🟡 | `SlideOut` is the edge-attached panel; no one-call sidebar assembly |
| AUINavigator | Push/pop stack with a title per level | — | ❌ | Most-missed structural piece for phone-width terminals and wizards |
| AUIFolderPanel | Tabbed document strip | `TabView` | ✅ | Literally the folder-tab container |
| AUIMatrix | Grid of cells behaving as one control (radio/highlight) | `GridView` of `Button`s | 🟡 | No single-control matrix with radio/highlight modes |
| AUIScrollView | Scrolling with pinch magnification | `ScrollView` | ✅ | Both axes; scrollbars. Magnification ➖ |
| AUIScroller | Scroll bar as its own control | `BorderScrollbars` (internal) | 🟡 | Scrollbar drawing exists but is not a standalone public control |
| AUISpacer | Flexible space along one axis | `Spacer` | ✅ | |
| AUIDivider | Self-orienting hairline | `Divider` | ✅ | Connects into borders (`DividerConnection`) |
| AUIVisualEffectView | System materials / translucency | — | ➖ | |
| AUIPreferences | Defaults system wrapper | — | ❌ | `TUIFavorites` is a favourites store, not general defaults. `UserDefaults` is a one-file wrapper |
| AUIIconStrip | Icon-over-caption pane selector | `Toolbar` (`.both` mode), `SegmentedControl` | 🟡 | No dedicated strip |
| AUIPreferencesWindow | Paged settings window | `FloatingWindow` + `TabView`/`IconStrip` | 🟡 | Assemble; no paged settings window type |
| AUIWindow | Levels, size bounds, titlebar accessories, autosave | `Window`, `FloatingWindow` | ✅ | Resize/move/close/maximize chrome. Frame autosave ❌ |
| AUIApplication | Run entry, menu bar, appearance | `App`, `Desktop`, `MenuBar`, themes | ✅ | |
| AUIPanel | Floating / utility / HUD / non-activating | `FloatingWindow`, `Dialog` | ✅ | HUD/non-activating ➖ |
| AUIView | The root every control inherits | `TUIView` | ✅ | |
| AUIBox | Titled group box | `Panel` | ✅ | |
| AUIWizard | Multi-step flows, validation, branching | — | ❌ | Installer/setup TUIs want exactly this; builds on Navigator |
| AUIPageView | Paged content — dots, arrows, swipe | — | ❌ | Cheap on top of `ZStack` |
| AUIAccordion | Titled sections opening one at a time or sharing | `DisclosureGroup` | 🟡 | One collapsible section; **no group coordination** (exclusive open / space sharing) |
| AUIZStack | Layered children | `ZStack` | ✅ | |
| AUIStack | Rows/columns that wrap, distribute, align | `HStack`, `VStack`, `StackView`, `AbsoluteLayout` | 🟡 | Alignment and distribution. **No wrapping (flow) layout** |

## Companions

| ActiveUI | What it is | TUIKit equivalent | Status | Gap / notes |
|---|---|---|---|---|
| AUIMarkdownEditor | Markdown editor — ribbon, ruler, source pane | `MarkdownView` (read-only) + `SyntaxTextView` | 🟡 | Reader and a highlighted source editor exist; no combined editor with preview |
| AUISourceEditor | Code editor — gutter, syntax, folding, diff, merge | `TUICodeEditor.CodeEditorView`, `DiffView`, gutter bands | ✅ | Phase 15: folding (E6) and merge (E7) still open per PLAN |
| AUITerminal | Terminal emulator running a real shell | `App.suspended {}` hands the TTY to a child | 🟡 | Different shape: hand-over, not an embedded pane. An in-window pty widget is a large build |
| AUICanvas / AUIBezierPath | (see Controls) | | | |
| AUIImageViewer | (see Controls) | | ❌ | |
| AUIOutlineView | Disclosure tree, any view per row | `TreeView`, `DirectoryTree` | 🟡 | Title rows; no arbitrary view per row |
| AUIBrowser | Miller columns | `Browser` (+ `FileSystemBrowserDataSource`) | ✅ | |
| AUIChart | Bars, lines, areas, sectors against shared axes | `BarChart`, `LineChart` (areas), `PieChart`, `ScatterChart`, `TimelineChart`, `Sparkline` | ✅ | Cells + VTG for every chart. Annotation marks (rule/rect/annotated) ❌; one-chart-many-marks composition ❌ (one class per shape) |
| AUIWebBrowser | Browser — chrome, tabs, find, zoom | `TUIWebBrowser` (sibling repo) | ✅ | Separate package by design |
| AUIDiagramView | Nodes and edges, auto-placed | — | ❌ | Large; VTG polylines make it drawable, layout is the work |
| AUICollectionView | Scrolling grid of uniform items, sections | `GridView` in `ScrollView` | 🟡 | Static grid; no recycling, sections, or item selection model |
| AUIBoardView | Kanban — draggable cards, limits, collapse | — | ❌ | |
| AUIDocument | Document type — open/save/registration | `FileDialog` | 🟡 | Dialogs exist; no document model, dirty tracking, or type registration |

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
| ✅ equivalent | 33 |
| 🟡 partial / assemble | 31 |
| ❌ missing | 11 |
| ➖ not applicable | 6 |

(Two catalog pages — AUICanvas/AUIBezierPath and AUIImageViewer — appear in
both the Controls and Companions groups above and are counted once; AUIScroller is 🟡 in the table and listed below because the public control is absent.)

### Missing outright (❌)

AUITokenField · AUIRangeSlider · AUILink · AUIImageViewer · AUIViewThatFits ·
AUINavigator · AUIPreferences · AUIWizard · AUIPageView · AUIDiagramView ·
AUIBoardView · (AUIScroller as a public control)

### Suggested order, if we add

Ranked by how much a *terminal* app wants it, against build cost. Nothing here
is decided — this is the menu.

**Small, obviously useful (a day or less each, cells-first like everything else)**

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

**Medium, high showcase value**

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
