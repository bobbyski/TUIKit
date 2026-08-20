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
    root.addSubview(pinnedHeight(group("PathControl · TUIFavorites", [row(spacing: 2, [path, favorites])]), 4))

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

    let bottom = row(spacing: 1, [
        group("MarkdownView", [markdown]),
        group("RichText", [rich]),
    ])

    let root = VStack(spacing: 0, insets: EdgeInsets(top: 0, left: 1, bottom: 0, right: 1))
    root.addSubview(top)
    root.addSubview(bottom)
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

    root.addSubview(pinnedHeight(group("Ribbon — grouped toolbar, placed like any view", [ribbon]), 5))
    root.addSubview(row(spacing: 1, [
        // Button and split as siblings: nesting them in their own stack
        // would give the pair a fit-content intrinsic and starve the split.
        group("SplitView — Flip Axis is R7", [pinnedHeight(flip, 1), split]),
        group("ScrollView", [scroll]),
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
