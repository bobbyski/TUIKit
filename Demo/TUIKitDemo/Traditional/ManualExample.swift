import Foundation
import TUIKit

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

extension DemoApp {
    // The MANUAL example: the original imperative demo, intact and repeatable —
    // every control wired by hand. The declarative example below mirrors it.
    func makeManualExample(index: Int) -> FloatingWindow {
        let app = self.app
        let controls = FloatingWindow(
            title: "Manual Example \(index)",
            frame: Rect(x: 3 + index * 4, y: 2 + index * 2, width: 74, height: 22)
        )
        controls.theme = .standard
        controls.themeContext = .secondaryWindows   // a form/dialog surface (Turbo: gray)
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
        fileActions.addItem("&Open") {
            status.text = files.selectedIndex.map { "context: open \(files.items[$0])" } ?? "context: open"
        }
        fileActions.addItem("&Rename…") { status.text = "context: rename" }
        fileActions.addSeparator()
        fileActions.addItem("&Delete") { status.text = "context: delete (not really)" }
        files.contextMenu = fileActions

        let summary = Button("&Summary") {
            status.text = "name='\(name.text)' wrap=\(wrap.isChecked) mode=\(mode.selectedIndex ?? -1)"
        }
        let quit = Button("&Quit") {
            let dialog = Dialog(title: "Quit?", message: "Leave the TUIKit demo?")
            dialog.addButton("&Cancel", isCancel: true)
            dialog.addButton("&Quit", isDefault: true) { app.stop() }
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
        // stylesheet. CSS is a *layer on top of the theme*, not a theme — flip
        // the "CSS" toggle in the status bar and edits re-style the window live
        // over whatever theme is currently selected.
        let editor = SyntaxTextView(
            text: """
            /* TUIKit stylesheet — a layer ON TOP of the theme.
               Flip the "CSS" toggle in the status bar, then edit me
               and watch the window restyle over whatever theme is active. */
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
                status.text = "CSS re-applied over the theme — \(editor.lineCount) lines"
            } else {
                status.text = "editing — \(editor.lineCount) lines (turn on the CSS toggle to apply)"
            }
        }

        let codeTab = VStack(spacing: 1, insets: EdgeInsets(all: 1))
        codeTab.addSubview(RichText(markup: "[bold]SyntaxTextView[/] — the window's [cyan]stylesheet[/], layered over the theme by the [bold]CSS[/] toggle"))
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

        // Status bar (Controls v2): a flexible status label, an independent CSS
        // toggle, and a theme pop-up — side by side, because a theme and a
        // stylesheet are orthogonal. Pick any theme, then flip CSS on/off to see
        // the sheet layer over whatever theme is active. Off is just
        // `styleSheet = nil` (the theme underneath is never touched).
        let liveToggle = ToggleButton("CSS")
        liveToggle.onChange = { on in
            cssThemeActive = on
            controls.styleSheet = on ? StyleSheet(editor.text) : nil
            status.text = on
                ? "stylesheet applied over the current theme — edit it live in the Code tab"
                : "stylesheet cleared (theme unchanged)"
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
}
