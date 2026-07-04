import Foundation
import TUIKit

// Demo Source — a mini source browser for the demo's *own* files. It's the most
// "assembled from parts" window: a TreeView + SplitView + a closable-tab TabView,
// wired together imperatively with a few small local helper functions. Read it as
// a worked example of composing controls and reacting to their callbacks.
extension DemoApp {

    // Layout, front to back:
    //
    //   ┌ Demo Source ──────────────────────────────[+][x]┐
    //   │ Files        │ file.swift × │ other.swift × │    │   ← TreeView | SplitView | TabView (closable)
    //   │ ▾ TUIKitDemo │ TUIKitDemo ▸ Declarative ▸ …  │   │   ← each tab: PathControl breadcrumb…
    //   │   main.swift │  1 │ import Foundation           │   ← …over a read-only SyntaxTextView
    //   └──────────────┴──────────────────────────────────┘
    //
    // Behavior: single-click a file → open it in the *current* tab; click the
    // already-selected file again, or press Return → open it in a *new* tab.
    func makeDemoSource(index: Int) -> FloatingWindow {
        let app = self.app

        // #filePath is this file (…/TUIKitDemo/Declarative/DemoSource.swift), so
        // the demo root is two directories up. Using the source location (not the
        // process's working directory) makes the tree point at the right place no
        // matter where `swift run` was invoked from.
        let demoDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Declarative/
            .deletingLastPathComponent()   // TUIKitDemo/

        // Builds one TreeNode for a URL, recursively. Directories get a
        // `childProvider` closure instead of eager children: TreeView calls it the
        // first time the node expands, so we never scan the whole tree up front —
        // only the folders you actually open. The file URL is stashed in
        // `representedValue` (an `Any?` the tree carries for you) so the selection
        // callbacks can recover which file a row stands for.
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
                    .map { node(for: $0) }   // recurse: each child is itself a lazy node
            } : nil)   // a file (nil provider) is a non-expandable leaf

            item.representedValue = url
            return item
        }

        let window = FloatingWindow(
            title: "Demo Source \(index)",
            frame: Rect(x: 6 + index * 3, y: 2 + index * 2, width: 84, height: 30)
        )
        window.onCloseRequest = { [weak window] in if let window { app.dismiss(window) } }
        // When this window maximizes, leave the top row (menu bar) and bottom row
        // (global status) visible instead of covering the whole screen.
        window.maximizeInsets = EdgeInsets(top: 1, bottom: 1)
        window.themeContext = .contentWindow   // an editor surface (Turbo: blue window, yellow text)

        let tree = TreeView(roots: [node(for: demoDir)])
        let tabs = TabView()
        tabs.tabsClosable = true   // each tab shows a × the user can click to close it
        let status = Label(
            "Click a file to open it · click it again (or ↵) for a new tab · × closes one",
            style: CellStyle(flags: .dim)
        )

        // Maps a file extension to a RichSwift syntax language id (unknown → plain
        // "text", which just renders unhighlighted).
        func language(for url: URL) -> String {
            switch url.pathExtension.lowercased() {
            case "swift":            return "swift"
            case "json":             return "json"
            case "md", "markdown":   return "markdown"
            case "css":              return "css"
            default:                 return "text"
            }
        }

        // Path shown in the breadcrumb, made relative to the folder *above* the
        // demo dir so the first crumb is the demo folder's own name
        // (e.g. "TUIKitDemo ▸ Declarative ▸ DemoSource.swift").
        func crumbPath(for url: URL) -> String {
            let base = demoDir.deletingLastPathComponent().path
            let full = url.path
            return full.hasPrefix(base + "/") ? String(full.dropFirst(base.count + 1)) : url.lastPathComponent
        }

        // Builds the content view for one open file: a breadcrumb over a syntax
        // editor. This is returned straight to `TabView.addTab`, which sets its
        // frame — so a VStack works fine as tab content here (the stack fills the
        // frame TabView gives it and stretches the flexible editor). Contrast with
        // the Contact Book's `detail`, where `setContent` fill-anchoring made a
        // plain host view necessary. The editor is read-only: this is a viewer.
        func sourcePane(for url: URL, text: String) -> TUIView {
            let crumbs = PathControl(path: crumbPath(for: url))
            let editor = SyntaxTextView(text: text, language: language(for: url))
            editor.isEditable = false   // a source viewer, not an editor
            return VStack(spacing: 0) {
                crumbs
                editor
            }
        }

        // Opens a file into the tab area. `newTab` (or having no tabs yet) adds a
        // fresh tab; otherwise it replaces the current tab's content in place
        // (`setTab`) — a "preview tab" that single-clicks reuse, so browsing files
        // doesn't pile up tabs.
        func open(_ url: URL, inNewTab newTab: Bool) {
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true else {
                return   // clicking a folder expands it in the tree; only files open here
            }

            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                status.text = "· \(url.lastPathComponent) isn't a UTF-8 text file"
                return
            }

            let pane = sourcePane(for: url, text: text)
            let name = url.lastPathComponent

            if newTab || tabs.tabCount == 0 {
                tabs.addTab(name, content: pane)
                tabs.select(tabs.tabCount - 1, notify: false)   // focus the tab we just added
                status.text = "opened \(name) in a new tab — \(tabs.tabCount) open"
            } else {
                tabs.setTab(at: tabs.selectedIndex, title: name, content: pane)
                status.text = "opened \(name) in the current tab"
            }

            window.content.setNeedsLayout()   // the new/updated tab content needs positioning
        }

        // The two callbacks split single from double click. The click events are
        // debounced through the app's multi-click guard, and a double fires ONLY
        // `onActivate` — never `onSelectionChanged` alongside it. So:
        //   • single-click a file → selectionChanged → open in current tab
        //   • double-click a file → activate         → open in a new tab (only)
        tree.onSelectionChanged = { selected in
            if let url = selected?.representedValue as? URL { open(url, inNewTab: false) }
        }
        tree.onActivate = { activated in
            if let url = activated.representedValue as? URL { open(url, inNewTab: true) }
        }
        // Refresh the hint when a tab is closed (and relayout, since the visible
        // content may have changed).
        tabs.onTabClosed = { _ in
            status.text = tabs.tabCount == 0
                ? "all tabs closed — pick a file to open one"
                : "closed a tab — \(tabs.tabCount) open"
            window.content.setNeedsLayout()
        }

        // Left column: a bold "Files" caption, a rule, then the flexible tree.
        let treeSection = VStack(spacing: 0) {
            Label(" Files", style: CellStyle(flags: .bold))
            Divider(axis: .horizontal)
            tree
        }

        // Tree on the left, tab area on the right, draggable divider between.
        let split = SplitView(.horizontal) { treeSection; tabs }
        split.minimumFirstLength = 18
        split.minimumSecondLength = 30

        // Host the split above the status line. (Root is a VStack, which is fine
        // for setContent — see the note in ContactBook.swift.)
        window.content.setContent {
            VStack(spacing: 0) {
                split
                status
            }
        }
        split.setDividerPosition(26)   // after the tree exists, so clamping is correct

        // Seed the window so it opens on something useful instead of an empty
        // pane: expand the root folder, open main.swift in the first tab, and
        // select its row in the tree. The select is *silent* (notify: false) so it
        // doesn't fire onSelectionChanged and re-open the file we just opened.
        if let root = tree.roots.first {
            tree.expand(root)
            let mainURL = demoDir.appendingPathComponent("main.swift")
            open(mainURL, inNewTab: true)

            if let mainNode = root.children.first(where: {
                ($0.representedValue as? URL)?.lastPathComponent == "main.swift"
            }) {
                tree.select(mainNode, notify: false)
            }
        }

        window.makeFirstResponder(tree)   // arrows drive the tree from the start
        return window
    }
}
