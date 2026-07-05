import Testing
@testable import TUIKit

// In-memory data source keyed by title, for deterministic tests.
@MainActor
private final class FakeBrowserSource: BrowserDataSource {
    let root: [BrowserItem]
    let children: [String: [BrowserItem]]

    init(root: [BrowserItem], children: [String: [BrowserItem]]) {
        self.root = root
        self.children = children
    }

    func browserRootItems(_ browser: Browser) -> [BrowserItem] {
        root
    }

    func browser(_ browser: Browser, childrenOf item: BrowserItem) -> [BrowserItem] {
        children[item.title] ?? []
    }
}

// Fake file system: a path → entries map, no disk touched.
private struct FakeFileSystem: FileSystemProvider {
    let tree: [String: [FileSystemEntry]]

    func entries(at path: String) -> [FileSystemEntry] {
        tree[path] ?? []
    }
}

// MARK: - Column navigation

@Test @MainActor func browserDescendsAndAscendsColumns() {
    let source = FakeBrowserSource(
        root: [
            BrowserItem("Fruits", isExpandable: true),
            BrowserItem("Veg", isExpandable: true),
            BrowserItem("Note"),
        ],
        children: [
            "Fruits": [BrowserItem("Apple"), BrowserItem("Banana")],
            "Veg": [BrowserItem("Carrot")],
        ]
    )

    let browser = Browser(dataSource: source, columnWidth: 10)
    let window = Window(frame: Rect(x: 0, y: 0, width: 32, height: 4))
    browser.frame = window.bounds
    window.addSubview(browser)

    var selections: [String?] = []
    browser.onSelectionChanged = { selections.append($0?.title) }

    // Focus selects the first root row, whose children fill column 2.
    window.makeFirstResponder(browser)
    #expect(browser.selectedItem?.title == "Fruits")

    let lines = SceneRenderer(root: window).render(size: Size(width: 32, height: 4)).textLines()
    #expect(lines[0].hasPrefix("Fruits   ›"))
    #expect(Array(lines[0])[10] == "│", "a divider separates the columns")
    #expect(lines[0].contains("Apple"), "column 2 shows the selected item's children")

    // Down within column 1 re-targets column 2 to Veg's children.
    window.route(.key(KeyInput(key: .down)))
    #expect(browser.selectedItem?.title == "Veg")

    // Right descends into that child column.
    window.route(.key(KeyInput(key: .right)))
    #expect(browser.selectedItem?.title == "Carrot")

    // Left climbs back to the parent column.
    window.route(.key(KeyInput(key: .left)))
    #expect(browser.selectedItem?.title == "Veg")

    // Selecting a leaf drops any child column, so Right stays put.
    window.route(.key(KeyInput(key: .down)))   // Veg → Note (leaf)
    #expect(browser.selectedItem?.title == "Note")
    window.route(.key(KeyInput(key: .right)))
    #expect(browser.selectedItem?.title == "Note", "a leaf has no child column")

    #expect(selections == ["Fruits", "Veg", "Carrot", "Veg", "Note"])
}

@Test @MainActor func browserClickSelectsAndDoubleClickActivates() {
    let source = FakeBrowserSource(
        root: [BrowserItem("Fruits", isExpandable: true), BrowserItem("Note")],
        children: ["Fruits": [BrowserItem("Apple")]]
    )
    let browser = Browser(dataSource: source, columnWidth: 10)
    let window = Window(frame: Rect(x: 0, y: 0, width: 32, height: 4))
    browser.frame = window.bounds
    window.addSubview(browser)

    var activated: [String] = []
    browser.onActivate = { activated.append($0.title) }

    // A raw press selects nothing; the settled click does.
    _ = browser.mouseEvent(MouseInput(position: Point(x: 1, y: 1), action: .press, button: .left))
    _ = browser.mouseEvent(MouseInput(position: Point(x: 1, y: 1), action: .click, button: .left))
    #expect(browser.selectedItem?.title == "Note")
    #expect(activated.isEmpty, "a single click only selects")

    // Double-click activates the row under the pointer.
    _ = browser.mouseEvent(MouseInput(position: Point(x: 1, y: 1), action: .click, button: .left, clickCount: 2))
    #expect(activated == ["Note"])
}

// MARK: - File-system integration

@Test @MainActor func browserBrowsesAFileSystem() {
    let fs = FakeFileSystem(tree: [
        "/root": [
            FileSystemEntry(name: "readme.txt", isDirectory: false),
            FileSystemEntry(name: "src", isDirectory: true),
        ],
        "/root/src": [
            FileSystemEntry(name: "main.swift", isDirectory: false),
        ],
    ])

    let browser = Browser(fileSystemRoot: "/root", provider: fs, columnWidth: 14)
    let window = Window(frame: Rect(x: 0, y: 0, width: 30, height: 4))
    browser.frame = window.bounds
    window.addSubview(browser)

    // Directories sort first: "src" leads "readme.txt".
    window.makeFirstResponder(browser)
    #expect(browser.selectedItem?.title == "src")

    // Descend into the directory; the child carries its absolute path.
    window.route(.key(KeyInput(key: .right)))
    #expect(browser.selectedItem?.title == "main.swift")
    #expect(browser.selectedItem?.representedValue as? String == "/root/src/main.swift")
}
