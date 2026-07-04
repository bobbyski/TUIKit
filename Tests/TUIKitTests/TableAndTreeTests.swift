import Testing
@testable import TUIKit

@MainActor
private func renderedLines(_ view: TUIView, size: Size, focused: Bool = false) -> [String] {
    let window = Window(frame: Rect(origin: .zero, size: size))
    view.frame = Rect(origin: .zero, size: size)
    window.addSubview(view)

    if focused {
        window.makeFirstResponder(view)
    }

    return SceneRenderer(root: window).render(size: size).textLines()
}

// MARK: - TableView

@MainActor
private func makeTable() -> TableView {
    TableView(
        columns: [
            TableColumn("Name"),
            TableColumn("Size", width: .fixed(4)),
        ],
        rows: (1...10).map { ["file-\($0)", "\($0)K"] }
    )
}

@Test @MainActor func tableRendersHeaderAndRows() {
    let table = makeTable()
    let lines = renderedLines(table, size: Size(width: 16, height: 4))

    // 16 wide, fixed 4 + separator leaves 11 for Name.
    #expect(lines[0] == "Name        Size")
    #expect(lines[1] == "file-1      1K  ")
    #expect(lines[3] == "file-3      3K  ")
}

@Test @MainActor func tableResolvesFlexibleColumnsByWeight() {
    let table = TableView(
        columns: [
            TableColumn("A", width: .flexible(2)),
            TableColumn("B", width: .flexible(1)),
            TableColumn("C", width: .fixed(3)),
        ],
        rows: [["aa", "bb", "cc"]]
    )

    // Total 20: separators 2, fixed 3 → leftover 15 → A 10, B 5.
    let lines = renderedLines(table, size: Size(width: 20, height: 2))
    #expect(lines[0] == "A          B     C  ")
    #expect(lines[1] == "aa         bb    cc ")
}

@Test @MainActor func tableNavigatesAndScrollsBelowTheHeader() {
    let table = makeTable()
    table.frame = Rect(x: 0, y: 0, width: 16, height: 4)   // header + 3 rows

    var events: [Int?] = []
    table.onSelectionChanged = { events.append($0) }

    _ = table.keyDown(KeyInput(key: .down))
    #expect(table.selectedIndex == 0)

    _ = table.keyDown(KeyInput(key: .end))
    #expect(table.selectedIndex == 9)
    #expect(table.scrollOffset == 7, "last row visible in a 3-row viewport")

    _ = table.keyDown(KeyInput(key: .pageUp))
    #expect(table.selectedIndex == 7)

    _ = table.keyDown(KeyInput(key: .home))
    #expect(table.selectedIndex == 0)
    #expect(table.scrollOffset == 0)

    #expect(events == [0, 9, 7, 0])
}

@Test @MainActor func tableClickSelectsRowAndHeaderRequestsSort() {
    let table = makeTable()
    table.frame = Rect(x: 0, y: 0, width: 16, height: 4)

    var sorts: [Int] = []
    table.onSortRequested = { sorts.append($0) }

    // Click the second visible row (viewport row 2 → data row 1).
    _ = table.mouseEvent(MouseInput(position: Point(x: 3, y: 2), action: .press, button: .left))
    #expect(table.selectedIndex == 1)

    // Header clicks: x3 is inside Name (0..10), x13 inside Size (12..15).
    _ = table.mouseEvent(MouseInput(position: Point(x: 3, y: 0), action: .press, button: .left))
    _ = table.mouseEvent(MouseInput(position: Point(x: 13, y: 0), action: .press, button: .left))
    #expect(sorts == [0, 1])
    #expect(table.selectedIndex == 1, "header clicks do not move the selection")
}

@Test @MainActor func tableActivatesAndSelectsSilently() {
    let table = makeTable()
    table.frame = Rect(x: 0, y: 0, width: 16, height: 4)

    var events: [Int?] = []
    var activated: [Int] = []
    table.onSelectionChanged = { events.append($0) }
    table.onActivate = { activated.append($0) }

    table.select(4)
    #expect(table.selectedIndex == 4)
    #expect(events.isEmpty)

    _ = table.keyDown(KeyInput(key: .enter))
    #expect(activated == [4])
}

@Test @MainActor func tableSelectionRendersInverseAcrossTheFullRow() {
    let table = makeTable()
    table.select(0)

    let window = Window(frame: Rect(x: 0, y: 0, width: 16, height: 4))
    table.frame = window.bounds
    window.addSubview(table)

    let buffer = SceneRenderer(root: window).render(size: Size(width: 16, height: 4))

    // Every cell of the selected row (y1) is inverse, including padding.
    for x in 0..<16 {
        #expect(buffer[Point(x: x, y: 1)].style.flags.contains(.inverse))
    }

    #expect(!buffer[Point(x: 0, y: 2)].style.flags.contains(.inverse))
}

// MARK: - TreeView

@MainActor
private func makeTree() -> (TreeView, TreeNode, TreeNode, TreeNode) {
    let sources = TreeNode("Sources")
    let controls = TreeNode("Controls")
    controls.addChild(TreeNode("Button.swift"))
    controls.addChild(TreeNode("ListView.swift"))
    sources.addChild(controls)
    sources.addChild(TreeNode("TUIKit.swift"))

    let tests = TreeNode("Tests")
    tests.addChild(TreeNode("ControlTests.swift"))

    let tree = TreeView(roots: [sources, tests])
    return (tree, sources, controls, tests)
}

@Test @MainActor func treeRendersCollapsedRootsWithDisclosures() {
    let (tree, _, _, _) = makeTree()

    #expect(tree.visibleRowCount == 2)

    let lines = renderedLines(tree, size: Size(width: 20, height: 4))
    #expect(lines[0].hasPrefix("▸ Sources"))
    #expect(lines[1].hasPrefix("▸ Tests"))
    #expect(lines[2].allSatisfy { $0 == " " })
}

@Test @MainActor func treeExpandsAndIndentsChildren() {
    let (tree, sources, controls, _) = makeTree()

    tree.expand(sources)
    #expect(tree.visibleRowCount == 4)

    tree.expand(controls)
    #expect(tree.visibleRowCount == 6)

    let lines = renderedLines(tree, size: Size(width: 26, height: 7))
    #expect(lines[0].hasPrefix("▾ Sources"))
    #expect(lines[1].hasPrefix("  ▾ Controls"))
    #expect(lines[2].hasPrefix("    Button.swift") == false, "leaves keep a disclosure gutter")
    #expect(lines[2].hasPrefix("      Button.swift"))
    #expect(lines[4].hasPrefix("  TUIKit.swift") == false)
    #expect(lines[4].hasPrefix("    TUIKit.swift"))
    #expect(lines[5].hasPrefix("▸ Tests"))
}

@Test @MainActor func treeDisclosureKeysExpandCollapseAndStep() {
    let (tree, sources, controls, _) = makeTree()
    tree.frame = Rect(x: 0, y: 0, width: 26, height: 8)

    tree.select(sources)

    _ = tree.keyDown(KeyInput(key: .right))
    #expect(sources.isExpanded, "→ expands a collapsed node")
    #expect(tree.selectedNode === sources)

    _ = tree.keyDown(KeyInput(key: .right))
    #expect(tree.selectedNode === controls, "→ on an expanded node steps to the first child")

    _ = tree.keyDown(KeyInput(key: .left))
    #expect(tree.selectedNode === sources, "← on a collapsed child steps to the parent")

    _ = tree.keyDown(KeyInput(key: .left))
    #expect(!sources.isExpanded, "← collapses an expanded node")
    #expect(tree.visibleRowCount == 2)
    #expect(tree.selectedNode === sources, "the collapsed node stays selected")
}

@Test @MainActor func treeLazyChildrenLoadOnceOnFirstExpansion() {
    var loads = 0
    let lazy = TreeNode("Lazy", childProvider: {
        loads += 1
        return [TreeNode("child-1"), TreeNode("child-2")]
    })

    let tree = TreeView(roots: [lazy])
    #expect(lazy.isExpandable, "a provider makes the node expandable before loading")

    tree.expand(lazy)
    #expect(loads == 1)
    #expect(tree.visibleRowCount == 3)

    tree.collapse(lazy)
    tree.expand(lazy)
    #expect(loads == 1, "the provider runs exactly once")
    #expect(tree.visibleRowCount == 3)
}

@Test @MainActor func treeClickSelectsAndDisclosureClickToggles() {
    let (tree, sources, controls, _) = makeTree()
    tree.frame = Rect(x: 0, y: 0, width: 26, height: 8)
    tree.expand(sources)

    var selections: [String] = []
    tree.onSelectionChanged = { selections.append($0?.title ?? "nil") }

    // Row 1 is "  ▸ Controls": x0 selects only, x2 is the disclosure.
    _ = tree.mouseEvent(MouseInput(position: Point(x: 5, y: 1), action: .press, button: .left))
    #expect(tree.selectedNode === controls)
    #expect(!controls.isExpanded, "clicking the title does not toggle")

    _ = tree.mouseEvent(MouseInput(position: Point(x: 2, y: 1), action: .press, button: .left))
    #expect(controls.isExpanded, "clicking the triangle expands")
    #expect(tree.visibleRowCount == 6)

    _ = tree.mouseEvent(MouseInput(position: Point(x: 2, y: 1), action: .press, button: .left))
    #expect(!controls.isExpanded, "clicking it again collapses")

    #expect(selections == ["Controls"], "selection changed once; the toggles kept it")
}

// MARK: - DirectoryTree

// In-memory file system: listings by path, with a request log proving
// laziness. Nothing in these tests touches the real disk.
private final class FakeFileSystem: FileSystemProvider {
    var listings: [String: [FileSystemEntry]] = [:]
    private(set) var requests: [String] = []

    func entries(at path: String) -> [FileSystemEntry] {
        requests.append(path)
        return listings[path] ?? []
    }
}

@MainActor
private func makeDirectoryTree() -> (DirectoryTree, FakeFileSystem, Window) {
    let disk = FakeFileSystem()
    disk.listings["/root"] = [
        FileSystemEntry(name: "README.md", isDirectory: false),
        FileSystemEntry(name: "src", isDirectory: true),
        FileSystemEntry(name: "docs", isDirectory: true),
    ]
    disk.listings["/root/src"] = [
        FileSystemEntry(name: "main.swift", isDirectory: false),
    ]

    let directory = DirectoryTree(root: "/root", fileSystem: disk)
    let window = Window(frame: Rect(x: 0, y: 0, width: 24, height: 8))
    directory.frame = window.bounds
    window.addSubview(directory)
    window.layoutIfNeeded()
    return (directory, disk, window)
}

@Test @MainActor func directoryTreeStartsCollapsedAndListsNothing() {
    let (directory, disk, window) = makeDirectoryTree()

    #expect(disk.requests.isEmpty, "creation reads nothing from the file system")
    #expect(directory.selectedPath == nil)

    let lines = SceneRenderer(root: window).render(size: window.frame.size).textLines()
    #expect(lines[0].hasPrefix("▸ root"))
}

@Test @MainActor func directoryTreeExpandsLazilyAndSortsDirectoriesFirst() {
    let (directory, disk, window) = makeDirectoryTree()

    directory.expandRoot()
    #expect(disk.requests == ["/root"], "expansion lists exactly the expanded directory")

    let lines = SceneRenderer(root: window).render(size: window.frame.size).textLines()
    #expect(lines[0].hasPrefix("▾ root"))
    #expect(lines[1].hasPrefix("  ▸ docs"), "directories first, alphabetical")
    #expect(lines[2].hasPrefix("  ▸ src"))
    #expect(lines[3].hasPrefix("    README.md"), "files after directories")
}

@Test @MainActor func directoryTreeSelectsAndActivatesPaths() {
    let (directory, disk, window) = makeDirectoryTree()
    directory.expandRoot()

    var selections: [String?] = []
    var activated: [String] = []
    directory.onSelectionChanged = { selections.append($0) }
    directory.onActivate = { activated.append($0) }

    // Click the "src" row, then its disclosure triangle.
    window.route(.mouse(MouseInput(position: Point(x: 6, y: 2), action: .press, button: .left)))
    #expect(directory.selectedPath == "/root/src")

    window.route(.mouse(MouseInput(position: Point(x: 2, y: 2), action: .press, button: .left)))
    #expect(disk.requests == ["/root", "/root/src"], "each directory lists once, on first expansion")

    let lines = SceneRenderer(root: window).render(size: window.frame.size).textLines()
    #expect(lines[3].hasPrefix("      main.swift"))

    window.route(.key(KeyInput(key: .enter)))
    #expect(activated == ["/root/src"])
    #expect(
        selections == ["/root", "/root/src"],
        "click-focus selects the root row first, then the click selects src"
    )
}

@Test @MainActor func directoryTreeCanHideFiles() {
    let (directory, disk, window) = makeDirectoryTree()
    directory.showsFiles = false
    directory.expandRoot()

    let lines = SceneRenderer(root: window).render(size: window.frame.size).textLines()
    #expect(lines[1].hasPrefix("  ▸ docs"))
    #expect(lines[2].hasPrefix("  ▸ src"))
    #expect(!lines.joined().contains("README.md"))
    _ = disk
}

@Test @MainActor func directoryTreeSetRootReloads() {
    let (directory, disk, window) = makeDirectoryTree()
    disk.listings["/other"] = [FileSystemEntry(name: "thing.txt", isDirectory: false)]

    directory.setRoot("/other")
    directory.expandRoot()

    #expect(directory.rootPath == "/other")

    let lines = SceneRenderer(root: window).render(size: window.frame.size).textLines()
    #expect(lines[0].hasPrefix("▾ other"))
    #expect(lines[1].hasPrefix("    thing.txt"))
}

@Test @MainActor func treeActivatesTheSelectedNode() {
    let (tree, sources, _, _) = makeTree()
    tree.frame = Rect(x: 0, y: 0, width: 26, height: 8)

    var activated: [String] = []
    tree.onActivate = { activated.append($0.title) }

    tree.select(sources)
    _ = tree.keyDown(KeyInput(key: .enter))
    #expect(activated == ["Sources"])
}
