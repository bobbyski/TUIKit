import Testing
@testable import TUIKit

// MARK: - SplitView

@MainActor
private func makeSplit() -> (SplitView, Window) {
    let split = SplitView(axis: .horizontal, first: View(), second: View())
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
    let split = SplitView(axis: .vertical, first: View(), second: View())
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

// MARK: - FileDialog

// Local in-memory file system (test helpers are file-private).
private final class DialogFakeFileSystem: FileSystemProvider {
    var listings: [String: [FileSystemEntry]] = [:]
    private(set) var requests: [String] = []

    func entries(at path: String) -> [FileSystemEntry] {
        requests.append(path)
        return listings[path] ?? []
    }
}

@MainActor
private func makeFileDialog(mode: FileDialog.Mode) -> (FileDialog, DialogFakeFileSystem, [String]) {
    let disk = DialogFakeFileSystem()
    disk.listings["/root"] = [
        FileSystemEntry(name: "a.txt", isDirectory: false),
        FileSystemEntry(name: "sub", isDirectory: true),
    ]
    disk.listings["/root/sub"] = []

    let dialog = FileDialog(mode: mode, root: "/root", fileSystem: disk)
    return (dialog, disk, [])
}

@Test @MainActor func fileDialogOpenConfirmsTheSelectedFile() {
    let (dialog, disk, _) = makeFileDialog(mode: .open)

    var confirmed: [String] = []
    var dismissed = 0
    dialog.onConfirm = { confirmed.append($0) }
    dialog.onDismiss = { dismissed += 1 }

    #expect(disk.requests == ["/root"], "the root is listed once, up front")
    #expect(dialog.chosenPath == "/root", "focus lands on the root row")

    // Rows: root, sub, a.txt — walk to the file and confirm with Return.
    dialog.route(.key(KeyInput(key: .down)))
    dialog.route(.key(KeyInput(key: .down)))
    #expect(dialog.chosenPath == "/root/a.txt")

    dialog.route(.key(KeyInput(key: .enter)))
    #expect(confirmed == ["/root/a.txt"])
    #expect(dismissed == 1)
}

@Test @MainActor func fileDialogEscCancelsWithoutConfirming() {
    let (dialog, _, _) = makeFileDialog(mode: .open)

    var confirmed: [String] = []
    var dismissed = 0
    dialog.onConfirm = { confirmed.append($0) }
    dialog.onDismiss = { dismissed += 1 }

    dialog.route(.key(KeyInput(key: .escape)))
    #expect(confirmed.isEmpty)
    #expect(dismissed == 1)
}

@Test @MainActor func fileDialogSaveJoinsDirectoryAndName() {
    let (dialog, _, _) = makeFileDialog(mode: .save)

    dialog.suggestedName = "new.txt"
    #expect(dialog.chosenPath == "/root/new.txt")

    // Selecting a file prefills its name; its parent is the target.
    dialog.route(.key(KeyInput(key: .down)))   // sub (directory)
    dialog.route(.key(KeyInput(key: .down)))   // a.txt (file)
    #expect(dialog.suggestedName == "a.txt")
    #expect(dialog.chosenPath == "/root/a.txt")

    // Selecting a folder retargets the directory, keeping the name.
    dialog.route(.key(KeyInput(key: .up)))
    #expect(dialog.chosenPath == "/root/sub/a.txt")

    var confirmed: [String] = []
    dialog.onConfirm = { confirmed.append($0) }
    dialog.route(.key(KeyInput(key: .enter)))
    #expect(confirmed == ["/root/sub/a.txt"])
}

@Test @MainActor func fileDialogSelectFolderHidesFilesAndChooses() {
    let (dialog, _, _) = makeFileDialog(mode: .selectFolder)

    #expect(dialog.buttons.last?.title == "Choose")

    // Rows are root and sub only; walking past the end stays on sub.
    dialog.route(.key(KeyInput(key: .down)))
    dialog.route(.key(KeyInput(key: .down)))
    #expect(dialog.chosenPath == "/root/sub", "a.txt is hidden in folder mode")

    var confirmed: [String] = []
    dialog.onConfirm = { confirmed.append($0) }
    dialog.route(.key(KeyInput(key: .enter)))
    #expect(confirmed == ["/root/sub"])
}
