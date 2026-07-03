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
  structural views (`View`, `StackView`, `Window`).

## Diagram

```mermaid
classDiagram
    direction TB

    class View {
        <<@MainActor, base>>
        +frame : Rect
        +bounds : Rect
        +subviews : [View]
        +isHidden : Bool
        +anchors : AnchorSet?
        +intrinsicContentSize : Size?
        +minimumSize : Size
        +maximumSize : Size?
        +acceptsFirstResponder : Bool
        +isFirstResponder : Bool
        +addSubview(View)
        +draw(Painter)
        +layoutSubviews()
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

    class Button {
        +title : String
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
        +addTab(String, content : View)
        +select(Int, notify)
        +title(at : Int) String?
    }

    class ScrollView {
        +documentView : View?
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

    class GridView {
        +columns : [Track]
        +rows : [Track]
        +place(View, column, row, spans)
        +setRow(Int, Track)
    }

    class Window {
        <<@MainActor, focus scope>>
        +firstResponder : View?
        +makeFirstResponder(View?) Bool
        +focusNext() Bool
        +focusPrevious() Bool
        +route(TerminalInput) Bool
    }

    View <|-- Label
    View <|-- Button
    View <|-- TextField
    View <|-- Checkbox
    View <|-- RadioGroup
    View <|-- ListView
    View <|-- SegmentedControl
    View <|-- TabView
    View <|-- ScrollView
    View <|-- Stepper
    View <|-- StackView
    View <|-- GridView
    View <|-- Window
    StackView <|-- HStack
    StackView <|-- VStack

    ListView *-- RowNavigationState : uses
    TabView o-- View : content per tab
    ScrollView o-- View : documentView

    note for RowNavigationState "Shared selection/scroll core.\nFuture TableView & TreeView\nwill reuse this."
```

## Planned (Phase 6 remainder)

Not yet implemented; shown so the diagram tracks the design intent.

```mermaid
classDiagram
    direction TB

    class View
    class ListView
    class RowNavigationState

    class ScrollView
    class TableView {
        +columns : [Column]
        +rows : [[String]]
        +onSelectionChanged
    }
    class TreeView {
        +roots : [Node]
        +onSelectionChanged
    }
    class SplitView {
        +axis
        +dividerPosition : Int
    }
    class MenuBar
    class Dialog
    class ColorPicker {
        +color : TerminalColor
        +onChange
    }
    class RichText {
        +markup : String
    }
    class SyntaxTextView {
        +text : String
        +language : String
    }

    View <|-- TableView
    View <|-- TreeView
    View <|-- SplitView
    View <|-- MenuBar
    View <|-- ColorPicker
    View <|-- RichText
    ScrollView <|-- SyntaxTextView
    Window <|-- Dialog
    TableView *-- RowNavigationState : uses
    TreeView *-- RowNavigationState : uses
```
