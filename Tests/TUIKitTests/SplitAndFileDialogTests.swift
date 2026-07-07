import Testing
@testable import TUIKit

// MARK: - SplitView

@MainActor
private func makeSplit() -> (SplitView, Window) {
    let split = SplitView(axis: .horizontal, first: TUIView(), second: TUIView())
    let window = Window(frame: Rect(x: 0, y: 0, width: 20, height: 4))
    split.frame = window.bounds
    window.addSubview(split)
    window.layoutIfNeeded()
    return (split, window)
}

@Test @MainActor func splitViewLaysOutPanesAroundTheDivider() {
    let (split, window) = makeSplit()

    // Unset divider defaults to half of 20: first 9, divider col 9, second 10.
    #expect(split.currentDividerPosition == 9)
    #expect(split.first.frame == Rect(x: 0, y: 0, width: 9, height: 4))
    #expect(split.second.frame == Rect(x: 10, y: 0, width: 10, height: 4))

    split.setDividerPosition(5)
    window.layoutIfNeeded()
    #expect(split.first.frame.size.width == 5)
    #expect(split.second.frame == Rect(x: 6, y: 0, width: 14, height: 4))

    let line = Array(SceneRenderer(root: window).render(size: window.frame.size).textLines()[1])
    #expect(line[5] == "│", "the divider renders at its column")
}

@Test @MainActor func splitViewFocusCueIsColorNotBoldOrInverse() {
    // The default divider cue recolors to the accent — never bold or inverse,
    // since bold box-drawing glyphs render as a dashed line. (Regression guard.)
    let (split, window) = makeSplit()
    window.makeFirstResponder(split)

    let style = SceneRenderer(root: window)
        .render(size: window.frame.size)[Point(x: split.currentDividerPosition, y: 1)]
        .style

    #expect(style.foreground == .named(.brightCyan), "focus recolors the divider to the accent")
    #expect(!style.flags.contains(.bold), "never bold")
    #expect(!style.flags.contains(.inverse), "never inverse")
}

@Test @MainActor func splitViewKeysMoveAndClampTheDivider() {
    let (split, _) = makeSplit()
    split.minimumFirstLength = 3
    split.minimumSecondLength = 4

    var moves: [Int] = []
    split.onDividerMoved = { moves.append($0) }

    _ = split.keyDown(KeyInput(key: .left))
    #expect(split.currentDividerPosition == 8)

    _ = split.keyDown(KeyInput(key: .home))
    #expect(split.currentDividerPosition == 3, "home snaps against the first minimum")

    _ = split.keyDown(KeyInput(key: .left))
    #expect(split.currentDividerPosition == 3, "clamped at the minimum, no event")

    _ = split.keyDown(KeyInput(key: .end))
    #expect(split.currentDividerPosition == 15, "end leaves the second minimum (20 - 1 - 4)")

    #expect(moves == [8, 3, 15])
}

@Test @MainActor func splitViewDividerDragsThroughWindowCapture() {
    let (split, window) = makeSplit()

    // Grab the divider at (9, 1), drag left across the first pane.
    window.route(.mouse(MouseInput(position: Point(x: 9, y: 1), action: .press, button: .left)))
    window.route(.mouse(MouseInput(position: Point(x: 4, y: 2), action: .drag, button: .left)))
    #expect(split.currentDividerPosition == 4, "capture keeps the drag alive over the pane")

    window.route(.mouse(MouseInput(position: Point(x: 4, y: 2), action: .release, button: .left)))
    window.route(.mouse(MouseInput(position: Point(x: 12, y: 2), action: .drag, button: .left)))
    #expect(split.currentDividerPosition == 4, "release ends the drag")
}

@Test @MainActor func splitViewVerticalAxisUsesRowGeometry() {
    let split = SplitView(axis: .vertical, first: TUIView(), second: TUIView())
    split.frame = Rect(x: 0, y: 0, width: 10, height: 11)
    split.layoutIfNeeded()

    #expect(split.currentDividerPosition == 5)
    #expect(split.first.frame == Rect(x: 0, y: 0, width: 10, height: 5))
    #expect(split.second.frame == Rect(x: 0, y: 6, width: 10, height: 5))

    _ = split.keyDown(KeyInput(key: .up))
    #expect(split.currentDividerPosition == 4)

    _ = split.keyDown(KeyInput(key: .down))
    _ = split.keyDown(KeyInput(key: .down))
    #expect(split.currentDividerPosition == 6)
}

// MARK: - DirectoryList / FileDialog fake disk

// Local in-memory file system (test helpers are file-private). New folders
// land in `listings` so a subsequent `entries` call sees them.
private final class DialogFakeFileSystem: FileSystemProvider {
    var listings: [String: [FileSystemEntry]] = [:]
    var locations: [FileDialog.Location] = []
    private(set) var requests: [String] = []
    private(set) var created: [String] = []

    func entries(at path: String) -> [FileSystemEntry] {
        requests.append(path)
        return listings[path] ?? []
    }

    func createDirectory(at path: String) -> Bool {
        created.append(path)
        let parent = DirectoryTree.parent(of: path)
        let name = DirectoryTree.lastComponent(of: path)
        listings[parent, default: []].append(FileSystemEntry(name: name, isDirectory: true))
        listings[path] = []
        return true
    }

    func standardLocations() -> [FileDialog.Location] {
        locations
    }
}

@MainActor
private func makeDisk() -> DialogFakeFileSystem {
    let disk = DialogFakeFileSystem()
    disk.listings["/root"] = [
        FileSystemEntry(name: "a.txt", isDirectory: false),
        FileSystemEntry(name: "notes.md", isDirectory: false),
        FileSystemEntry(name: ".hidden", isDirectory: false),
        FileSystemEntry(name: "sub", isDirectory: true),
    ]
    disk.listings["/root/sub"] = [FileSystemEntry(name: "x.txt", isDirectory: false)]
    return disk
}

@MainActor
private func makeFileDialog(mode: FileDialog.Mode) -> (FileDialog, DialogFakeFileSystem) {
    let disk = makeDisk()
    let dialog = FileDialog(mode: mode, root: "/root", fileSystem: disk)
    return (dialog, disk)
}

// MARK: - DirectoryList

@Test @MainActor func directoryListOrdersParentDirectoriesThenFiles() {
    let list = DirectoryList(directory: "/root", fileSystem: makeDisk())

    #expect(list.visibleRows.map(\.path) == ["/", "/root/sub", "/root/a.txt", "/root/notes.md"])
    #expect(list.visibleRows.first?.isParent == true, "the .. row leads the list")
    #expect(list.selectedEntry?.path == "/root/sub", "selection lands on the first real entry")
}

@Test @MainActor func directoryListFiltersFilesButNeverDirectories() {
    let list = DirectoryList(directory: "/root", fileSystem: makeDisk())

    list.filterPatterns = ["*.md"]
    #expect(list.visibleRows.map(\.path) == ["/", "/root/sub", "/root/notes.md"], "a.txt is filtered out; sub stays")
}

@Test @MainActor func directoryListHidesDotFilesUntilAsked() {
    let list = DirectoryList(directory: "/root", fileSystem: makeDisk())

    #expect(!list.visibleRows.contains { $0.path == "/root/.hidden" })

    list.showsHidden = true
    #expect(list.visibleRows.contains { $0.path == "/root/.hidden" })
}

@Test @MainActor func directoryListHidesFilesWhenShowsFilesIsOff() {
    let list = DirectoryList(directory: "/root", fileSystem: makeDisk(), showsFiles: false)

    #expect(list.visibleRows.map(\.path) == ["/", "/root/sub"], "folder-only listing")
}

@Test @MainActor func directoryListNavigatesIntoAndOutOfDirectories() {
    let list = DirectoryList(directory: "/root", fileSystem: makeDisk())

    var navigated: [String] = []
    list.onNavigate = { navigated.append($0) }

    list.setDirectory("/root/sub")
    #expect(list.directory == "/root/sub")
    #expect(list.visibleRows.map(\.path) == ["/root", "/root/sub/x.txt"], ".. points back to /root")
    #expect(navigated == ["/root/sub"])
}

// MARK: - FileDialog

@Test @MainActor func fileDialogOpenConfirmsTheActivatedFile() {
    let (dialog, disk) = makeFileDialog(mode: .open)

    var confirmed: [String] = []
    var dismissed = 0
    dialog.onConfirm = { confirmed.append($0) }
    dialog.onDismiss = { dismissed += 1 }

    #expect(disk.requests == ["/root"], "the root is listed once, up front")
    #expect(dialog.chosenPath == "/root/sub", "selection starts on the first real entry")

    // Rows: .., sub, a.txt, notes.md — step onto the file and Return opens it.
    dialog.route(.key(KeyInput(key: .down)))   // a.txt
    #expect(dialog.chosenPath == "/root/a.txt")

    dialog.route(.key(KeyInput(key: .enter)))
    #expect(confirmed == ["/root/a.txt"])
    #expect(dismissed == 1)
}

@Test @MainActor func fileDialogActivatingAFolderNavigatesRatherThanConfirms() {
    let (dialog, _) = makeFileDialog(mode: .open)

    var confirmed: [String] = []
    dialog.onConfirm = { confirmed.append($0) }

    // Selection starts on "sub"; Return descends into it, no confirm.
    dialog.route(.key(KeyInput(key: .enter)))
    #expect(dialog.currentDirectory == "/root/sub")
    #expect(confirmed.isEmpty)
}

@Test @MainActor func fileDialogEscCancelsWithoutConfirming() {
    let (dialog, _) = makeFileDialog(mode: .open)

    var confirmed: [String] = []
    var dismissed = 0
    dialog.onConfirm = { confirmed.append($0) }
    dialog.onDismiss = { dismissed += 1 }

    dialog.route(.key(KeyInput(key: .escape)))
    #expect(confirmed.isEmpty)
    #expect(dismissed == 1)
}

@Test @MainActor func fileDialogSaveJoinsDirectoryAndName() {
    let (dialog, _) = makeFileDialog(mode: .save)

    dialog.suggestedName = "new.txt"
    #expect(dialog.chosenPath == "/root/new.txt")

    // Selecting a file prefills its name for overwrite.
    dialog.route(.key(KeyInput(key: .down)))   // a.txt
    #expect(dialog.suggestedName == "a.txt")
    #expect(dialog.chosenPath == "/root/a.txt")

    // Descending into a folder keeps the name and retargets the directory.
    dialog.route(.key(KeyInput(key: .up)))     // back to sub
    dialog.route(.key(KeyInput(key: .enter)))  // into /root/sub
    #expect(dialog.currentDirectory == "/root/sub")
    #expect(dialog.chosenPath == "/root/sub/a.txt")

    var confirmed: [String] = []
    dialog.onConfirm = { confirmed.append($0) }
    dialog.buttons.last?.activate()
    #expect(confirmed == ["/root/sub/a.txt"])
}

@Test @MainActor func fileDialogSelectFolderHidesFilesAndChooses() {
    let (dialog, _) = makeFileDialog(mode: .selectFolder)

    #expect(dialog.buttons.last?.title == "Choose")
    #expect(dialog.chosenPath == "/root/sub", "selection starts on the only folder; files are hidden")

    var confirmed: [String] = []
    dialog.onConfirm = { confirmed.append($0) }
    dialog.buttons.last?.activate()
    #expect(confirmed == ["/root/sub"])
}

@Test @MainActor func fileDialogWildcardAndFileTypeFilterTheList() {
    let disk = makeDisk()
    let dialog = FileDialog(
        mode: .open,
        root: "/root",
        fileSystem: disk,
        fileTypes: [.init(title: "Markdown", patterns: ["*.md"])],
        wildcard: "*.md"
    )

    // With the wildcard applied, walking the list never reaches a.txt.
    var seen: Set<String> = []

    for _ in 0..<6 {
        seen.insert(dialog.chosenPath)
        dialog.route(.key(KeyInput(key: .down)))
    }

    #expect(seen.contains("/root/notes.md"))
    #expect(!seen.contains("/root/a.txt"), "the *.md filter hides a.txt")
}

@Test @MainActor func fileDialogNewFolderCreatesAndSelects() {
    let (dialog, disk) = makeFileDialog(mode: .save)

    #expect(dialog.addDirectory(named: "Reports"))
    #expect(disk.created == ["/root/Reports"])
    #expect(dialog.currentDirectory == "/root")
    #expect(dialog.selectedPath == "/root/Reports", "the new folder is selected")
}

@Test @MainActor func fileDialogCustomConfirmTitleAndKind() {
    let disk = makeDisk()
    let dialog = FileDialog(
        mode: .open,
        root: "/root",
        fileSystem: disk,
        chooses: .directories,
        confirmTitle: "Import"
    )

    #expect(dialog.buttons.last?.title == "Import")
    #expect(dialog.chosenPath == "/root/sub", "directories-only selection")
}

@Test @MainActor func fileDialogSidebarLocationNavigates() {
    let disk = makeDisk()
    disk.locations = [FileDialog.Location(title: "Sub", path: "/root/sub", icon: "S")]
    let dialog = FileDialog(mode: .open, root: "/root", fileSystem: disk)

    // Focus starts on the file list; step back onto the sidebar and activate.
    dialog.route(.key(KeyInput(key: .tab, modifiers: .shift)))
    dialog.route(.key(KeyInput(key: .enter)))
    #expect(dialog.currentDirectory == "/root/sub")
}
