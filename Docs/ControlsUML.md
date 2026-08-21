# TUIKit Controls — UML Class Diagram

A maintained class diagram of the control layer. Update it in the same commit
as any control change (new control, new public member, new event, changed
base relationship). The diagram is Mermaid, so it renders on GitHub and in
most Markdown viewers.

Conventions:

- Only the public/framework-facing surface is shown (interaction internals
  are omitted).
- Event callbacks are listed as fields typed as closures (e.g.
  `onActivate : () -> Void`).
- `«control»` in a note marks views intended as user-facing controls, versus
  structural views (`TUIView`, `StackView`, `Window`).

## Diagram

```mermaid
classDiagram
    direction TB

    class TUIView {
        <<@MainActor, base>>
        +frame : Rect
        +bounds : Rect
        +subviews : [TUIView]
        +isHidden : Bool
        +anchors : AnchorSet?
        +theme : Theme?
        +identifier : String?
        +styleClasses : Set~String~
        +styleSheet : StyleSheet?
        +effectiveTheme : Theme
        +intrinsicContentSize : Size?
        +minimumSize : Size
        +maximumSize : Size?
        +acceptsFirstResponder : Bool
        +isFirstResponder : Bool
        +addSubview(TUIView)
        +draw(Painter)
        +layoutSubviews()
        +relayout()
        +refresh()
        +keyDown(KeyInput) Bool
        +handleHotKey(KeyInput) Bool
        +handleColdKey(KeyInput) Bool
        +mouseEvent(MouseInput) Bool
        +hitTest(Point)
    }

    class Label {
        +text : String
        +style : CellStyle
        +alignment : TextAlignment
    }

    class ControlStyle {
        <<enum>>
        tinted
        bordered
    }

    class Button {
        +title : String
        +style : ControlStyle
        +onActivate : () -> Void
        +isPressed : Bool
        +activate()
    }

    class TextField {
        +text : String
        +placeholder : String
        +onChanged : (String) -> Void
        +onSubmit : (String) -> Void
        +setText(String)
    }

    class Checkbox {
        +label : String
        +isChecked : Bool
        +onChange : (Bool) -> Void
        +toggle()
        +setChecked(Bool, notify)
    }

    class RadioGroup {
        +options : [String]
        +selectedIndex : Int?
        +onSelectionChanged : (Int) -> Void
        +select(Int, notify)
    }

    class ListView {
        +items : [String]
        +selectedIndex : Int?
        +scrollOffset : Int
        +onSelectionChanged : (Int?) -> Void
        +onActivate : (Int) -> Void
        +select(Int?, notify)
    }

    class SegmentedControl {
        +segments : [String]
        +selectedIndex : Int?
        +onSelectionChanged : (Int) -> Void
        +select(Int, notify)
    }

    class TabView {
        +selectedIndex : Int
        +tabCount : Int
        +tabBarHeight : Int
        +onSelectionChanged : (Int) -> Void
        +addTab(String, content : TUIView)
        +select(Int, notify)
        +title(at : Int) String?
    }

    class ScrollView {
        +documentView : TUIView?
        +contentOffset : Point
        +contentSize : Size
        +showsIndicators : Bool
        +onOffsetChanged : (Point) -> Void
        +setOffset(Point, notify)
    }

    class Stepper {
        +value : Int
        +range : ClosedRange~Int~
        +step : Int
        +onValueChanged : (Int) -> Void
        +setValue(Int, notify)
        +stepValue(Int)
    }

    class TableColumn {
        <<struct>>
        +title : String
        +width : Width (fixed/flexible)
    }

    class TableView {
        +columns : [TableColumn]
        +rows : [[String]]
        +selectedIndex : Int?
        +onSelectionChanged : (Int?) -> Void
        +onActivate : (Int) -> Void
        +onSortRequested : (Int) -> Void
        +select(Int?, notify)
    }

    class TreeNode {
        +title : String
        +children : [TreeNode]
        +parent : TreeNode?
        +isExpanded : Bool
        +isExpandable : Bool
        +representedValue : Any?
        +addChild(TreeNode)
    }

    class FileSystemProvider {
        <<protocol>>
        +entries(at path) [FileSystemEntry]
    }

    class DirectoryTree {
        +rootPath : String
        +showsFiles : Bool
        +selectedPath : String?
        +selectedPathIsDirectory : Bool?
        +onSelectionChanged : (String?) -> Void
        +onActivate : (String) -> Void
        +setRoot(String)
        +reload()
        +expandRoot()
    }

    class Panel {
        +title : String
        +showsCloseButton : Bool
        +content : TUIView
        +onClose : () -> Void
    }

    class Dialog {
        +body : TUIView
        +buttons : [Button]
        +defaultButton : Button?
        +cancelButton : Button?
        +onDismiss : () -> Void
        +preferredSize : Size
        +addButton(title, isDefault, isCancel, action) Button
        +sizeToFit(in : Size)
    }

    class FileDialog {
        +mode : Mode (open/save/selectFolder)
        +chosenPath : String
        +suggestedName : String
        +onConfirm : (String) -> Void
    }

    class SplitView {
        +axis : StackView.Axis
        +first : TUIView
        +second : TUIView
        +currentDividerPosition : Int
        +minimumFirstLength : Int
        +minimumSecondLength : Int
        +onDividerMoved : (Int) -> Void
        +setDividerPosition(Int, notify)
    }

    class TreeView {
        +roots : [TreeNode]
        +selectedNode : TreeNode?
        +onSelectionChanged : (TreeNode?) -> Void
        +onActivate : (TreeNode) -> Void
        +select(TreeNode?, notify)
        +expand(TreeNode)
        +collapse(TreeNode)
    }

    class MenuItem {
        +title : String
        +keyEquivalent : KeyInput?
        +isEnabled : Bool
        +isSeparator : Bool
        +action : () -> Void
        +separator()$ MenuItem
    }

    class Menu {
        +title : String
        +items : [MenuItem]
        +addItem(title, keyEquivalent, action) MenuItem
        +addSeparator()
    }

    class MenuBar {
        +menus : [Menu]
        +isMenuOpen : Bool
        +addMenu(Menu)
        +openMenu(at : Int)
        +closeMenu()
    }

    class ColorPicker {
        +color : TerminalColor
        +onColorChanged : (TerminalColor) -> Void
        +setColor(TerminalColor, notify)
    }

    class RichText {
        +setMarkup(String)
        +setRenderable(RichRenderable)
    }

    class MarkdownView {
        +markdown : String
        +scrollOffset : Int
        +setMarkdown(String)
    }

    class SyntaxTextView {
        +text : String
        +language : String
        +showsLineNumbers : Bool
        +tabWidth : Int
        +lineCount : Int
        +cursorPosition : Point
        +onChanged : (String) -> Void
        +setText(String)
    }

    class PopUpButton {
        +items : [String]
        +style : ControlStyle
        +selectedIndex : Int?
        +isOpen : Bool
        +onSelectionChanged : (Int) -> Void
        +select(Int?, notify)
        +openPopup() / closePopup()
    }

    class ToggleButton {
        +title : String
        +isOn : Bool
        +onChange : (Bool) -> Void
        +setOn(Bool, notify)
        +toggle()
    }

    class StatusBar {
        +segments : [StatusBarSegment]
        +showsSeparators : Bool
        +addSegment(content, min, max, percentage)
    }

    class Divider {
        +axis : StackView.Axis
        +isConnected : Bool
        +isDraggable : Bool
        +onMoved : (Int) -> Void
    }

    class ComboBox {
        +text : String
        +items : [String]
        +isOpen : Bool
        +onChanged / onSubmit : (String) -> Void
        +onSelectionChanged : (Int) -> Void
        +setText(String)
    }

    class Slider {
        +value : Int
        +range : ClosedRange~Int~
        +step : Int
        +onValueChanged : (Int) -> Void
        +setValue(Int, notify)
    }

    class LevelIndicator {
        +value : Int
        +maximum : Int
        +style : capacity / rating
        +isEditable : Bool
        +onValueChanged : (Int) -> Void
        +setValue(Int, notify)
    }

    class PathControl {
        +path : String
        +onPathSelected : (String) -> Void
        +setPath(String)
        +prefixPath(to) String
    }

    class DisclosureGroup {
        +title : String
        +isExpanded : Bool
        +content : TUIView
        +onExpansionChanged : (Bool) -> Void
        +setExpanded(Bool, notify)
        +toggle()
    }

    class ProgressIndicator {
        +style : bar / spinner
        +doubleValue : Double
        +minValue / maxValue : Double
        +fractionCompleted : Double
        +showsPercentage : Bool
        +caption : String
        +spinnerFrames : [Character]
        +advance()
    }

    class DatePicker {
        +mode : date / time / calendar
        +date : Date
        +calendar : Calendar
        +onDateChanged : (Date) -> Void
        +setDate(Date, notify)
    }

    class ToolbarItem {
        +title : String
        +icon : Character?
        +isEnabled : Bool
        +action : () -> Void
    }

    class Toolbar {
        +items : [ToolbarItem]
        +style : ControlStyle
        +addItem(title, icon, isEnabled, action) ToolbarItem
    }

    class BrowserItem {
        <<struct>>
        +title : String
        +isExpandable : Bool
        +representedValue : Any?
    }

    class BrowserDataSource {
        <<protocol>>
        +browserRootItems(Browser) [BrowserItem]
        +browser(Browser, childrenOf) [BrowserItem]
    }

    class Browser {
        +columnWidth : Int
        +selectedItem : BrowserItem?
        +onSelectionChanged : (BrowserItem?) -> Void
        +onActivate : (BrowserItem) -> Void
        +reload()
    }

    class RowNavigationState {
        <<struct, pure>>
        +count : Int
        +selectedIndex : Int?
        +scrollOffset : Int
        +select(Int?) Bool
        +move(by) Bool
        +ensureSelectionVisible(height)
        +scroll(by, height)
    }

    class StackView {
        <<@MainActor>>
        +axis : Axis
        +spacing : Int
        +alignment : StackAlignment
        +insets : EdgeInsets
    }
    class HStack
    class VStack

    class AbsoluteLayout {
        <<@MainActor, no auto-layout>>
        +place(TUIView, at : Rect) TUIView
        +intrinsicContentSize : Size?
    }

    class GridView {
        +columns : [Track]
        +rows : [Track]
        +place(TUIView, column, row, spans)
        +setRow(Int, Track)
    }

    class Window {
        <<@MainActor, focus scope>>
        +firstResponder : TUIView?
        +isModal : Bool
        +makeFirstResponder(TUIView?) Bool
        +focusNext() Bool
        +focusPrevious() Bool
        +route(TerminalInput) Bool
    }

    class FloatingWindow {
        +title : String
        +content : TUIView
        +isMovable : Bool
        +isResizable : Bool
        +minimumWindowSize : Size
        +onCloseRequest : () -> Void
    }

    class Desktop {
        +fillCharacter : Character
        +fillStyle : CellStyle
    }

    TUIView <|-- Label
    TUIView <|-- Button
    TUIView <|-- TextField
    TUIView <|-- Checkbox
    TUIView <|-- RadioGroup
    TUIView <|-- ListView
    TUIView <|-- SegmentedControl
    TUIView <|-- TabView
    TUIView <|-- ScrollView
    TUIView <|-- Stepper
    TUIView <|-- TableView
    TUIView <|-- TreeView
    TUIView <|-- DirectoryTree
    TUIView <|-- Panel
    TUIView <|-- Desktop
    Window <|-- Dialog
    Window <|-- FloatingWindow
    FloatingWindow *-- Panel : chrome
    Dialog <|-- FileDialog
    TUIView <|-- SplitView
    TUIView <|-- MenuBar
    TUIView <|-- ColorPicker
    TUIView <|-- RichText
    TUIView <|-- MarkdownView
    TUIView <|-- SyntaxTextView
    TUIView <|-- PopUpButton
    TUIView <|-- ToggleButton
    TUIView <|-- StatusBar
    TUIView <|-- Divider
    TUIView <|-- ComboBox
    TUIView <|-- Slider
    TUIView <|-- LevelIndicator
    TUIView <|-- PathControl
    TUIView <|-- DisclosureGroup
    TUIView <|-- ProgressIndicator
    TUIView <|-- DatePicker
    TUIView <|-- Toolbar
    TUIView <|-- Browser
    ComboBox *-- TextField : editing
    TUIView <|-- StackView
    TUIView <|-- GridView
    TUIView <|-- AbsoluteLayout
    TUIView <|-- Window
    StackView <|-- HStack
    StackView <|-- VStack

    ListView *-- RowNavigationState : uses
    TableView *-- RowNavigationState : uses
    TreeView *-- RowNavigationState : uses
    Browser *-- RowNavigationState : per column
    Toolbar o-- ToolbarItem : items
    Button ..> ControlStyle : styled by
    PopUpButton ..> ControlStyle : styled by
    Toolbar ..> ControlStyle : styled by
    Browser o-- BrowserItem : rows
    Browser ..> BrowserDataSource : columns via
    BrowserDataSource <|.. FileSystemBrowserDataSource
    FileSystemBrowserDataSource ..> FileSystemProvider : lists via
    TableView *-- TableColumn : columns
    TreeView o-- TreeNode : roots
    TreeNode o-- TreeNode : children
    DirectoryTree *-- TreeView : composes
    DirectoryTree ..> FileSystemProvider : lists via
    Panel o-- TUIView : content
    Dialog *-- Panel : chrome
    Dialog o-- Button : actions
    FileDialog *-- DirectoryTree : browses
    SplitView o-- TUIView : first/second
    MenuBar o-- Menu : menus
    Menu o-- MenuItem : items
    ColorPicker *-- TabView : modes
    ColorPicker *-- Stepper : palette/rgb
    TabView o-- TUIView : content per tab
    ScrollView o-- TUIView : documentView

    note for RowNavigationState "Shared selection/scroll core\ndriving List, Table, and Tree."
    note for RichText "Bridges RichSwift content\n(markup, tables, panels, syntax)\ninto cells via SGRDecoder."
```

All Phase 6 controls are implemented, and all Phase 6B (Controls v2)
controls now appear in the diagram above — including `ProgressIndicator`,
`DatePicker`, `Toolbar`, and `Browser`. The diagram is the complete control
surface as of Controls v2.

### App-layer: the timer facility

A first-class TUIKit subsystem (not a control) — the framework's one timing
primitive, used by any control or app that acts over time (animation,
debounces, delays). It landed with `ProgressIndicator`'s spinner and will be
reused by the Phase 11 tooltip delay.

```mermaid
classDiagram
    direction LR

    class App {
        +addTimer(every, repeats, body) AppTimer
        +schedule(after, body) AppTimer
    }

    class AppTimer {
        +interval : Duration
        +repeats : Bool
        +isCancelled : Bool
        +cancel()
    }

    class TimerSource {
        <<protocol, Sendable>>
        +ticks(every) AsyncStream~Void~
    }

    class ClockTimerSource {
        <<Task.sleep; production>>
    }

    class ManualTimerSource {
        <<fire(); tests, zero wall-clock>>
        +fire()
        +streamCount : Int
    }

    App o-- AppTimer : owns
    App ..> TimerSource : ticks from
    TimerSource <|.. ClockTimerSource
    TimerSource <|.. ManualTimerSource

    note for TimerSource "Input and ticks merge into one\nAsyncStream in App.run — a tick\npresents a frame like a keypress.\nNever blocks; headless-scriptable."
```

See `Architecture.md` for how the run loop merges ticks with input.

## Planned (Controls v2 — PLAN Phase 6B) — COMPLETE

```mermaid
classDiagram
    direction TB

    class TUIView
    class TextField

    class ComboBox {
        +text : String
        +items : [String]
        +onChanged : (String) -> Void
        +onSubmit : (String) -> Void
        +onSelectionChanged : (Int) -> Void
    }

    class ProgressIndicator
    class Slider
    class DatePicker
    class LevelIndicator
    class Browser
    class PathControl
    class DisclosureGroup
    class Toolbar
    class ContextMenu

    TUIView <|-- ComboBox
    TUIView <|-- ProgressIndicator
    TUIView <|-- Slider
    TUIView <|-- DatePicker
    TUIView <|-- LevelIndicator
    TUIView <|-- Browser
    TUIView <|-- PathControl
    TUIView <|-- DisclosureGroup
    TUIView <|-- Toolbar
    ComboBox *-- TextField : editing
    StatusBar o-- StatusBarSegment : segments
```

Rev 2 (PLAN Phase 11): SearchField, Sheets, ImageView, TokenField,
Tooltips.

## Charts (REQUESTS R9–R11) and the highlighting seam (R8)

```mermaid
classDiagram
    direction TB

    class TUIView

    class ChartFidelity {
        <<enumeration>>
        blocks
        ascii
        braille
    }

    class Sparkline {
        +values : [Double]
        +fidelity : ChartFidelity
        +range : ClosedRange~Double~?
        +style : CellStyle?
    }

    class TimelineChart {
        +rows : [TimelineRow]
        +domain : ClosedRange~Double~?
        +fidelity : ChartFidelity
        +showsAxis : Bool
        +selectedRow : Int?
        +onSelectRow : (Int) -> Void
    }

    class TimelineRow {
        +label : String
        +segments : [Segment]
    }

    class LineChart {
        +series : [Series]
        +xDomain / yDomain : ClosedRange~Double~?
        +fidelity : ChartFidelity
        +yFormatter : (Double) -> String
        +showsLegend : Bool
    }

    class BarChart {
        +categories : [String]
        +series : [Series]
        +maximumValue : Double?
        +showsLegend : Bool
    }

    class PieChart {
        +slices : [Slice]
        +innerRadiusFraction : Double
        +showsLegend : Bool
    }

    class ScatterChart {
        +series : [Series]
        +xDomain / yDomain : ClosedRange~Double~?
        +showsLegend : Bool
    }

    TUIView <|-- Sparkline
    TUIView <|-- TimelineChart
    TUIView <|-- LineChart
    TUIView <|-- BarChart
    TUIView <|-- PieChart
    TUIView <|-- ScatterChart
    TimelineChart o-- TimelineRow : rows

    class SyntaxHighlighting {
        <<protocol>>
        +highlight(line, inout HighlightState) [HighlightSpan]
    }

    class SyntaxTextView {
        +language : String
        +highlighter : SyntaxHighlighting?
    }

    class HTMLHighlighter
    class JavaScriptHighlighter
    class CSSHighlighter

    SyntaxHighlighting <|.. HTMLHighlighter
    SyntaxHighlighting <|.. JavaScriptHighlighter
    SyntaxHighlighting <|.. CSSHighlighter
    SyntaxTextView --> SyntaxHighlighting : lines + carried state
    HTMLHighlighter --> JavaScriptHighlighter : script island
    HTMLHighlighter --> CSSHighlighter : style island

    note for Sparkline "Cells first, VTG optional:\nblocks default, ascii the floor,\nbraille opt-in (LineChart only).\nColours from theme slots."
```

Charts render on one rule — cells first, every glyph single-width, colours
from the `chartData` palette (theme-derived when unset) with per-series
overrides. The ActiveUI chart shapes all have TUI counterparts now:
`AUIBarMark`→BarChart, `AUISectorMark`→PieChart (donut included),
`AUIPointMark`→ScatterChart, `AUIAreaMark`→`LineChart.Series.fillsArea`,
`AUILineMark`→LineChart; the pie's cell disc is coarse by nature, so its
legend always carries the exact percentages. Long-press (no new class): `MouseInput.Action.longPress` +
`Button.onLongPress` + `ToolbarItem.longPressAction`, context menu fallback.

## Phase 16 — Control parity (Wave A)

```mermaid
classDiagram
    direction TB

    class TUIView
    class TextField
    class Button

    class SearchField {
        +field : TextField
        +text : String
        +placeholder : String
        +debounce : Duration?
        +onSearch : (String) -> Void
        +onCommit : (String) -> Void
        +setText(String)
        +clear()
    }

    class Link {
        +title : String
        +url : String
        +presentation : Presentation
        +onOpen : ((String) -> Void)?
        +open()
        +help(anchor, baseURL)$ Link
    }

    class PasteButton {
        +button : Button
        +pasteboard : Pasteboard?
        +onPaste : (String) -> Void
        +onEmpty : () -> Void
        +paste()
    }

    class RangeSlider {
        +lowerValue : Int
        +upperValue : Int
        +values : ClosedRange~Int~
        +range : ClosedRange~Int~
        +step : Int
        +minimumGap : Int
        +activeThumb : Thumb
        +onValuesChanged : (ClosedRange~Int~) -> Void
        +setValues(ClosedRange~Int~, notify)
        +activate(Thumb)
    }

    class Slider {
        +tickMarks : Int
        +snapsToTicks : Bool
    }

    class StatusBar {
        +flashText : String?
        +flash(String, for)
        +clearFlash()
    }

    class StatusBarSegment {
        +priority : Int
    }

    class ViewThatFits {
        +axis : Axis
        +candidates : [TUIView]
        +chosenIndex : Int?
        +onChoiceChanged : (Int) -> Void
    }

    class PageView {
        +pages : [TUIView]
        +currentIndex : Int
        +showsControls : Bool
        +onPageChanged : (Int) -> Void
        +setCurrentIndex(Int, notify)
        +next() Bool
        +previous() Bool
    }

    class Accordion {
        +mode : Mode
        +sections : [DisclosureGroup]
        +onSectionChanged : (Int, Bool) -> Void
        +addSection(String, content, isExpanded) DisclosureGroup
        +setExpanded(Int, Bool, notify)
    }

    class Navigator {
        +levels : [Level]
        +depth : Int
        +topView : TUIView
        +title : String
        +showsHeader : Bool
        +backTitle : String
        +onDepthChanged : (Int) -> Void
        +push(TUIView, title)
        +pop() Bool
        +popToRoot()
    }

    class Canvas {
        +drawCells : ((Painter, Rect) -> Void)?
        +drawChrome : ((ChromeSurface, Rect) -> Void)?
        +placeholderText : String
        +naturalSize : Size?
        +redraw()
    }

    TUIView <|-- SearchField
    TUIView <|-- Link
    TUIView <|-- PasteButton
    TUIView <|-- RangeSlider
    TUIView <|-- Navigator
    TUIView <|-- Canvas
    TUIView <|-- ViewThatFits
    TUIView <|-- PageView
    TUIView <|-- Accordion
    Accordion o-- DisclosureGroup : sections
    SearchField *-- TextField : editing
    PasteButton *-- Button : pressing
```

## Phase 16 — Control parity (Wave B)

```mermaid
classDiagram
    direction TB

    class TUIView
    class Navigator
    class Button
    class DisclosureGroup

    class Wizard {
        +steps : [Step]
        +currentIndex : Int
        +currentStep : Step
        +navigator : Navigator
        +backButton : Button
        +nextButton : Button
        +isOnFinalStep : Bool
        +onFinish : () -> Void
        +onStepChanged : (Int) -> Void
        +goNext() Bool
        +goBack() Bool
    }

    class Gauge {
        +value : Double
        +range : ClosedRange~Double~
        +style : Style
        +label : String
        +warningThreshold : Double?
        +criticalThreshold : Double?
        +fraction : Double
        +setValue(Double)
        +fillColor(ResolvedTheme) TerminalColor
    }

    class LevelIndicator {
        +warningLevel : Int?
        +criticalLevel : Int?
        +fillColor(ResolvedTheme) TerminalColor
    }

    class FlowStack {
        +spacing : Int
        +lineSpacing : Int
        +insets : EdgeInsets
        +defaultChildWidth : Int
    }

    class Form {
        +init(labelWidth, spacing, FormBuilder)
    }
    class Section {
        +init(String, FormBuilder)
    }

    class Matrix {
        +titles : [String]
        +columns : Int
        +mode : Mode
        +selected : Set~Int~
        +cursor : Int
        +onSelectionChanged : (Set~Int~) -> Void
        +onActivate : (Int) -> Void
        +select(Set~Int~, notify)
    }

    class Toolbox {
        +tools : [Tool]
        +axis : Axis
        +showsCaptions : Bool
        +selectedIndex : Int
        +onSelectionChanged : (Int) -> Void
        +select(Int, notify)
    }

    class TokenField {
        +tokens : [String]
        +field : TextField
        +placeholder : String
        +onTokensChanged : ([String]) -> Void
        +setTokens([String], notify)
        +mint(String)
        +remove(at)
        +removeLast()
    }

    class CompletionList {
        +field : TextField?
        +items : [String]
        +filter : (String, String) -> Bool
        +maximumVisible : Int
        +matches : [String]
        +highlightedIndex : Int
        +onAccept : ((String) -> Void)?
        +accept(Int)
        +hide()
    }

    class TextField {
        +onDeleteBackwardAtStart : () -> Void
    }

    TUIView <|-- Wizard
    TUIView <|-- Gauge
    TUIView <|-- FlowStack
    TUIView <|-- Matrix
    TUIView <|-- Toolbox
    TUIView <|-- TokenField
    TUIView <|-- CompletionList
    TokenField *-- TextField : tail
    CompletionList --> TextField : follows
    Wizard *-- Navigator : steps
    Wizard *-- Button : footer
    Form o-- Section : headers
```
