import TUIKit

// TUIKitDemo — the living gallery of TUIKit capabilities.
//
// Per the AICoding rules, this demo doubles as a tutorial: it should always
// read as the recommended way to use the public API, and it grows a section
// for each control as it lands so it can be used for eyeball testing.
//
// Modes:
//   swift run TUIKitDemo                 static gallery (cells/views/layout)
//   swift run TUIKitDemo --interactive   live control form (Phase 6)
//   swift run TUIKitDemo --events        live driver event viewer

if CommandLine.arguments.contains("--interactive") {
    try await runFormDemo()
} else if CommandLine.arguments.contains("--events") {
    try await runEventViewer()
} else {
    runStaticGallery()
}

/// Interactive form dogfooding every Phase 6 control on the real driver:
/// Tab/Shift+Tab move focus, all controls answer keys and mouse, and the
/// status line narrates the semantic events the app receives.
@MainActor
func runFormDemo() async throws {
    let app = App(driver: ANSIDriver())
    let window = Window()

    let status = Label("Tab moves focus — every change lands here.", style: CellStyle(flags: .dim))

    let name = TextField(placeholder: "type a name, Return to submit")
    name.maximumSize = Size(width: 999, height: 1)
    name.onChanged = { status.text = "name draft: '\($0)'" }
    name.onSubmit = { status.text = "name submitted: '\($0)'" }

    let wrap = Checkbox("Wrap lines")
    wrap.onChange = { status.text = "wrap lines: \($0)" }

    let mode = RadioGroup(["Fast", "Balanced", "Accurate"], selectedIndex: 1)
    mode.onSelectionChanged = { status.text = "mode: \(mode.options[$0])" }

    let files = ListView(items: (1...30).map { "Document-\($0).txt" })
    files.onSelectionChanged = { index in
        status.text = index.map { "selected \(files.items[$0])" } ?? "selection cleared"
    }
    files.onActivate = { status.text = "OPENED \(files.items[$0])" }

    let summary = Button("Summary") {
        status.text = "name='\(name.text)' wrap=\(wrap.isChecked) mode=\(mode.selectedIndex ?? -1)"
    }
    let quit = Button("Quit") { app.stop() }

    let buttons = HStack(spacing: 2)
    buttons.addSubview(summary)
    buttons.addSubview(quit)
    buttons.addSubview(View())   // flexible spacer keeps buttons leading

    let nameRow = HStack(spacing: 1)
    nameRow.addSubview(Label("Name:", style: CellStyle(flags: .bold)))
    nameRow.addSubview(name)

    let form = VStack(spacing: 1, insets: EdgeInsets(all: 1))
    form.anchors = .fill()
    form.addSubview(Label("TUIKit control form — Ctrl+C or Quit to exit", style: CellStyle(flags: .bold)))
    form.addSubview(nameRow)
    form.addSubview(wrap)
    form.addSubview(mode)
    form.addSubview(Label("Files (arrows, PgUp/PgDn, Return):", style: CellStyle(flags: .bold)))
    form.addSubview(files)   // flexible: takes the leftover height
    form.addSubview(status)
    form.addSubview(buttons)

    window.addSubview(form)
    window.makeFirstResponder(name)

    do {
        try await app.run(window)
    } catch {
        print("Interactive mode needs a real terminal (\(error)).")
        return
    }

    print("Restored terminal.")
}

/// Full-screen event viewer, now built the way real TUIKit apps are: a
/// `Window` subclass on an `App` run loop. Proves driver, decoder, view
/// system, responder routing, resize handling, and graceful stop together.
@MainActor
final class EventLogWindow: Window {
    var onQuit: () -> Void = {}

    private var events: [String] = []

    override func draw(_ painter: Painter) {
        let title = CellStyle(foreground: .named(.brightWhite), background: .named(.blue), flags: .bold)

        painter.fill(bounds, with: .blank)
        painter.fill(Rect(x: 0, y: 0, width: bounds.size.width, height: 1), with: TerminalCell(character: " ", style: title))
        painter.write(" TUIKit interactive demo — press q to quit ", at: .zero, style: title)
        painter.write(
            "window \(bounds.size.width)x\(bounds.size.height) — type, use arrows, click, scroll, resize",
            at: Point(x: 1, y: 2),
            style: CellStyle(foreground: .named(.brightBlack))
        )

        let visible = events.suffix(max(0, bounds.size.height - 5))

        for (index, line) in visible.enumerated() {
            painter.write(line, at: Point(x: 1, y: 4 + index))
        }
    }

    override func keyDown(_ key: KeyInput) -> Bool {
        if key.key == .character("q"), key.modifiers.isEmpty {
            onQuit()
            return true
        }

        log("key: \(key)")
        return true
    }

    override func mouseEvent(_ mouse: MouseInput) -> Bool {
        log("mouse: \(mouse)")
        return true
    }

    private func log(_ line: String) {
        events.append("\(events.count + 1). \(line)")
        setNeedsDisplay()
    }
}

/// Runs the interactive event viewer on the real terminal.
@MainActor
func runEventViewer() async throws {
    let app = App(driver: ANSIDriver())
    let window = EventLogWindow()

    window.onQuit = { app.stop() }

    do {
        try await app.run(window)
    } catch {
        print("Interactive mode needs a real terminal (\(error)).")
        return
    }

    print("Restored terminal.")
}

/// Bordered, titled panel used by the gallery's view-tree section.
@MainActor
final class DemoPanel: View {
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

print("TUIKit \(TUIKit.version) — capability demo")

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

// MARK: - View Tree (Phase 3)

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

let controlsWindow = Window(frame: Rect(x: 0, y: 0, width: 46, height: 12))
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
galleryButtons.addSubview(View())

controlsForm.addSubview(galleryRow)
controlsForm.addSubview(Checkbox("Wrap lines", isChecked: true))
controlsForm.addSubview(RadioGroup(["Fast", "Balanced", "Accurate"], selectedIndex: 1))
controlsForm.addSubview(ListView(items: ["Document-1.txt", "Document-2.txt"]))
controlsForm.addSubview(galleryButtons)

controlsWindow.addSubview(controlsForm)
controlsWindow.makeFirstResponder(galleryOK)

show(SceneRenderer(root: controlsWindow).render(size: Size(width: 46, height: 12)))
print("(the focused OK button renders inverted)")

// MARK: - Coming Soon

heading("Coming soon")

print("""
Remaining controls arrive through Phase 6: ScrollView, Window chrome,
MenuBar, Dialog, TableView, TreeView, SplitView, Stepper, color picker,
file dialogs, RichText (RichSwift), and SyntaxTextView.

Live demos:  swift run TUIKitDemo --interactive   (control form)
             swift run TUIKitDemo --events        (driver event viewer)
""")
}
