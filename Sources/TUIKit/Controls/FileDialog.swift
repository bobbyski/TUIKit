/// Modal file chooser: open, save, or select-folder.
///
/// `FileDialog` composes the pieces that already exist — `Dialog` for
/// modality and buttons, `DirectoryTree` for browsing — so the whole
/// control is testable against a fake `FileSystemProvider` (AICoding rule
/// 30). The footer line always shows the path that would be confirmed.
///
/// ```swift
/// let dialog = FileDialog(mode: .save, root: projectRoot)
/// dialog.suggestedName = "Untitled.txt"
/// dialog.onConfirm = { path in save(to: path) }
/// dialog.onDismiss = { [weak app] in app?.dismiss(dialog) }
/// dialog.sizeToFit(in: screenSize)
/// app.present(dialog)
/// ```
///
/// Behavior by mode:
///
/// - `.open` — browse files and folders; confirm returns the selection.
/// - `.save` — a name field joins the current directory; selecting a file
///   prefills the name, selecting a folder retargets the directory.
/// - `.selectFolder` — files are hidden; confirm returns the folder.
///
/// Return anywhere confirms (tree activation, name-field submit, or the
/// default button); Esc cancels. Cancel never calls `onConfirm`.
@MainActor
public final class FileDialog: Dialog {
    /// What the dialog chooses.
    public enum Mode: Sendable {
        /// Choose an existing file (or folder).
        case open

        /// Choose a directory and file name to write.
        case save

        /// Choose a directory; files are hidden.
        case selectFolder
    }

    /// What the dialog chooses.
    public let mode: Mode

    /// Called with the chosen path when the dialog confirms.
    public var onConfirm: (String) -> Void = { _ in }

    /// Proposed file name (save mode).
    public var suggestedName: String {
        get {
            nameField.text
        }
        set {
            nameField.setText(newValue)
            updateFooter()
        }
    }

    // Browsing and naming.
    private let directory: DirectoryTree
    private let nameField = TextField(placeholder: "file name")
    private let footer = Label("", style: CellStyle(flags: .dim))

    // Directory a save would write into.
    private var currentDirectory: String

    /// Creates a file dialog.
    ///
    /// - Parameters:
    ///   - mode: What the dialog chooses.
    ///   - root: Directory the tree starts at.
    ///   - fileSystem: Listing source. Defaults to the local file system.
    public init(
        mode: Mode,
        root: String,
        fileSystem: FileSystemProvider = LocalFileSystem()
    ) {
        self.mode = mode
        self.currentDirectory = root
        self.directory = DirectoryTree(
            root: root,
            fileSystem: fileSystem,
            showsFiles: mode != .selectFolder
        )

        super.init(title: Self.windowTitle(for: mode))

        let column = VStack(spacing: 0)
        column.anchors = .fill()
        column.addSubview(directory)

        if mode == .save {
            let nameRow = HStack(spacing: 1)
            nameRow.addSubview(Label("Name:", style: CellStyle(flags: .bold)))
            nameField.maximumSize = Size(width: 999, height: 1)
            nameRow.addSubview(nameField)
            column.addSubview(nameRow)
        }

        column.addSubview(footer)
        body.addSubview(column)

        directory.expandRoot()
        updateFooter()

        directory.onSelectionChanged = { [weak self] path in
            self?.selectionChanged(to: path)
        }

        directory.onActivate = { [weak self] _ in
            self?.defaultButton?.activate()
        }

        nameField.onSubmit = { [weak self] _ in
            self?.defaultButton?.activate()
        }

        nameField.onChanged = { [weak self] _ in
            self?.updateFooter()
        }

        addButton("Cancel", isCancel: true)
        addButton(Self.confirmTitle(for: mode), isDefault: true) { [weak self] in
            guard let self else {
                return
            }

            self.onConfirm(self.chosenPath)
        }

        // Start browsing, not on the default button.
        makeFirstResponder(nil)
        focusNext()
    }

    /// The path confirm would return right now.
    public var chosenPath: String {
        switch mode {
        case .open, .selectFolder:
            return directory.selectedPath ?? directory.rootPath

        case .save:
            let name = nameField.text
            return name.isEmpty ? currentDirectory : DirectoryTree.join(currentDirectory, name)
        }
    }

    /// Roomy enough for the tree; `sizeToFit(in:)` clamps to the screen.
    public override var preferredSize: Size {
        let base = super.preferredSize
        return Size(width: max(base.width, 44), height: max(base.height + 12, 16))
    }

    // MARK: - Selection plumbing

    private func selectionChanged(to path: String?) {
        if let path {
            if directory.isDirectory(path) {
                currentDirectory = path
            } else {
                currentDirectory = DirectoryTree.parent(of: path)

                if mode == .save {
                    nameField.setText(DirectoryTree.lastComponent(of: path))
                }
            }
        }

        updateFooter()
    }

    private func updateFooter() {
        footer.text = chosenPath
    }

    private static func windowTitle(for mode: Mode) -> String {
        switch mode {
        case .open:
            return "Open"

        case .save:
            return "Save"

        case .selectFolder:
            return "Choose Folder"
        }
    }

    private static func confirmTitle(for mode: Mode) -> String {
        switch mode {
        case .open:
            return "Open"

        case .save:
            return "Save"

        case .selectFolder:
            return "Choose"
        }
    }
}
