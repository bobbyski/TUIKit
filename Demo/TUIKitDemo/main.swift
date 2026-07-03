import Foundation
import TUIKit   // re-exports RichSwift (Markup, Table, Syntax, …)

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

/// Full-screen root window that draws only its top row — the menu bar
/// strip. Everything below stays desktop, with floating windows overlapping
/// freely; menu dropdowns still open below the bar because they are this
/// window's subviews.
@MainActor
final class MenuBarWindow: Window {
    var onQuit: () -> Void = {}

    /// While one of its menus is open, Esc closes the menu instead of
    /// quitting.
    weak var menuBar: MenuBar?

    /// Only the bar row gets chrome; the desktop shows through the rest.
    override func draw(_ painter: Painter) {
        painter.fill(
            Rect(x: 0, y: 0, width: bounds.size.width, height: 1),
            with: .blank
        )
    }

    /// Claim only the bar row and open dropdowns; everywhere else is
    /// click-through, so clicks reach the floating windows behind.
    override func hitTest(_ point: Point) -> (view: View, local: Point)? {
        guard let hit = super.hitTest(point) else {
            return nil
        }

        if hit.view === self, point.y > 0 {
            return nil
        }

        return hit
    }

    /// Esc quits from anywhere via the hot-key pass (before focused views),
    /// unless a menu is open — then the dropdown handles it.
    override func handleHotKey(_ key: KeyInput) -> Bool {
        if key.key == .escape, key.modifiers.isEmpty {
            if menuBar?.isMenuOpen == true {
                return false
            }

            onQuit()
            return true
        }

        return false
    }
}

/// Interactive form dogfooding every Phase 6 control on the real driver:
/// Tab/Shift+Tab move focus, all controls answer keys and mouse, and the
/// status line narrates the semantic events the app receives.
@MainActor
func runFormDemo() async throws {
    let app = App(driver: ANSIDriver())

    // The desktop is the stylable background behind every window:
    // a solid middle gray.
    app.desktop.fillStyle = CellStyle(background: .rgb(red: 128, green: 128, blue: 128))
    app.desktop.theme = .dark   // inherited default for un-themed windows

    // Menu bar strip across the top (the root window).
    let menuWindow = MenuBarWindow()
    menuWindow.onQuit = { app.stop() }

    // All demo controls live in this floating window; closing it quits.
    let controls = FloatingWindow(
        title: "TUIKit Controls",
        frame: Rect(x: 3, y: 2, width: 74, height: 22)
    )
    controls.theme = .standard   // keeps the terminal look inside
    controls.onCloseRequest = { app.stop() }

    let status = Label("Click windows to focus them — drag titles to move, ◢ to resize.", style: CellStyle(flags: .dim))

    // The status line carries a style class so the CSS theme can target it.
    status.styleClasses = ["status"]

    // Whether Theme ▸ CSS is active (the Code tab's stylesheet applies live).
    var cssThemeActive = false

    let name = TextField(placeholder: "type a name, Return to submit")
    name.maximumSize = Size(width: 999, height: 1)
    name.onChanged = { status.text = "name draft: '\($0)'" }
    name.onSubmit = { status.text = "name submitted: '\($0)'" }

    let wrap = Checkbox("Wrap lines")
    wrap.onChange = { status.text = "wrap lines: \($0)" }

    let mode = RadioGroup(["Fast", "Balanced", "Accurate"], selectedIndex: 1)
    mode.onSelectionChanged = { status.text = "mode: \(mode.options[$0])" }

    let density = SegmentedControl(["Compact", "Cozy", "Roomy"], selectedIndex: 1)
    density.onSelectionChanged = { status.text = "density: \(density.segments[$0])" }

    let tabSize = Stepper(value: 4, in: 1...16)
    tabSize.onValueChanged = { status.text = "tab size: \($0)" }

    let accent = ColorPicker(color: .named(.cyan))
    accent.onColorChanged = { status.text = "accent color: \($0)" }

    let files = ListView(items: (1...30).map { "Document-\($0).txt" })
    files.onSelectionChanged = { index in
        status.text = index.map { "selected \(files.items[$0])" } ?? "selection cleared"
    }
    files.onActivate = { status.text = "OPENED \(files.items[$0])" }

    let summary = Button("Summary") {
        status.text = "name='\(name.text)' wrap=\(wrap.isChecked) mode=\(mode.selectedIndex ?? -1)"
    }
    let quit = Button("Quit") {
        let dialog = Dialog(title: "Quit?", message: "Leave the TUIKit demo?")
        dialog.addButton("Cancel", isCancel: true)
        dialog.addButton("Quit", isDefault: true) { app.stop() }
        dialog.onDismiss = { [weak dialog] in
            if let dialog {
                app.dismiss(dialog)
            }
        }
        dialog.sizeToFit(in: app.desktop.bounds.size)
        app.present(dialog)
        status.text = "modal dialog open — Esc cancels, Return confirms"
    }

    let open = Button("Open…") {
        let dialog = FileDialog(mode: .open, root: FileManager.default.currentDirectoryPath)
        dialog.onConfirm = { status.text = "chose: \($0)" }
        dialog.onDismiss = { [weak dialog] in
            if let dialog {
                app.dismiss(dialog)
            }
        }
        dialog.sizeToFit(in: app.desktop.bounds.size)
        app.present(dialog)
    }

    let buttons = HStack(spacing: 2)
    buttons.addSubview(summary)
    buttons.addSubview(open)
    buttons.addSubview(quit)
    buttons.addSubview(View())   // flexible spacer keeps buttons leading

    let nameRow = HStack(spacing: 1)
    nameRow.addSubview(Label("Name:", style: CellStyle(flags: .bold)))
    nameRow.addSubview(name)

    // "Form" tab content: the input controls.
    let formTab = VStack(spacing: 1, insets: EdgeInsets(all: 1))
    formTab.addSubview(nameRow)
    formTab.addSubview(wrap)
    formTab.addSubview(Label("Mode (radio):", style: CellStyle(flags: .bold)))
    formTab.addSubview(mode)
    formTab.addSubview(Label("Density (segmented):", style: CellStyle(flags: .bold)))
    formTab.addSubview(density)

    let stepperRow = HStack(spacing: 1)
    stepperRow.addSubview(Label("Tab size (stepper):", style: CellStyle(flags: .bold)))
    stepperRow.addSubview(tabSize)
    stepperRow.addSubview(View())   // flexible spacer keeps the row leading
    formTab.addSubview(stepperRow)

    formTab.addSubview(Label("Accent (color picker):", style: CellStyle(flags: .bold)))
    formTab.addSubview(accent)

    formTab.addSubview(buttons)
    formTab.addSubview(View())   // spacer pushes content to the top

    // "Files" tab content: the scrolling list and a real directory browser.
    let browser = DirectoryTree(root: FileManager.default.currentDirectoryPath)
    browser.expandRoot()
    browser.onSelectionChanged = { path in
        status.text = path.map { "path: \($0)" } ?? "path cleared"
    }
    browser.onActivate = { status.text = "OPENED \($0)" }

    let filesTab = VStack(spacing: 1, insets: EdgeInsets(all: 1))
    filesTab.addSubview(Label("Files (arrows, PgUp/PgDn, Return):", style: CellStyle(flags: .bold)))
    filesTab.addSubview(files)
    filesTab.addSubview(Label("Directory (lazy, real file system):", style: CellStyle(flags: .bold)))
    filesTab.addSubview(browser)

    // "Scroll" tab content: a document taller than any terminal, inside a
    // ScrollView (arrows/PgUp/PgDn/Home/End when focused; wheel anytime).
    let article = VStack(spacing: 0, insets: EdgeInsets(all: 1))
    article.addSubview(Label("TUIKit — scrollable document", style: CellStyle(flags: .bold)))
    article.addSubview(Label(""))

    for chapter in 1...12 {
        article.addSubview(Label("Chapter \(chapter)", style: CellStyle(flags: .underline)))

        for line in 1...4 {
            article.addSubview(Label("  \(chapter).\(line) The viewport clips; the offset translates."))
        }

        article.addSubview(Label(""))
    }

    let scroller = ScrollView(document: article)
    scroller.onOffsetChanged = { status.text = "scrolled to row \($0.y)" }

    let scrollTab = VStack(spacing: 1, insets: EdgeInsets(all: 1))
    scrollTab.addSubview(Label("Scroll (arrows, PgUp/PgDn, wheel):", style: CellStyle(flags: .bold)))
    scrollTab.addSubview(scroller)

    // "Data" tab content: a sortable table above a lazily-loading tree.
    var tableRows = [
        ("Button.swift", 4, "control"),
        ("ListView.swift", 9, "control"),
        ("Painter.swift", 5, "views"),
        ("StackView.swift", 10, "layout"),
        ("TableView.swift", 12, "control"),
        ("Window.swift", 7, "app"),
    ]

    let table = TableView(
        columns: [
            TableColumn("Name"),
            TableColumn("KB", width: .fixed(4)),
            TableColumn("Layer", width: .fixed(8)),
        ]
    )

    func reloadTable() {
        table.rows = tableRows.map { [$0.0, "\($0.1)", $0.2] }
    }

    reloadTable()
    table.onSelectionChanged = { row in
        status.text = row.map { "table row: \(tableRows[$0].0)" } ?? "table selection cleared"
    }
    table.onActivate = { status.text = "OPENED \(tableRows[$0].0)" }
    table.onSortRequested = { column in
        switch column {
        case 0: tableRows.sort { $0.0 < $1.0 }
        case 1: tableRows.sort { $0.1 < $1.1 }
        default: tableRows.sort { $0.2 < $1.2 }
        }

        reloadTable()
        status.text = "sorted by \(table.columns[column].title)"
    }

    let sources = TreeNode("Sources", childProvider: {
        [
            TreeNode("Controls", children: tableRows.map { TreeNode($0.0) }),
            TreeNode("TUIKit.swift"),
        ]
    })
    let docs = TreeNode("Docs", children: [
        TreeNode("Architecture.md"),
        TreeNode("ControlsUML.md"),
    ])

    let tree = TreeView(roots: [sources, docs])
    tree.onSelectionChanged = { node in
        status.text = node.map { "tree node: \($0.title)" } ?? "tree selection cleared"
    }
    tree.onActivate = { status.text = "OPENED \($0.title)" }

    let tableSection = VStack(spacing: 1)
    tableSection.addSubview(Label("Table (click headers to sort):", style: CellStyle(flags: .bold)))
    tableSection.addSubview(table)

    let treeSection = VStack(spacing: 1)
    treeSection.addSubview(Label("Tree (←/→ disclose, lazy Sources):", style: CellStyle(flags: .bold)))
    treeSection.addSubview(tree)

    let dataSplit = SplitView(axis: .vertical, first: tableSection, second: treeSection)
    dataSplit.minimumFirstLength = 4
    dataSplit.minimumSecondLength = 4
    dataSplit.onDividerMoved = { status.text = "split divider at row \($0)" }

    let dataTab = VStack(spacing: 1, insets: EdgeInsets(all: 1))
    dataTab.addSubview(Label("SplitView: drag the ─ divider, or focus it and use ↑/↓", style: CellStyle(flags: .bold)))
    dataTab.addSubview(dataSplit)

    // "Code" tab content: the syntax editor, holding this window's
    // stylesheet. With Theme ▸ CSS active, edits re-style the window live.
    let editor = SyntaxTextView(
        text: """
        /* TUIKit stylesheet — pick Theme > CSS,
           then edit me and watch the window restyle */
        Panel { border: rounded; border-color: brightCyan; }
        .status { color: brightCyan; }
        Button { bold: true; }
        TableView { header-color: brightYellow;
                    selection-background: #aa5500; }
        ListView { selection-background: #2266aa;
                   selection-color: brightWhite; }
        TextField:focused { underline: true; }
        """,
        language: "css"
    )
    editor.onChanged = { source in
        if cssThemeActive {
            controls.styleSheet = StyleSheet(source)
            status.text = "CSS re-applied — \(editor.lineCount) lines"
        } else {
            status.text = "editing — \(editor.lineCount) lines (Theme ▸ CSS applies this)"
        }
    }

    let codeTab = VStack(spacing: 1, insets: EdgeInsets(all: 1))
    codeTab.addSubview(RichText(markup: "[bold]SyntaxTextView[/] — the window's [cyan]stylesheet[/]; live with Theme ▸ CSS"))
    codeTab.addSubview(editor)

    // "Docs" tab content: a scrolling markdown reader.
    let docsView = MarkdownView(markdown: """
    # TUIKit

    A terminal UI framework with **AppKit bones** and `RichSwift` blood. \
    This paragraph is long on purpose so the view can show off soft \
    word-wrapping at whatever width the terminal happens to be.

    ## Controls
    - Buttons, fields, checkboxes, radios, steppers
    - Lists, tables, trees, a real directory browser
    - Menus, dialogs, split views, color pickers

    > Scroll me: arrows and PgUp/PgDn while focused, wheel anytime.

    ```swift
    let app = App(driver: ANSIDriver())
    try await app.run(window)
    ```
    """)

    let docsTab = VStack(spacing: 1, insets: EdgeInsets(all: 1))
    docsTab.addSubview(Label("MarkdownView (read-only, wraps to width):", style: CellStyle(flags: .bold)))
    docsTab.addSubview(docsView)

    // The form scrolls vertically so every control stays reachable on
    // small screens; the document reflows to the viewport width.
    let formScroll = ScrollView(document: formTab)
    formScroll.fitsDocumentWidth = true

    let tabs = TabView()
    tabs.addTab("Form", content: formScroll)
    tabs.addTab("Files", content: filesTab)
    tabs.addTab("Scroll", content: scrollTab)
    tabs.addTab("Data", content: dataTab)
    tabs.addTab("Code", content: codeTab)
    tabs.addTab("Docs", content: docsTab)
    tabs.onSelectionChanged = { status.text = "tab: \(tabs.title(at: $0) ?? "?")" }
    // Fill the controls window, leaving the bottom row for status.
    tabs.anchors = AnchorSet(leading: 0, trailing: 0, top: 0, bottom: 1)

    // Status pinned to the bottom row of the controls window.
    status.anchors = AnchorSet(leading: 0, trailing: 0, bottom: 0, height: 1)

    // Menu bar on the top row: hot keys work from anywhere (^O, ^Q).
    let fileMenu = Menu("File")
    fileMenu.addItem("Open…", keyEquivalent: KeyInput(key: .character("o"), modifiers: .control)) {
        open.activate()
    }
    fileMenu.addSeparator()
    fileMenu.addItem("Quit", keyEquivalent: KeyInput(key: .character("q"), modifiers: .control)) {
        quit.activate()
    }

    let viewMenu = Menu("View")

    for (index, name) in ["Form", "Files", "Scroll", "Data", "Code", "Docs"].enumerated() {
        viewMenu.addItem(name) {
            tabs.select(index, notify: true)
        }
    }

    // Overlapping, non-modal windows: spawn floats, click between them.
    var floatingWindows: [FloatingWindow] = []
    var floatingCount = 0

    let windowMenu = Menu("Window")
    windowMenu.addItem("New Floating Window", keyEquivalent: KeyInput(key: .character("n"), modifiers: .control)) {
        floatingCount += 1
        let id = floatingCount
        let pick = TUIKit.Theme.builtIn[id % TUIKit.Theme.builtIn.count]

        let float = FloatingWindow(
            title: "Float \(id) — \(pick.name)",
            frame: Rect(x: 4 + (id % 5) * 6, y: 2 + (id % 4) * 2, width: 36, height: 10)
        )
        float.theme = pick.theme
        float.onCloseRequest = { [weak float] in
            if let float {
                floatingWindows.removeAll { $0 === float }
                app.dismiss(float)
            }
        }

        let list = ListView(items: (1...8).map { "Row \($0) of \(pick.name)" })
        list.onSelectionChanged = { index in
            status.text = index.map { "float \(id): row \($0 + 1)" } ?? "float \(id)"
        }

        let column = VStack(spacing: 1)
        column.addSubview(Label("Click another window to activate it.", style: CellStyle(flags: .dim)))
        column.addSubview(list)
        column.anchors = .fill()
        float.content.addSubview(column)

        floatingWindows.append(float)
        app.present(float)
        float.makeFirstResponder(list)
        status.text = "float \(id): drag the title to move, ◢ to resize, click windows to switch"
    }
    windowMenu.addItem("Activate Controls Window") {
        app.activate(controls)
        status.text = "controls window is key"
    }
    windowMenu.addItem("Raise All Floating Windows") {
        for float in floatingWindows {
            app.activate(float)
        }

        status.text = floatingWindows.isEmpty
            ? "no floating windows — File ▸ New Floating Window"
            : "raised \(floatingWindows.count) floating window(s) above the main window"
    }

    // Live theme switching for the controls window.
    let themeMenu = Menu("Theme")

    for (name, theme) in TUIKit.Theme.builtIn {   // qualified: RichSwift also has a Theme
        themeMenu.addItem(name) {
            cssThemeActive = false
            controls.styleSheet = nil
            controls.theme = theme
            status.text = "theme: \(name)"
        }
    }

    themeMenu.addSeparator()
    themeMenu.addItem("CSS") {
        cssThemeActive = true
        controls.theme = .standard
        controls.styleSheet = StyleSheet(editor.text)
        tabs.select(4, notify: true)   // jump to the Code tab: the source
        status.text = "theme: CSS — edit the stylesheet here, changes apply live"
    }

    let menuBar = MenuBar()
    menuBar.addMenu(fileMenu)
    menuBar.addMenu(viewMenu)
    menuBar.addMenu(windowMenu)
    menuBar.addMenu(themeMenu)
    menuBar.anchors = AnchorSet(leading: 0, top: 0, height: 1)

    // Assemble: controls in their floating window, the menu bar in the
    // root strip window.
    controls.content.addSubview(tabs)
    controls.content.addSubview(status)
    controls.makeFirstResponder(tabs)   // ←/→ switches tabs; Tab enters content

    menuWindow.addSubview(menuBar)
    menuWindow.menuBar = menuBar
    menuWindow.makeFirstResponder(menuBar)

    // The controls float goes onto the desktop first; running presents the
    // menu window above it. Click either to make it key.
    app.present(controls)

    do {
        try await app.run(menuWindow)
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
    var onQuit: () -> Void = {} {
        didSet {
            exitButton.onActivate = onQuit
        }
    }

    /// Clickable exit — anchored to the top-right of the title bar.
    let exitButton = Button("Exit")

    private var events: [String] = []

    override init(frame: Rect = .zero) {
        super.init(frame: frame)
        exitButton.anchors = AnchorSet(trailing: 1, top: 0)
        addSubview(exitButton)
    }

    override func draw(_ painter: Painter) {
        let title = CellStyle(foreground: .named(.brightWhite), background: .named(.blue), flags: .bold)

        painter.fill(bounds, with: .blank)
        painter.fill(Rect(x: 0, y: 0, width: bounds.size.width, height: 1), with: TerminalCell(character: " ", style: title))
        painter.write(" TUIKit event viewer — q or the Exit button quits ", at: .zero, style: title)
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
galleryButtons.addSubview(View())

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
galleryDialog.addButton("Cancel", isCancel: true)
galleryDialog.addButton("Delete", isDefault: true)
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

Live demos:  swift run TUIKitDemo --interactive   (tabbed control form)
             swift run TUIKitDemo --events        (driver event viewer)
""")
}
