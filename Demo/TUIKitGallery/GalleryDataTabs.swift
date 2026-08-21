import Foundation
import TUIKit

// The Lists, Text, and Layout folder tabs.

// MARK: - Lists & trees

@MainActor
func makeListsTab() -> TUIView {
    let root = VStack(spacing: 0, insets: EdgeInsets(top: 0, left: 1, bottom: 0, right: 1))

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

    // The real disk, twice: an outline and Miller columns.
    let cwd = FileManager.default.currentDirectoryPath
    let directory = DirectoryTree(root: cwd)
    directory.expandRoot()
    let browser = Browser(fileSystemRoot: cwd)

    // Crumbs + favorites: the one-row navigation strips.
    let path = PathControl(path: "/Users/bobby/src/frameworks/UILess/Code/TUIKit")
    let favorites = TUIFavorites()
    favorites.items = [
        .init(title: "TUIKit"),
        .init(title: "RichSwift"),
        .init(title: "VectorTerminal"),
    ]

    root.addSubview(row(spacing: 1, [
        group("ListView", [list]),
        group("TreeView", [tree]),
        group("TableView", [table]),
    ]))
    root.addSubview(row(spacing: 1, [
        group("DirectoryTree (the real disk)", [directory]),
        group("Browser — Miller columns", [browser]),
    ]))
    // Phase 16: Sidebar — tiles beside the detail here; below 60 columns
    // it turns into a navigator (resize the window to see it flip).
    let folders = [
        SidebarItem(icon: "✉", title: "Inbox", subtitle: "12 unread"),
        SidebarItem(icon: "★", title: "Starred", subtitle: "3 flagged"),
        SidebarItem(icon: "✎", title: "Drafts", subtitle: "1 draft"),
        SidebarItem(icon: "⌫", title: "Trash", subtitle: "empty"),
    ]
    let sidebar = Sidebar(items: folders) { index in
        Label("  \(folders[index].title): \(folders[index].subtitle ?? "") — the detail pane for this folder")
    }

    root.addSubview(pinnedHeight(group("PathControl · TUIFavorites", [row(spacing: 2, [path, favorites])]), 4))
    // Phase 16: CollectionView — sections of uniform items, a selection,
    // arrows that walk the grid.
    let files = CollectionView(sections: [
        .init(title: "Recent", items: ["report.pdf", "notes.md", "photo.png", "deck.key", "todo.txt"]),
        .init(title: "Shared", items: ["budget.xlsx", "plan.md", "logo.svg"]),
    ]) { Label($0) }
    files.itemWidth = 16

    root.addSubview(pinnedHeight(row([
        group("Sidebar — list + detail; pushes below 60 columns", [sidebar]),
        group("CollectionView — arrows walk the grid", [files]),
    ]), 8))

    return root
}

// MARK: - Text

@MainActor
func makeTextTab() -> TUIView {
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
      <body class="main">&lt;escaped&gt; &amp; entities</body>
    </html>
    """

    let editor = SyntaxTextView(text: sample, language: "html")

    let text = TextView(text: """
    TextView: focusable, selectable multi-line text.

    Arrow keys move, Shift extends the selection, ^C copies — \
    the same editing engine as the code view, minus the gutter.
    """)

    let markdown = MarkdownView(markdown: """
    # MarkdownView

    Renders **RichSwift markdown**: headings, lists, quotes, `inline code`.

    - scrolls with arrows and the wheel
    - soft-wraps to its width
    """)

    let rich = RichText(markup: "[bold yellow]RichText[/]: inline [cyan]markup[/] via [green]RichSwift[/] — tables, panels and syntax render too.")

    let top = row(spacing: 1, [
        group("SyntaxTextView — html (script/style islands lex as JS/CSS)", [editor]),
        group("TextView", [text]),
    ])

    // Phase 16.24: Edit flips the same pane to highlighted source and back.
    let editToggle = Button("&Edit source") {}
    editToggle.onActivate = { [weak markdown, weak editToggle] in
        guard let markdown else { return }
        markdown.toggleEditing()
        editToggle?.title = markdown.isEditing ? "&Render" : "&Edit source"
    }

    let bottom = row(spacing: 1, [
        group("MarkdownView — Edit flips to the source editor", [pinnedHeight(editToggle, 1), markdown]),
        group("RichText", [rich]),
    ])

    // Phase 16: Link hands its URL over (or opens it); (?) is the same
    // control in its help-button dress.
    let linkResult = Label("links report here")
    let link = Link("TUIKit on GitHub", url: "https://github.com/bobbyski/TUIKit")
    link.onOpen = { linkResult.text = "would open: \($0)" }
    let help = Link.help(anchor: "text", baseURL: "tuikit://help#")
    help.onOpen = { linkResult.text = "help anchor: \($0)" }

    let root = VStack(spacing: 0, insets: EdgeInsets(top: 0, left: 1, bottom: 0, right: 1))
    root.addSubview(top)
    root.addSubview(bottom)
    root.addSubview(pinnedHeight(group("Link & HelpLink", [row(spacing: 2, [link, help, linkResult])]), 4))
    return root
}

// MARK: - Layout

@MainActor
func makeLayoutTab() -> TUIView {
    let root = VStack(spacing: 0, insets: EdgeInsets(top: 0, left: 1, bottom: 0, right: 1))

    // SplitView with the R7 axis flip, live.
    let first = Label("first pane")
    first.alignment = .center
    let second = Label("second pane")
    second.alignment = .center
    let split = SplitView(axis: .horizontal, first: first, second: second)
    // The divider position is sticky user state; minimums keep it sane
    // through the zero-size first layout a freshly built tab goes through.
    split.minimumFirstLength = 8
    split.minimumSecondLength = 8

    let flip = Button("&Flip Axis") { [weak split] in
        guard let split else {
            return
        }

        split.axis = split.axis == .horizontal ? .vertical : .horizontal
    }

    // ScrollView: a document taller than its viewport.
    let document = VStack(spacing: 0)
    for line in 1...30 {
        document.addSubview(pinnedHeight(Label("scrolling line \(line)"), 1))
    }
    let scroll = ScrollView(document: document)

    // Disclosure + divider + ribbon.
    let disclosure = DisclosureGroup("Advanced", isExpanded: true)
    disclosure.content.addSubview(Label("hidden until disclosed").anchoredFill())

    let ribbon = Ribbon()
    ribbon.addGroup("Clipboard", items: [
        ToolbarItem("Cut", icon: ToolbarIcon(glyph: "✂")),
        ToolbarItem("Copy", icon: ToolbarIcon(glyph: "⧉")),
        ToolbarItem("Paste", icon: ToolbarIcon(glyph: "⎘")),
    ])
    ribbon.addGroup("History", items: [
        ToolbarItem("Undo", icon: ToolbarIcon(glyph: "↶")),
        ToolbarItem("Redo", icon: ToolbarIcon(glyph: "↷")),
    ])

    // Phase 16: StatusBar flash (a timed message owning the row) and
    // priority (the hint gives way first when the bar is narrow).
    let status = StatusBar()
    status.showsSeparators = false   // a connected separator would weld into the group's title row
    status.addSegment(Label("Ready"), minimumWidth: 8, priority: 2)
    status.addSegment(Label("low-priority hint — narrows first"), percentage: 100, priority: 0)
    status.addSegment(Label("Ln 12, Col 4"), priority: 1)
    let flash = Button("&Flash") { [weak status] in status?.flash("Saved 3 files — back in 3 seconds") }

    // Phase 16: FlowStack reflows tags to the width; Form sections share
    // one label column across headers.
    let tags = FlowStack(spacing: 1)
    for tag in ["swift", "terminal", "tui", "concurrency", "testing", "headless", "vtg", "themes", "gallery", "wave-b"] {
        tags.addSubview(Button(tag) {})
    }
    let sectioned = Form(spacing: 0) {
        Section("Account") {
            Field("Name") { TextField(placeholder: "your name") }
            Field("Email") { TextField(placeholder: "you@host") }
        }
        Section("Appearance") {
            Field("Theme") { PopUpButton(items: ["Turbo", "Ambiance", "Standard"], selectedIndex: 0) }
        }
    }

    // Phase 16: Toolbox — an exclusive tool palette.
    let toolLabel = Label("tool: Select")
    let toolbox = Toolbox(axis: .horizontal, tools: [
        .init(glyph: "↖", caption: "Select"), .init(glyph: "✎", caption: "Pen"),
        .init(glyph: "▭", caption: "Rect"), .init(glyph: "◯", caption: "Ellipse"),
    ])
    toolbox.onSelectionChanged = { toolLabel.text = "tool: \(toolbox.tools[$0].caption)" }

    root.addSubview(pinnedHeight(row([
        group("Ribbon — grouped toolbar, placed like any view", [ribbon]),
        group("Toolbox — one tool at a time", [toolbox, toolLabel]),
    ]), 5))
    root.addSubview(pinnedHeight(row([
        group("FlowStack — tags wrap to the width", [tags]),
        group("Form — Section headers, one label column", [sectioned]),
    ]), 8))
    root.addSubview(pinnedHeight(group("StatusBar — flash and priority", [status, row([pinnedHeight(flash, 1)])]), 5))
    // Phase 16: Scroller — a bar of its own, driving the ScrollView beside it
    // (and following it, when the view scrolls on its own).
    let scroller = Scroller(axis: .vertical, span: ScrollSpan(offset: 0, viewport: 8, content: 30))
    scroller.onScroll = { [weak scroll] offset in
        scroll?.setOffset(Point(x: 0, y: offset), notify: false)
    }
    scroll.onOffsetChanged = { [weak scroller, weak scroll] offset in
        guard let scroller, let scroll else { return }
        scroller.span = ScrollSpan(offset: offset.y, viewport: scroll.bounds.size.height, content: scroll.contentSize.height)
    }

    root.addSubview(row(spacing: 1, [
        // Button and split as siblings: nesting them in their own stack
        // would give the pair a fit-content intrinsic and starve the split.
        group("SplitView — Flip Axis is R7", [pinnedHeight(flip, 1), split]),
        group("Scroller ⟷ ScrollView", [row(spacing: 1, [scroller, scroll])]),
        group("DisclosureGroup + Divider", [disclosure, Divider(axis: .horizontal), Label("below the rule")]),
    ]))

    return root
}

private extension TUIView {
    /// Fill-anchors, returning self for one-line embedding.
    func anchoredFill() -> TUIView {
        anchors = .fill()
        return self
    }
}
