import Foundation
import TUIKit

/// Bordered, titled panel used by the gallery's view-tree section.
@MainActor
final class DemoPanel: TUIView {
    var title: String
    var background: TerminalColor

    /// Natural size, when the panel should be fixed rather than flexible.
    var preferredSize: Size?

    override var intrinsicContentSize: Size? {
        preferredSize
    }

    init(frame: Rect = .zero, title: String, background: TerminalColor) {
        self.title = title
        self.background = background
        super.init(frame: frame)
    }

    override func draw(_ painter: Painter) {
        let chrome = CellStyle(foreground: .named(.brightWhite), background: background)

        painter.fill(bounds, with: TerminalCell(character: " ", style: CellStyle(background: background)))
        painter.drawBox(bounds, style: chrome)
        painter.write(" \(title) ", at: Point(x: 2, y: 0), style: CellStyle(
            foreground: .named(.brightWhite),
            background: background,
            flags: .bold
        ))
    }
}

/// Prints the static capability gallery.
@MainActor
func runStaticGallery() {

/// Prints a section heading.
func heading(_ title: String) {
    let rule = String(repeating: "─", count: title.count + 2)
    print("\n┌\(rule)┐")
    print("│ \(title) │")
    print("└\(rule)┘")
}

/// Prints a buffer to the terminal through the ANSI encoder.
func show(_ buffer: CellBuffer) {
    for line in ANSIEncoder.encode(buffer) {
        print(line)
    }
}

print("TUIKit \(TUIKitInfo.version) — capability demo")

// MARK: - Named Colors

heading("Named colors (foreground and background)")

var colors = CellBuffer(size: Size(width: 68, height: 2))
var x = 0

for color in TerminalColor.NamedColor.allCases {
    let label = " " + String(color.rawValue.prefix(2)) + " "
    colors.write(label, at: Point(x: x, y: 0), style: CellStyle(foreground: .named(color)))
    colors.write(label, at: Point(x: x, y: 1), style: CellStyle(background: .named(color)))
    x += label.count
}

show(colors)

// MARK: - Emphasis Flags

heading("Emphasis flags")

var emphasis = CellBuffer(size: Size(width: 68, height: 1))
let samples: [(String, CellFlags)] = [
    ("bold", .bold),
    ("dim", .dim),
    ("italic", .italic),
    ("underline", .underline),
    ("inverse", .inverse),
    ("strike", .strikethrough),
]
x = 0

for (name, flag) in samples {
    emphasis.write(name, at: Point(x: x, y: 0), style: CellStyle(flags: flag))
    x += name.count + 2
}

show(emphasis)

// MARK: - Buffer Composition

heading("Buffer composition (fill, clip, overlap)")

var canvas = CellBuffer(size: Size(width: 40, height: 7))

// A filled backdrop...
canvas.fill(
    Rect(x: 1, y: 1, width: 24, height: 5),
    with: TerminalCell(character: "░", style: CellStyle(foreground: .named(.blue)))
)

// ...an overlapping panel...
canvas.fill(
    Rect(x: 14, y: 2, width: 20, height: 4),
    with: TerminalCell(character: " ", style: CellStyle(background: .named(.brightBlack)))
)

canvas.write(
    " TUIKit ",
    at: Point(x: 16, y: 3),
    style: CellStyle(foreground: .named(.brightWhite), background: .named(.blue), flags: .bold)
)

// ...and a write that runs off the right edge to show clipping.
canvas.write(
    "this text is clipped at the buffer edge →→→→→→→→",
    at: Point(x: 20, y: 5),
    style: CellStyle(foreground: .named(.yellow))
)

show(canvas)

// MARK: - RGB Gradient

heading("24-bit color (terminals that support it)")

var gradient = CellBuffer(size: Size(width: 64, height: 1))

for step in 0..<64 {
    let red = UInt8(255 - (step * 4))
    let blue = UInt8(step * 4)
    gradient[Point(x: step, y: 0)] = TerminalCell(
        character: "█",
        style: CellStyle(foreground: .rgb(red: red, green: 64, blue: blue))
    )
}

show(gradient)

// MARK: - TUIView Tree (Phase 3)

heading("View tree — local coordinates & clipping")

let window = DemoPanel(
    frame: Rect(x: 0, y: 0, width: 46, height: 9),
    title: "Window",
    background: .named(.blue)
)

let panel = DemoPanel(
    frame: Rect(x: 3, y: 2, width: 27, height: 6),
    title: "Panel",
    background: .named(.brightBlack)
)

// This child extends past its parent's right edge on purpose — the painter
// clips it at the panel boundary, proving the clipping contract visually.
let clipped = DemoPanel(
    frame: Rect(x: 17, y: 2, width: 18, height: 3),
    title: "Clipped",
    background: .named(.red)
)

window.addSubview(panel)
panel.addSubview(clipped)

show(SceneRenderer(root: window).render(size: Size(width: 46, height: 9)))
print("(the red panel is cut off at its parent's edge — clipping contract)")

// MARK: - Layout (Phase 5)

heading("Layout — stacks & grid")

// A classic app shell: fixed sidebar + flexible content, over a status bar,
// laid out entirely by VStack/HStack — no hand-computed frames.
let shell = VStack(frame: Rect(x: 0, y: 0, width: 46, height: 8), spacing: 0)
let mainRow = HStack(spacing: 1)

let sidebar = DemoPanel(title: "Side", background: .named(.magenta))
sidebar.preferredSize = Size(width: 10, height: 1)

mainRow.addSubview(sidebar)
mainRow.addSubview(DemoPanel(title: "Content", background: .named(.blue)))
mainRow.addSubview(DemoPanel(title: "Aside", background: .named(.cyan)))

let status = DemoPanel(title: "Status", background: .named(.brightBlack))
status.preferredSize = Size(width: 1, height: 3)

shell.addSubview(mainRow)
shell.addSubview(status)

show(SceneRenderer(root: shell).render(size: Size(width: 46, height: 8)))
print("(fixed 10-cell sidebar; Content/Aside split the leftover; fixed status)")

heading("Layout — grid with spans")

let grid = GridView(
    columns: [.fixed(8), .flexible(2), .flexible(1)],
    frame: Rect(x: 0, y: 0, width: 46, height: 7),
    columnSpacing: 1,
    rowSpacing: 0
)

let banner = DemoPanel(title: "Header spans all columns", background: .named(.blue))
grid.place(banner, column: 0, row: 0, columnSpan: 3)
grid.setRow(0, .fixed(3))
grid.place(DemoPanel(title: "8", background: .named(.red)), column: 0, row: 1)
grid.place(DemoPanel(title: "2fr", background: .named(.green)), column: 1, row: 1)
grid.place(DemoPanel(title: "1fr", background: .named(.yellow)), column: 2, row: 1)
grid.setRow(1, .flexible())

show(SceneRenderer(root: grid).render(size: Size(width: 46, height: 7)))
print("(fixed 8-cell column, then flexible columns weighted 2:1)")

// MARK: - Controls (Phase 6)

heading("Controls — first set (static render; --interactive for live)")

let controlsWindow = Window(frame: Rect(x: 0, y: 0, width: 46, height: 14))
let controlsForm = VStack(spacing: 1, insets: EdgeInsets(all: 1))
controlsForm.anchors = .fill()

let galleryField = TextField(text: "Bobby")
let galleryRow = HStack(spacing: 1)
galleryRow.addSubview(Label("Name:", style: CellStyle(flags: .bold)))
galleryRow.addSubview(galleryField)

let galleryButtons = HStack(spacing: 2)
let galleryOK = Button("OK")
galleryButtons.addSubview(galleryOK)
galleryButtons.addSubview(Button("Cancel"))
galleryButtons.addSubview(TUIView())

controlsForm.addSubview(galleryRow)
controlsForm.addSubview(Checkbox("Wrap lines", isChecked: true))
controlsForm.addSubview(RadioGroup(["Fast", "Balanced", "Accurate"], selectedIndex: 1))
controlsForm.addSubview(ListView(items: ["Document-1.txt", "Document-2.txt"]))
controlsForm.addSubview(Stepper(value: 42, in: 0...100))
controlsForm.addSubview(galleryButtons)

controlsWindow.addSubview(controlsForm)
controlsWindow.makeFirstResponder(galleryOK)

show(SceneRenderer(root: controlsWindow).render(size: Size(width: 46, height: 14)))
print("(the focused OK button renders inverted)")

heading("ScrollView — viewport, offset, indicator")

let scrollDocument = VStack(spacing: 0)

for row in 0..<12 {
    scrollDocument.addSubview(Label("row \(row) — only the viewport's slice of me is visible"))
}

let galleryScroll = ScrollView(document: scrollDocument)
galleryScroll.frame = Rect(x: 0, y: 0, width: 46, height: 5)
galleryScroll.setOffset(Point(x: 0, y: 4))

show(SceneRenderer(root: galleryScroll).render(size: Size(width: 46, height: 5)))
print("(scrolled to row 4 of 12; the right column is the indicator)")

heading("TableView & TreeView — the row-navigation family")

let galleryTable = TableView(
    columns: [TableColumn("Name"), TableColumn("KB", width: .fixed(4))],
    rows: [["Button.swift", "4"], ["ListView.swift", "9"], ["Painter.swift", "5"]]
)
galleryTable.select(1)
galleryTable.frame = Rect(x: 0, y: 0, width: 46, height: 4)

show(SceneRenderer(root: galleryTable).render(size: Size(width: 46, height: 4)))

let galleryRoot = TreeNode("Sources", children: [
    TreeNode("Controls", children: [TreeNode("Button.swift")]),
    TreeNode("TUIKit.swift"),
])
let galleryTree = TreeView(roots: [galleryRoot])
galleryTree.expand(galleryRoot)
galleryTree.expand(galleryRoot.children[0])
galleryTree.frame = Rect(x: 0, y: 0, width: 46, height: 4)

show(SceneRenderer(root: galleryTree).render(size: Size(width: 46, height: 4)))
print("(one selection/scroll core drives List, Table, and Tree)")

heading("Panel & Dialog — window chrome and modals")

let galleryPanel = TUIKit.Panel("Inspector")   // qualified: RichSwift also has a Panel
galleryPanel.showsCloseButton = true
let panelBody = Label("Content lives inside the border")
panelBody.anchors = .fill()
galleryPanel.content.addSubview(panelBody)
galleryPanel.frame = Rect(x: 0, y: 0, width: 46, height: 4)

show(SceneRenderer(root: galleryPanel).render(size: Size(width: 46, height: 4)))

let galleryDialog = Dialog(title: "Delete file?", message: "This cannot be undone.")
galleryDialog.addButton("&Cancel", isCancel: true)
galleryDialog.addButton("&Delete", isDefault: true, isDestructive: true)
galleryDialog.frame = Rect(origin: .zero, size: galleryDialog.preferredSize)

show(SceneRenderer(root: galleryDialog).render(size: galleryDialog.frame.size))
print("(present with app.present — the window stack makes it modal)")

heading("RichText — RichSwift content rendered into cells")

let richBanner = RichText(markup: "[bold magenta]RichSwift[/] markup, [green]tables[/], and [cyan]syntax[/] compose into TUIKit views")
richBanner.frame = Rect(x: 0, y: 0, width: 70, height: 1)
show(SceneRenderer(root: richBanner).render(size: Size(width: 70, height: 1)))

var buildMatrix = Table(title: "Build Matrix")
buildMatrix.addColumn("Platform", style: Style("bold cyan"))
buildMatrix.addColumn("Status")
buildMatrix.addRow("macOS", "[green]passing[/]")
buildMatrix.addRow("Linux", "[yellow]expected[/]")

let richTable = RichText(renderable: buildMatrix)
richTable.frame = Rect(x: 0, y: 0, width: 46, height: 7)
show(SceneRenderer(root: richTable).render(size: Size(width: 46, height: 7)))

let snippet = RichText(renderable: Syntax("let answer = 42  // the usual", language: "swift", lineNumbers: true))
snippet.frame = Rect(x: 0, y: 0, width: 46, height: 1)
show(SceneRenderer(root: snippet).render(size: Size(width: 46, height: 1)))
print("(SyntaxTextView makes this editable — see the Code tab, --interactive)")

// MARK: - What's Next

heading("Controls v1 complete")

print("""
All Phase 6 controls have landed. Next up: styling & theming (Phase 7),
demo polish (Phase 8), and the tutorial (Phase 9).

Live demos:  swift run TUIKitDemo --interactive   (declarative + manual windows)
             swift run TUIKitDemo --events        (driver event viewer)
""")
}
