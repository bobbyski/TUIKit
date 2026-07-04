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
//   swift run TUIKitDemo --interactive   declarative + manual example windows
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

    /// The menu row (top) and the global status row (bottom) get a solid
    /// backing; the desktop shows through everything between.
    override func draw(_ painter: Painter) {
        painter.fill(
            Rect(x: 0, y: 0, width: bounds.size.width, height: 1),
            with: .blank
        )
        painter.fill(
            Rect(x: 0, y: bounds.size.height - 1, width: bounds.size.width, height: 1),
            with: .blank
        )
    }

    /// Claim only the bar row and open dropdowns; everywhere else is
    /// click-through, so clicks reach the floating windows behind.
    override func hitTest(_ point: Point) -> (view: TUIView, local: Point)? {
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

/// Five panes carved by three draggable dividers. The layout is *derived*:
/// every pass positions panes from the current divider coordinates, and
/// drags update those coordinates — so dragged positions survive relayout,
/// the panes resize live, and junctions follow.
///
/// ```text
///   topLeft      │ topRight
///   ─────────────┼───────────────────
///   bottomLeft   │ bottomMid │ bottomRight
/// ```
@MainActor
final class PanesLayout: TUIView {
    var onDividerMoved: (String) -> Void = { _ in }

    private let across = Divider(axis: .horizontal)
    private let left = Divider(axis: .vertical)
    private let right = Divider(axis: .vertical)
    private let panes: [TUIView]

    // Divider coordinates; derived from ratios on first layout.
    private var acrossY = -1
    private var leftX = -1
    private var rightX = -1

    init(topLeft: TUIView, topRight: TUIView, bottomLeft: TUIView, bottomMiddle: TUIView, bottomRight: TUIView) {
        self.panes = [topLeft, topRight, bottomLeft, bottomMiddle, bottomRight]
        super.init(frame: .zero)

        for pane in panes {
            addSubview(pane)
        }

        // Dividers last: drawn over the panes and hit-tested first.
        for (divider, name) in [(across, "horizontal"), (left, "left"), (right, "right")] {
            divider.isDraggable = true
            addSubview(divider)
            divider.onMoved = { [weak self] position in
                self?.dividerMoved(name, to: position)
            }
        }
    }

    private func dividerMoved(_ name: String, to position: Int) {
        switch name {
        case "horizontal":
            acrossY = position

        case "left":
            leftX = position

        default:
            rightX = position
        }

        setNeedsLayout()
        onDividerMoved(name)
    }

    override func layoutSubviews() {
        let width = bounds.size.width
        let height = bounds.size.height

        guard width > 8, height > 4 else {
            return
        }

        if acrossY < 0 {
            acrossY = height * 2 / 5
            leftX = width / 3
            rightX = width * 2 / 3
        }

        // Clamp for window resizes.
        acrossY = min(max(1, acrossY), height - 2)
        leftX = min(max(1, leftX), width - 4)
        rightX = min(max(leftX + 2, rightX), width - 2)

        across.frame = Rect(x: 0, y: acrossY, width: width, height: 1)
        left.frame = Rect(x: leftX, y: 0, width: 1, height: height)
        right.frame = Rect(x: rightX, y: acrossY + 1, width: 1, height: height - acrossY - 1)

        let bottomY = acrossY + 1
        let bottomHeight = height - bottomY

        panes[0].frame = Rect(x: 0, y: 0, width: leftX, height: acrossY)
        panes[1].frame = Rect(x: leftX + 1, y: 0, width: width - leftX - 1, height: acrossY)
        panes[2].frame = Rect(x: 0, y: bottomY, width: leftX, height: bottomHeight)
        panes[3].frame = Rect(x: leftX + 1, y: bottomY, width: rightX - leftX - 1, height: bottomHeight)
        panes[4].frame = Rect(x: rightX + 1, y: bottomY, width: width - rightX - 1, height: bottomHeight)
    }
}

/// Interactive form dogfooding every Phase 6 control on the real driver:
/// Tab/Shift+Tab move focus, all controls answer keys and mouse, and the
/// status line narrates the semantic events the app receives.
@MainActor
func runFormDemo() async throws {
    let app = App(driver: ANSIDriver())
    app.desktop.fillStyle = CellStyle(background: .rgb(red: 128, green: 128, blue: 128))
    app.desktop.theme = .dark   // inherited default for un-themed windows

    // The MANUAL example: the original imperative demo, intact and repeatable —
    // every control wired by hand. The declarative example below mirrors it.
    func makeManualExample(index: Int) -> FloatingWindow {
        let controls = FloatingWindow(
            title: "Manual Example \(index)",
            frame: Rect(x: 3 + index * 4, y: 2 + index * 2, width: 74, height: 22)
        )
        controls.theme = .standard
        controls.onCloseRequest = { [weak controls] in
            if let controls { app.dismiss(controls) }   // close the window, not the app
        }

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

        // Right-click the list for a context menu.
        let fileActions = Menu("File Actions")
        fileActions.addItem("Open") {
            status.text = files.selectedIndex.map { "context: open \(files.items[$0])" } ?? "context: open"
        }
        fileActions.addItem("Rename…") { status.text = "context: rename" }
        fileActions.addSeparator()
        fileActions.addItem("Delete") { status.text = "context: delete (not really)" }
        files.contextMenu = fileActions

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
        buttons.addSubview(TUIView())   // flexible spacer keeps buttons leading

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
        stepperRow.addSubview(TUIView())   // flexible spacer keeps the row leading
        formTab.addSubview(stepperRow)

        formTab.addSubview(Label("Accent (color picker):", style: CellStyle(flags: .bold)))
        formTab.addSubview(accent)

        // Collapsible "Advanced" section: combo box, slider + level, rating.
        let fontCombo = ComboBox(items: ["Menlo", "Monaco", "SF Mono", "Fira Code"], placeholder: "font name")
        fontCombo.onSelectionChanged = { _ in status.text = "font: \(fontCombo.text)" }
        fontCombo.onSubmit = { status.text = "custom font: \($0)" }

        let speedLevel = LevelIndicator(value: 2, maximum: 5, style: .capacity)
        let speed = Slider(value: 40, in: 0...100, step: 5)
        speed.onValueChanged = { value in
            speedLevel.setValue((value + 10) / 20)
            status.text = "speed: \(value)"
        }

        let stars = LevelIndicator(value: 3, maximum: 5, style: .rating)
        stars.isEditable = true
        stars.onValueChanged = { status.text = "rating: \($0) star(s)" }

        let advancedStack = VStack(spacing: 1)

        for (title, control) in [("Font:", fontCombo as TUIView), ("Speed:", speed), ("Rating:", stars)] {
            let row = HStack(spacing: 1)
            row.addSubview(Label(title, style: CellStyle(flags: .bold)))
            row.addSubview(control)

            if control === speed {
                row.addSubview(speedLevel)
            }

            row.addSubview(TUIView())   // spacer
            advancedStack.addSubview(row)
        }

        let advanced = DisclosureGroup("Advanced (disclosure group)")
        advancedStack.anchors = .fill()
        advanced.content.addSubview(advancedStack)
        advanced.onExpansionChanged = { status.text = $0 ? "advanced options revealed" : "advanced options tucked away" }
        formTab.addSubview(advanced)

        formTab.addSubview(buttons)
        formTab.addSubview(TUIView())   // spacer pushes content to the top

        // "Files" tab content: the scrolling list, a breadcrumb path bar, and
        // a real directory browser (selection updates the crumbs).
        let browser = DirectoryTree(root: FileManager.default.currentDirectoryPath)
        let crumbs = PathControl(path: FileManager.default.currentDirectoryPath)
        crumbs.onPathSelected = { status.text = "crumb: \($0)" }

        browser.expandRoot()
        browser.onSelectionChanged = { path in
            crumbs.setPath(path ?? browser.rootPath)
            status.text = path.map { "path: \($0)" } ?? "path cleared"
        }
        browser.onActivate = { status.text = "OPENED \($0)" }

        let filesTab = VStack(spacing: 1, insets: EdgeInsets(all: 1))
        filesTab.addSubview(Label("Files (right-click for a context menu):", style: CellStyle(flags: .bold)))
        filesTab.addSubview(files)
        filesTab.addSubview(crumbs)
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

        // "Panes" tab content: five live panes carved by three draggable
        // dividers — drag a line and watch the content reflow. The panel joins
        // edge-reaching dividers into its border (├ ┤ ┬ ┴), the crossing shows
        // ┼, and the right divider's endpoint tees into the horizontal (┬).
        let panesPanel = TUIKit.Panel("Dividers & Junctions — drag any line")

        let paneGuide = MarkdownView(markdown: """
        **Panes.** Drag the lines with the mouse, or Tab to one and use the \
        arrows. This text **rewraps** as its pane resizes.
        """)

        let paneSwift = SyntaxTextView(text: """
        // resize me
        func layout(panes: Int) -> Bool {
            let lines = 3
            return panes == 5 && lines == 3
        }
        """, language: "swift")

        let paneList = ListView(items: (1...20).map { "Pane row \($0)" })
        paneList.onSelectionChanged = { index in
            status.text = index.map { "pane list row \($0 + 1)" } ?? ""
        }

        let paneNotes = MarkdownView(markdown: """
        - `┼` where lines cross
        - `┬` endpoint meets a line
        - border tees join the panel
        - focused lines show the accent
        """)

        let paneCSS = SyntaxTextView(text: """
        /* junctions follow drags */
        Panel { border: rounded; }
        .status { color: brightCyan; }
        """, language: "css")

        let panes = PanesLayout(
            topLeft: paneGuide,
            topRight: paneSwift,
            bottomLeft: paneList,
            bottomMiddle: paneNotes,
            bottomRight: paneCSS
        )
        panes.onDividerMoved = { name in
            status.text = "\(name) divider moved — panes resize, junctions follow"
        }
        panes.anchors = .fill()
        panesPanel.content.addSubview(panes)

        // "New" tab: the Controls v2 additions (PLAN Phase 6B) — a toolbar with a
        // » overflow, a determinate progress bar plus a live spinner driven by an
        // App timer, date/time pickers with a calendar popup, and a Miller-column
        // browser. This is also the demo's proof of the non-blocking timer story.
        final class DemoBrowserSource: BrowserDataSource {
            func browserRootItems(_ browser: Browser) -> [BrowserItem] {
                [
                    BrowserItem("Fruits", isExpandable: true),
                    BrowserItem("Veg", isExpandable: true),
                    BrowserItem("Grains", isExpandable: true),
                    BrowserItem("README"),
                ]
            }

            func browser(_ browser: Browser, childrenOf item: BrowserItem) -> [BrowserItem] {
                switch item.title {
                case "Fruits":
                    return [BrowserItem("Citrus", isExpandable: true), BrowserItem("Apple"), BrowserItem("Banana")]
                case "Citrus":
                    return [BrowserItem("Orange"), BrowserItem("Lemon"), BrowserItem("Lime")]
                case "Veg":
                    return [BrowserItem("Carrot"), BrowserItem("Kale")]
                case "Grains":
                    return [BrowserItem("Rice"), BrowserItem("Oats")]
                default:
                    return []
                }
            }
        }

        let toolbar = Toolbar()
        toolbar.addItem("Run", icon: "▶") { status.text = "toolbar ▸ Run" }
        toolbar.addItem("Stop", icon: "■") { status.text = "toolbar ▸ Stop" }
        toolbar.addItem("Reset", icon: "↺") { status.text = "toolbar ▸ Reset" }
        toolbar.addItem("Export") { status.text = "toolbar ▸ Export" }
        toolbar.addItem("Settings") { status.text = "toolbar ▸ Settings" }

        let progress = ProgressIndicator(style: .bar, value: 40, minValue: 0, maxValue: 100)
        progress.showsPercentage = true

        let progressSlider = Slider(value: 40, in: 0...100, step: 5)
        progressSlider.onValueChanged = {
            progress.doubleValue = Double($0)
            status.text = "progress: \($0)%"
        }

        let spinner = ProgressIndicator(style: .spinner)
        spinner.caption = "idle"

        var spinnerTimer: AppTimer?
        let spinToggle = ToggleButton("Spin")
        spinToggle.onChange = { on in
            if on {
                spinner.caption = "working…"
                spinnerTimer = app.addTimer(every: .milliseconds(120)) { spinner.advance() }
                status.text = "spinner: animating (App timer)"
            } else {
                spinnerTimer?.cancel()
                spinnerTimer = nil
                spinner.caption = "idle"
                status.text = "spinner: stopped"
            }
        }

        let spinRow = HStack(spacing: 2)
        spinRow.addSubview(spinToggle)
        spinRow.addSubview(spinner)
        spinRow.addSubview(TUIView())

        let datePicker = DatePicker(mode: .date)
        datePicker.onDateChanged = { _ in status.text = "date updated" }
        let timePicker = DatePicker(mode: .time)
        timePicker.onDateChanged = { _ in status.text = "time updated" }

        let dateRow = HStack(spacing: 3)
        dateRow.addSubview(Label("Date:", style: CellStyle(flags: .bold)))
        dateRow.addSubview(datePicker)
        dateRow.addSubview(Label("Time:", style: CellStyle(flags: .bold)))
        dateRow.addSubview(timePicker)
        dateRow.addSubview(TUIView())

        let millerBrowser = Browser(dataSource: DemoBrowserSource(), columnWidth: 14)
        millerBrowser.maximumSize = Size(width: 9999, height: 7)
        millerBrowser.onSelectionChanged = { (item: BrowserItem?) in
            status.text = item.map { "browser ▸ \($0.title)" } ?? "browser cleared"
        }

        let v2Tab = VStack(spacing: 1, insets: EdgeInsets(all: 1))
        v2Tab.addSubview(Label("Toolbar — ←/→ move, Return activates, » overflow when narrow:", style: CellStyle(flags: .dim)))
        v2Tab.addSubview(toolbar)
        v2Tab.addSubview(Label("Progress bar — slide to fill:", style: CellStyle(flags: .dim)))
        v2Tab.addSubview(progressSlider)
        v2Tab.addSubview(progress)
        v2Tab.addSubview(Label("Spinner — toggle to animate via a non-blocking App timer:", style: CellStyle(flags: .dim)))
        v2Tab.addSubview(spinRow)
        v2Tab.addSubview(Label("Pickers — ↑/↓ fields, ←/→ segments, Space drops a calendar:", style: CellStyle(flags: .dim)))
        v2Tab.addSubview(dateRow)
        v2Tab.addSubview(Label("Browser — Miller columns, ←/→ between columns:", style: CellStyle(flags: .dim)))
        v2Tab.addSubview(millerBrowser)

        let v2Scroll = ScrollView(document: v2Tab)
        v2Scroll.fitsDocumentWidth = true

        let tabs = TabView()
        tabs.addTab("Form", content: formScroll)
        tabs.addTab("New", content: v2Scroll)
        tabs.addTab("Files", content: filesTab)
        tabs.addTab("Scroll", content: scrollTab)
        tabs.addTab("Data", content: dataTab)
        tabs.addTab("Code", content: codeTab)
        tabs.addTab("Docs", content: docsTab)
        tabs.addTab("Panes", content: panesPanel)
        tabs.onSelectionChanged = { status.text = "tab: \(tabs.title(at: $0) ?? "?")" }
        // Fill the controls window, leaving the bottom row for the status bar.
        tabs.anchors = AnchorSet(leading: 0, trailing: 0, top: 0, bottom: 1)

        // Status bar (Controls v2): flexible status label, a live-CSS toggle,
        // and a theme pop-up whose menu opens *above* (it sits at the bottom).
        let liveToggle = ToggleButton("CSS")
        liveToggle.onChange = { on in
            cssThemeActive = on
            controls.styleSheet = on ? StyleSheet(editor.text) : nil
            status.text = on
                ? "stylesheet applied — edit it live in the Code tab"
                : "stylesheet cleared"
        }

        let themePopUp = PopUpButton(items: TUIKit.Theme.builtIn.map(\.name), selectedIndex: 0)
        themePopUp.onSelectionChanged = { index in
            controls.theme = TUIKit.Theme.builtIn[index].theme
            status.text = "theme: \(TUIKit.Theme.builtIn[index].name)"
        }

        let statusBar = StatusBar()
        statusBar.addSegment(status, percentage: 100)
        statusBar.addSegment(liveToggle)
        statusBar.addSegment(themePopUp)
        statusBar.anchors = AnchorSet(leading: 0, trailing: 0, bottom: 0, height: 1)

        controls.content.addSubview(tabs)
        controls.content.addSubview(statusBar)
        controls.makeFirstResponder(tabs)
        return controls
    }

    // The DECLARATIVE example: the same spirit built with the TUIBuilder layer
    // (Docs/TUIBuilder.md) — nested containers, trailing-closure children,
    // chained modifiers, and no reactivity. Controls take defaults; you add
    // only your differences, and the parent containers do the layout. This is
    // the default window at launch.
    func makeDeclarativeExample(index: Int) -> FloatingWindow {
        let window = FloatingWindow(
            title: "Declarative Example \(index)",
            frame: Rect(x: 8 + index * 4, y: 4 + index * 2, width: 54, height: 20)
        )
        window.theme = .standard
        window.onCloseRequest = { [weak window] in
            if let window { app.dismiss(window) }
        }

        let status = Label("Built with TUIBuilder — try the controls.", style: CellStyle(flags: .dim))
        let progress = ProgressIndicator(style: .bar, value: 40, minValue: 0, maxValue: 100)
        progress.showsPercentage = true

        let nameField = TextField(placeholder: "type a name")
        nameField.onSubmit { status.text = "name: \($0)" }

        // The whole content declared once. `Form` lines the labeled rows up
        // for free; `setContent` fill-anchors the root into the window.
        window.content.setContent {
            VStack(spacing: 1, insets: EdgeInsets(all: 1)) {
                Label("A form, declared with TUIBuilder").bold()

                Form {
                    Field("Name") { nameField }
                    Field("Mode") {
                        SegmentedControl(["Fast", "Balanced", "Accurate"], selectedIndex: 1)
                            .onSelectionChanged { status.text = "mode \($0)" }
                    }
                    Field("Fill") {
                        Slider(value: 40, in: 0...100, step: 5).onValueChanged { value in
                            progress.doubleValue = Double(value)
                            status.text = "fill \(value)%"
                        }
                    }
                }

                Toggle("Wrap lines").onChange { status.text = "wrap: \($0)" }
                progress

                Spacer()

                HStack(spacing: 2) {
                    Spacer()
                    Button("Reset") { status.text = "reset" }
                    Button("Save") { status.text = "saved" }
                }

                status
            }
        }

        window.makeFirstResponder(nameField)
        return window
    }

    // A read-only table of every saved contact — reopen it after a Save to
    // confirm the edit reached the global store.
    func presentContactTable() {
        let store = ContactStore.shared
        let window = FloatingWindow(
            title: "All Contacts (\(store.people.count))",
            frame: Rect(x: 16, y: 5, width: 72, height: 18)
        )
        window.theme = .standard
        window.onCloseRequest = { [weak window] in if let window { app.dismiss(window) } }

        let table = TableView(columns: [
            TableColumn("Name"),
            TableColumn("Born", width: .fixed(12)),
            TableColumn("Address"),
        ])
        table.rows = store.people.map {
            [$0.name, ContactStore.displayFormatter.string(from: $0.birthday), $0.address]
        }

        window.content.setContent {
            VStack(spacing: 1, insets: EdgeInsets(all: 1)) {
                Label("Saved contacts — reopen after a Save to see changes land").bold()
                table
            }
        }
        window.makeFirstResponder(table)
        app.present(window)
    }

    // The Contact Book: a builder-built form bound to the global store with
    // @Bound projections. Left = names + ✚ Add; right = fields rebuilt per
    // selection, with Save/Revert driving load()/save() over the subtree.
    func makeContactBook(index: Int) -> FloatingWindow {
        let store = ContactStore.shared
        let window = FloatingWindow(
            title: "Contact Book \(index)",
            frame: Rect(x: 10 + index * 4, y: 3 + index * 2, width: 68, height: 22)
        )
        window.theme = .standard
        window.onCloseRequest = { [weak window] in if let window { app.dismiss(window) } }

        let list = ListView()
        // A plain view (not a stack): setContent fill-anchors its root, and a
        // stack would ignore anchors and size the content to its intrinsic
        // height — collapsing the flexible notes editor to nothing.
        let detail = TUIView()   // right pane, rebuilt on each selection
        let status = Label("Select a contact, or ✚ Add a new one.", style: CellStyle(flags: .dim))

        func refreshList(select selection: Int?) {
            list.items = store.people.map { $0.name.isEmpty ? "(new contact)" : $0.name }
            if let selection { list.select(selection, notify: true) }
        }

        func showPerson(at personIndex: Int) {
            guard store.people.indices.contains(personIndex) else {
                detail.setContent { Label("No contact selected.", style: CellStyle(flags: .dim)) }
                return
            }

            let person = store.people[personIndex]

            let notes = TextView()
            notes.bind(person.$notes)

            detail.setContent {
                VStack(spacing: 1, insets: EdgeInsets(all: 1)) {
                    Label("Contact details").bold()

                    Form {
                        Field("Name")    { TextField(placeholder: "full name").bind(person.$name) }
                        Field("Born")    { DatePicker(mode: .date, calendar: ContactStore.calendar).bind(person.$birthday) }
                        Field("Address") { TextField().bind(person.$address) }
                    }

                    Label("Notes").bold()
                    notes

                    HStack(spacing: 2) {
                        Spacer()
                        Button("Revert") { [weak detail] in
                            detail?.load()
                            status.text = "reverted"
                        }
                        Button("Save") { [weak detail] in
                            detail?.save()
                            refreshList(select: list.selectedIndex)
                            status.text = "saved — open Table to confirm"
                        }
                    }
                }
            }

            detail.load()   // model → the freshly-built controls
        }

        list.onSelectionChanged = { selection in
            if let selection { showPerson(at: selection) }
        }

        let leftHeader = HStack(spacing: 1, insets: EdgeInsets(top: 0, left: 1, bottom: 0, right: 1)) {
            Button("✚ Add") {
                store.add()
                refreshList(select: store.people.count - 1)
                status.text = "added a contact — fill it in and Save"
            }
            Button("Table") { presentContactTable() }
            Spacer()
        }

        let left = VStack(spacing: 0) {
            leftHeader
            Divider(axis: .horizontal)
            list
        }

        let split = SplitView(.horizontal) { left; detail }
        split.minimumFirstLength = 16
        split.minimumSecondLength = 24

        window.content.setContent {
            VStack(spacing: 0) {
                split
                status
            }
        }
        split.setDividerPosition(22)

        refreshList(select: store.people.isEmpty ? nil : 0)
        window.makeFirstResponder(list)   // focus the list, not the divider
        return window
    }

    // A source browser for the demo itself: a directory tree on the left, a
    // draggable divider, and a folder-tab editor on the right. It doubles as a
    // teaching aid — open the very code that builds these windows. Click a file
    // to open it in the current tab; click it again (or press ↵) to open it in
    // a fresh tab.
    func makeDemoSource(index: Int) -> FloatingWindow {
        // #filePath is this source file's location, so its parent directory is
        // the TUIKitDemo source tree — a stable anchor regardless of the
        // process's working directory.
        let demoDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

        // A tree node for a file or (lazily-listed) directory; the file URL
        // rides along in `representedValue` so selection can open it.
        func node(for url: URL) -> TreeNode {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true

            let item = TreeNode(url.lastPathComponent, childProvider: isDirectory ? {
                let children = (try? FileManager.default.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                )) ?? []

                return children
                    .sorted { a, b in
                        let aDir = (try? a.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                        let bDir = (try? b.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                        if aDir != bDir { return aDir }   // folders first
                        return a.lastPathComponent.localizedCaseInsensitiveCompare(b.lastPathComponent) == .orderedAscending
                    }
                    .map { node(for: $0) }
            } : nil)

            item.representedValue = url
            return item
        }

        let window = FloatingWindow(
            title: "Demo Source \(index)",
            frame: Rect(x: 6 + index * 3, y: 2 + index * 2, width: 84, height: 30)
        )
        window.onCloseRequest = { [weak window] in if let window { app.dismiss(window) } }

        let tree = TreeView(roots: [node(for: demoDir)])
        let tabs = TabView()
        let status = Label(
            "Click a file to open it · click it again (or ↵) to open it in a new tab",
            style: CellStyle(flags: .dim)
        )

        func language(for url: URL) -> String {
            switch url.pathExtension.lowercased() {
            case "swift":            return "swift"
            case "json":             return "json"
            case "md", "markdown":   return "markdown"
            case "css":              return "css"
            default:                 return "text"
            }
        }

        // Breadcrumb relative to the folder above the demo dir, so the first
        // crumb is the demo folder's own name.
        func crumbPath(for url: URL) -> String {
            let base = demoDir.deletingLastPathComponent().path
            let full = url.path
            return full.hasPrefix(base + "/") ? String(full.dropFirst(base.count + 1)) : url.lastPathComponent
        }

        // One folder's content: a breadcrumb over a syntax editor. The VStack
        // stretches the flexible editor to fill; the crumb row stays one tall.
        func sourcePane(for url: URL, text: String) -> TUIView {
            let crumbs = PathControl(path: crumbPath(for: url))
            let editor = SyntaxTextView(text: text, language: language(for: url))
            return VStack(spacing: 0) {
                crumbs
                editor
            }
        }

        func open(_ url: URL, inNewTab newTab: Bool) {
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true else {
                return   // folders expand in the tree; only files open
            }

            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                status.text = "· \(url.lastPathComponent) isn't a UTF-8 text file"
                return
            }

            let pane = sourcePane(for: url, text: text)
            let name = url.lastPathComponent

            if newTab || tabs.tabCount == 0 {
                tabs.addTab(name, content: pane)
                tabs.select(tabs.tabCount - 1, notify: false)
                status.text = "opened \(name) in a new tab — \(tabs.tabCount) open"
            } else {
                tabs.setTab(at: tabs.selectedIndex, title: name, content: pane)
                status.text = "opened \(name) in the current tab"
            }

            window.content.setNeedsLayout()
        }

        // Single click opens in the current tab; a second click / Return opens
        // a new tab (TreeView fires onActivate on a re-click of the selection).
        tree.onSelectionChanged = { selected in
            if let url = selected?.representedValue as? URL { open(url, inNewTab: false) }
        }
        tree.onActivate = { activated in
            if let url = activated.representedValue as? URL { open(url, inNewTab: true) }
        }

        let treeSection = VStack(spacing: 0) {
            Label(" Files", style: CellStyle(flags: .bold))
            Divider(axis: .horizontal)
            tree
        }

        let split = SplitView(.horizontal) { treeSection; tabs }
        split.minimumFirstLength = 18
        split.minimumSecondLength = 30

        window.content.setContent {
            VStack(spacing: 0) {
                split
                status
            }
        }
        split.setDividerPosition(26)

        // Reveal the folder, seed the first tab with main.swift, and highlight
        // it — a ready-made reading start instead of an empty pane.
        if let root = tree.roots.first {
            tree.expand(root)
            let mainURL = demoDir.appendingPathComponent("main.swift")
            open(mainURL, inNewTab: true)

            if let mainNode = root.children.first(where: {
                ($0.representedValue as? URL)?.lastPathComponent == "main.swift"
            }) {
                tree.select(mainNode, notify: false)   // silent: the tab is already open
            }
        }

        window.makeFirstResponder(tree)
        return window
    }

    // Root menu strip: File spawns example windows, Theme restyles the key one.
    let menuWindow = MenuBarWindow()
    menuWindow.onQuit = { app.stop() }

    var exampleCount = 0
    let fileMenu = Menu("File")
    fileMenu.addItem("New Declarative Example", keyEquivalent: KeyInput(key: .character("n"), modifiers: .control)) {
        exampleCount += 1
        app.present(makeDeclarativeExample(index: exampleCount))
    }
    fileMenu.addItem("New Manual Example", keyEquivalent: KeyInput(key: .character("m"), modifiers: .control)) {
        exampleCount += 1
        app.present(makeManualExample(index: exampleCount))
    }
    fileMenu.addItem("New Contact Book", keyEquivalent: KeyInput(key: .character("b"), modifiers: .control)) {
        exampleCount += 1
        app.present(makeContactBook(index: exampleCount))
    }
    fileMenu.addItem("New Demo Source", keyEquivalent: KeyInput(key: .character("d"), modifiers: .control)) {
        exampleCount += 1
        app.present(makeDemoSource(index: exampleCount))
    }
    fileMenu.addSeparator()
    fileMenu.addItem("Close Window", keyEquivalent: KeyInput(key: .character("w"), modifiers: .control)) {
        // Opening the menu made the strip key, so target the top-most example.
        if let target = app.windows.last(where: { $0 !== menuWindow }) {
            app.dismiss(target)
        }
    }
    fileMenu.addSeparator()
    fileMenu.addItem("Quit", keyEquivalent: KeyInput(key: .character("q"), modifiers: .control)) {
        app.stop()
    }

    let themeMenu = Menu("Theme")
    for (name, theme) in TUIKit.Theme.builtIn {
        themeMenu.addItem(name) {
            // One call themes the whole app — desktop and every window. Views
            // can still opt out locally (e.g. the declarative window pins its
            // controls to `.standard`).
            app.applyTheme(theme)
        }
    }

    let menuBar = MenuBar()
    menuBar.addMenu(fileMenu)
    menuBar.addMenu(themeMenu)
    menuBar.anchors = AnchorSet(leading: 0, top: 0, height: 1)
    menuWindow.addSubview(menuBar)
    menuWindow.menuBar = menuBar
    menuWindow.makeFirstResponder(menuBar)

    // Global status bar + live clock along the very bottom (also a second use
    // of the non-blocking App timer).
    let clock = Label("--:--:--")
    let clockFormatter = DateFormatter()
    clockFormatter.dateFormat = "HH:mm:ss"
    func refreshClock() { clock.text = clockFormatter.string(from: Date()) }
    refreshClock()
    app.addTimer(every: .seconds(1)) { refreshClock() }

    let globalStatus = StatusBar()
    globalStatus.addSegment(Label(" TUIKit Demo", style: CellStyle(flags: .bold)), minimumWidth: 14)
    globalStatus.addSegment(Label("File ▸ New… opens examples · close a window to dismiss it"), percentage: 100)
    globalStatus.addSegment(clock, minimumWidth: 10)
    globalStatus.anchors = AnchorSet(leading: 0, trailing: 0, bottom: 0, height: 1)
    menuWindow.addSubview(globalStatus)

    // Load the global contact list once, at startup.
    ContactStore.shared.loadIfNeeded()

    // The declarative example is the default; a Contact Book opens beside it so
    // the new feature is visible. File ▸ New… opens more of any kind.
    app.present(makeDeclarativeExample(index: 0))
    app.present(makeContactBook(index: 0))

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

Live demos:  swift run TUIKitDemo --interactive   (declarative + manual windows)
             swift run TUIKitDemo --events        (driver event viewer)
""")
}

// MARK: - Contact Book model (global, JSON-backed)

/// One editable contact. `@Bound` projects a `$` binding per field, so the
/// Contact Book form binds with `field.bind(person.$name)`.
@MainActor
final class Person {
    @Bound var name = ""
    @Bound var birthday: Date = Date()   // edited with a DatePicker (calendar control)
    @Bound var address = ""
    @Bound var notes = ""
}

/// JSON transport (Codable); `Person` is a bindable class, so we decode into
/// this and map across. `birthday` is an ISO `yyyy-MM-dd` string here and a
/// `Date` on `Person`; the `deathday` key in the seed JSON is simply ignored.
private struct PersonData: Codable {
    var name: String
    var birthday: String
    var address: String
    var notes: String
}

/// The one, global contact list. It lives for the whole run, so closing and
/// reopening a Contact Book window shows edits made earlier (no on-disk
/// persistence between runs — as specified).
@MainActor
final class ContactStore {
    static let shared = ContactStore()

    private(set) var people: [Person] = []
    private var loaded = false

    /// Every contact whose address is unknown falls back to the White House.
    static let whiteHouse = "1600 Pennsylvania Avenue NW, Washington, DC 20500"

    /// One UTC Gregorian calendar shared by the parser, the `DatePicker`, and
    /// the table — so a parsed date shows the same day everywhere.
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }()

    /// `yyyy-MM-dd` ↔ `Date` on the shared calendar (parses the seed JSON).
    static let isoFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// Human-readable US date for display (e.g. "Feb 22, 1732").
    static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateStyle = .medium
        return formatter
    }()

    /// Decodes the bundled `presidents.json` resource once, at startup.
    func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true

        let json = Bundle.module.url(forResource: "presidents", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) } ?? Data()
        let decoded = (try? JSONDecoder().decode([PersonData].self, from: json)) ?? []
        people = decoded.map { data in
            let person = Person()
            person.name = data.name
            person.birthday = Self.isoFormatter.date(from: data.birthday) ?? Date()
            person.address = data.address.isEmpty ? Self.whiteHouse : data.address
            person.notes = data.notes
            return person
        }
    }

    /// Appends a blank contact and returns it.
    @discardableResult
    func add() -> Person {
        let person = Person()
        people.append(person)
        return person
    }
}

