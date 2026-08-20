import TUIKit

// The gallery window: folder tabs, one per control group. RULE (PLAN.md
// maintenance rules): a new TUIKit control lands with a spot in one of
// these tabs, in the same commit.

/// Builds one gallery window — a resizable, maximizable floating window
/// whose content is a folder-tab view of control groups.
@MainActor
func makeGalleryWindow(index: Int) -> FloatingWindow {
    let window = FloatingWindow(
        title: index == 0 ? "TUIKit Gallery" : "TUIKit Gallery \(index + 1)",
        frame: Rect(x: 2 + index * 2, y: 1 + index, width: 76, height: 22)
    )
    window.minimumWindowSize = Size(width: 46, height: 12)
    window.maximizeInsets = EdgeInsets(top: 1, bottom: 1)   // keep menu + status visible

    let tabs = TabView()
    tabs.addTab("Buttons", content: makeButtonsTab())
    tabs.addTab("Inputs", content: makeInputsTab())
    tabs.addTab("Lists", content: makeListsTab())
    tabs.addTab("Text", content: makeTextTab())
    tabs.addTab("Charts", content: makeChartsTab())
    tabs.anchors = .fill()
    window.content.addSubview(tabs)

    return window
}

// A group box: a titled panel whose content is a padded vertical stack.
@MainActor
private func group(_ title: String, spacing: Int = 1, _ children: [TUIView]) -> Panel {
    let panel = Panel(title)
    let stack = VStack(spacing: spacing, insets: EdgeInsets(top: 0, left: 1, bottom: 0, right: 1))

    for child in children {
        stack.addSubview(child)
    }

    stack.anchors = .fill()
    panel.content.addSubview(stack)
    return panel
}

// Pins a stack row to an exact height, so flexible rows don't absorb it.
@MainActor
private func pinnedHeight(_ view: TUIView, _ height: Int) -> TUIView {
    view.minimumSize = Size(width: 0, height: height)
    view.maximumSize = Size(width: Int.max, height: height)
    return view
}

// A row of side-by-side flexible children.
@MainActor
private func row(spacing: Int = 1, _ children: [TUIView]) -> HStack {
    let stack = HStack(spacing: spacing)

    for child in children {
        stack.addSubview(child)
    }

    return stack
}

// MARK: - Buttons

@MainActor
private func makeButtonsTab() -> TUIView {
    let root = VStack(spacing: 0, insets: EdgeInsets(top: 0, left: 1, bottom: 0, right: 1))

    // Roles: how a theme dresses ordinary/default/destructive.
    let ok = Button("&Save") {}
    ok.role = .default
    let danger = Button("&Delete") {}
    danger.role = .destructive
    let plain = Button("&Reset") {}
    let bordered = Button("Bordered") {}
    bordered.style = .bordered

    // Long-press: hold fires the alternate; a quick click still clicks.
    let holdResult = Label("click / hold ⇧ 600ms")
    let hold = Button("&Back") { holdResult.text = "clicked — quick press" }
    hold.onLongPress = { holdResult.text = "long-pressed — history menu would open" }

    let menuButton = Button("Menu on hold") {}
    let context = Menu("")
    context.addItem("Reopen Closed Tab") { holdResult.text = "menu: reopen" }
    context.addItem("Copy Address") { holdResult.text = "menu: copy" }
    menuButton.contextMenu = context   // no handler → long-press opens this

    let toggle = ToggleButton("Wrap Lines")
    let check = Checkbox("Show hidden files")
    let radios = RadioGroup(["Ask", "Allow", "Block"])
    let segments = SegmentedControl(["Day", "Week", "Month"], selectedIndex: 0)

    root.addSubview(pinnedHeight(group("Roles", [row([ok, danger, plain, bordered])]), 4))
    root.addSubview(pinnedHeight(group("Long-press (hold a fresh press ~600 ms)", [
        row([hold, menuButton]),
        holdResult,
    ]), 5))
    root.addSubview(pinnedHeight(group("State", [row([toggle, check])]), 4))
    root.addSubview(group("Choice", [row(spacing: 3, [radios, segments])]))

    return root
}

// MARK: - Inputs

@MainActor
private func makeInputsTab() -> TUIView {
    let root = VStack(spacing: 0, insets: EdgeInsets(top: 0, left: 1, bottom: 0, right: 1))

    let field = TextField()
    field.placeholder = "type here…"
    let combo = ComboBox(items: ["Mercury", "Venus", "Earth", "Mars"])

    let slider = Slider(value: 35, in: 0...100)
    let stepper = Stepper(value: 4, in: 0...10)
    let level = LevelIndicator(value: 3, maximum: 5)
    level.isEditable = true

    let progress = ProgressIndicator(style: .bar, value: 0.6)
    let date = DatePicker(mode: .date)

    root.addSubview(pinnedHeight(group("Text", [row([field, combo])]), 4))
    root.addSubview(pinnedHeight(group("Values", [row(spacing: 3, [slider, stepper, level])]), 4))
    root.addSubview(group("Progress & Dates", [row(spacing: 3, [progress, date])]))

    return root
}

// MARK: - Lists

@MainActor
private func makeListsTab() -> TUIView {
    let list = ListView(items: ["Inbox", "Drafts", "Sent", "Archive", "Spam", "Trash"])

    let tree = TreeView(roots: [
        TreeNode("Sources", children: [
            TreeNode("TUIKit", children: [TreeNode("Charts.swift"), TreeNode("Toolbar.swift")]),
            TreeNode("Tests"),
        ]),
        TreeNode("Docs", children: [TreeNode("Architecture.md")]),
    ])

    let table = TableView(
        columns: [TableColumn("Name"), TableColumn("Size", width: .fixed(8)), TableColumn("Kind", width: .fixed(10))],
        rows: [
            ["index.html", "12 KB", "html"],
            ["style.css", "48 KB", "css"],
            ["app.js", "214 KB", "js"],
            ["logo.png", "9 KB", "image"],
        ]
    )

    return row(spacing: 1, [
        group("ListView", [list]),
        group("TreeView", [tree]),
        group("TableView", [table]),
    ])
}

// MARK: - Text

@MainActor
private func makeTextTab() -> TUIView {
    // The R8 lexers, all three at once: markup, a style island, a script
    // island with a regex literal.
    let sample = """
    <!doctype html>
    <html>
      <head>
        <style>
          body { color: #333; margin: 0; }  /* island: CSS */
        </style>
        <script>
          // island: JavaScript
          const ok = /ab+c/.test(input) && count > 42;
          document.title = `found ${count} items`;
        </script>
      </head>
      <body class="main">
        &lt;escaped&gt; text &amp; entities
      </body>
    </html>
    """

    let editor = SyntaxTextView(text: sample, language: "html")
    return group("SyntaxTextView — language: html (script/style islands lex as JS/CSS)", [editor])
}
