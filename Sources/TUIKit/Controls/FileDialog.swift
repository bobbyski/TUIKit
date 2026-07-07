import Foundation

/// Modal file chooser: open, save, or select-folder.
///
/// `FileDialog` composes pieces that already exist — `Dialog` for modality
/// and buttons, a locations sidebar and `DirectoryList` for browsing — into
/// the classic Windows-style chooser: shortcut locations on the left, one
/// directory at a time in the middle (with a `..` row and a breadcrumb bar),
/// and filter controls beneath. Every listing goes through a
/// `FileSystemProvider`, so the whole control is testable against a fake disk
/// (AICoding rule 30).
///
/// ```text
///   Home  │ /Users/bobby/Projects            ◂ breadcrumb
///   Computer │ ↑ ..
///   Disk  │ ▸ Sources
///         │ ▸ Tests
///         │ · README.md
///   ───────┴──────────────────────────
///   Filter: [*.txt        ]  [x] Show hidden
///   Type:   [ Text (*.txt) ▾ ]
///   Name:   [ notes.txt   ]      [ New Folder ]
///   /Users/bobby/Projects/notes.txt
///                        [ Cancel ] [ Save ]
/// ```
///
/// Behavior by mode (each preset is overridable through the initializer):
///
/// - `.open` — browse files and folders; confirm returns the selection.
/// - `.save` — a Name field joins the current directory; selecting a file
///   prefills the name, and New Folder creates a subdirectory.
/// - `.selectFolder` — files are hidden; confirm returns the current (or
///   selected) folder.
///
/// Return anywhere confirms (activating a file, the name field, or the
/// default button); activating a folder or `..` navigates instead. Esc
/// cancels and never calls `onConfirm`.
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

    /// Which kinds of entry the dialog may return.
    public enum FileKind: Sendable {
        /// Only files (folders are for navigation).
        case files

        /// Only directories; files are hidden entirely.
        case directories

        /// Either a file or a folder.
        case filesAndDirectories
    }

    /// A shortcut in the locations sidebar.
    public struct Location: Equatable, Sendable {
        /// Text shown in the sidebar.
        public var title: String

        /// Absolute path the shortcut jumps to.
        public var path: String

        /// One-cell glyph drawn before the title.
        public var icon: Character

        /// Creates a sidebar location.
        ///
        /// - Parameters:
        ///   - title: Text shown in the sidebar.
        ///   - path: Absolute path the shortcut jumps to.
        ///   - icon: One-cell glyph drawn before the title.
        public init(title: String, path: String, icon: Character = "▸") {
            self.title = title
            self.path = path
            self.icon = icon
        }
    }

    /// A named wildcard filter for the Type pop-up (e.g. "Text" → `*.txt`).
    public struct FileType: Equatable, Sendable {
        /// Text shown in the pop-up.
        public var title: String

        /// Wildcard patterns files must match (see ``Glob``).
        public var patterns: [String]

        /// Creates a file type.
        ///
        /// - Parameters:
        ///   - title: Text shown in the pop-up.
        ///   - patterns: Wildcard patterns files must match.
        public init(title: String, patterns: [String]) {
            self.title = title
            self.patterns = patterns
        }
    }

    /// One-cell glyphs the dialog draws before rows and locations.
    ///
    /// The default set is single-width so columns stay aligned in every
    /// terminal; ``emoji`` is offered for terminals whose font renders and
    /// advances emoji as one cell.
    public struct Icons: Equatable, Sendable {
        /// Glyph for the `..` parent row.
        public var parent: Character

        /// Glyph for a directory.
        public var folder: Character

        /// Glyph for a file.
        public var file: Character

        /// Glyph for the Home shortcut.
        public var home: Character

        /// Glyph for the file-system root shortcut.
        public var root: Character

        /// Glyph for a volume shortcut.
        public var volume: Character

        /// Creates an icon set.
        public init(
            parent: Character,
            folder: Character,
            file: Character,
            home: Character,
            root: Character,
            volume: Character
        ) {
            self.parent = parent
            self.folder = folder
            self.file = file
            self.home = home
            self.root = root
            self.volume = volume
        }

        /// Single-width text glyphs (the default): aligned everywhere.
        public static let `default` = Icons(
            parent: "↑", folder: "▸", file: "·", home: "⌂", root: "/", volume: "≡"
        )

        /// Emoji glyphs; use only where the terminal treats them as one cell.
        public static let emoji = Icons(
            parent: "⬆", folder: "📁", file: "📄", home: "🏠", root: "💽", volume: "📦"
        )
    }

    /// What the dialog chooses.
    public let mode: Mode

    /// Which kinds of entry confirm may return.
    public let chooses: FileKind

    /// Called with the chosen path when the dialog confirms.
    public var onConfirm: (String) -> Void = { _ in }

    /// Proposed file name (save / name-field modes).
    public var suggestedName: String {
        get {
            nameField.text
        }
        set {
            nameField.setText(newValue)
            updateFooter()
        }
    }

    // Browsing.
    private let fileSystem: FileSystemProvider
    private let directoryList: DirectoryList
    private let locations: [Location]
    private let usesNameField: Bool

    // Controls.
    private let pathControl: PathControl
    private let nameField = TextField(placeholder: "file name")
    private let wildcardField = TextField(placeholder: "*")
    private let hiddenToggle = Checkbox("Show hidden")
    private let footer = Label("", style: CellStyle(flags: .dim))
    private let newFolderRow = HStack(spacing: 1)
    private let newFolderField = TextField(placeholder: "new folder name")

    /// Creates a file dialog.
    ///
    /// - Parameters:
    ///   - mode: What the dialog chooses; presets the other options.
    ///   - root: Directory the browser starts in.
    ///   - fileSystem: Listing source. Defaults to the local file system.
    ///   - chooses: Kinds confirm may return. `nil` uses the mode default.
    ///   - fileTypes: Named wildcard filters for the Type pop-up.
    ///   - locations: Sidebar shortcuts. `nil` asks the file system for its
    ///     standard locations (home, root, volumes).
    ///   - icons: Row and location glyphs. Defaults to the text set.
    ///   - confirmTitle: Label for the confirm button. `nil` uses the mode
    ///     default ("Open"/"Save"/"Choose").
    ///   - canCreateDirectories: Whether New Folder appears. `nil` uses the
    ///     mode default (save only).
    ///   - showsHiddenFiles: Whether dot-files start visible.
    ///   - wildcard: Initial filter text.
    public init(
        mode: Mode,
        root: String,
        fileSystem: FileSystemProvider = LocalFileSystem(),
        chooses: FileKind? = nil,
        fileTypes: [FileType] = [],
        locations: [Location]? = nil,
        icons: Icons = .default,
        confirmTitle: String? = nil,
        canCreateDirectories: Bool? = nil,
        showsHiddenFiles: Bool = false,
        wildcard: String = ""
    ) {
        self.mode = mode
        self.chooses = chooses ?? Self.defaultChooses(for: mode)
        self.fileSystem = fileSystem
        self.usesNameField = mode == .save
        self.locations = locations ?? fileSystem.standardLocations()

        let canCreate = canCreateDirectories ?? (mode == .save)

        self.directoryList = DirectoryList(
            directory: root,
            fileSystem: fileSystem,
            showsFiles: self.chooses != .directories,
            icons: icons
        )
        self.pathControl = PathControl(path: root)

        super.init(title: Self.windowTitle(for: mode))

        isResizable = true
        minimumWindowSize = Size(width: 40, height: 16)

        directoryList.showsHidden = showsHiddenFiles
        hiddenToggle.setChecked(showsHiddenFiles)

        let column = VStack(spacing: 0)
        column.anchors = .fill()

        column.addSubview(pathControl)
        column.addSubview(Divider())                 // above the files section
        column.addSubview(browsingArea(icons: icons))
        column.addSubview(Divider())                 // below the files section

        // The Filter / Type / Name rows sit in their own spaced stack so a
        // blank line separates each field.
        let fields = VStack(spacing: 1)
        fields.addSubview(filterRow())

        if !fileTypes.isEmpty {
            fields.addSubview(typeRow(fileTypes: fileTypes))
        }

        if usesNameField {
            fields.addSubview(nameRow(canCreate: canCreate))
        }

        fields.addSubview(newFolderSection())
        column.addSubview(fields)

        column.addSubview(Divider())                 // between the fields and the footer/buttons
        column.addSubview(footer)
        body.addSubview(column)

        wire()

        // Apply the initial filter (explicit wildcard wins; otherwise the
        // first file type seeds it).
        let initialWildcard = !wildcard.isEmpty ? wildcard : (fileTypes.first?.patterns.joined(separator: ";") ?? "")
        wildcardField.setText(initialWildcard)
        applyWildcard(initialWildcard)

        addButton("Cancel", isCancel: true)
        addButton(confirmTitle ?? Self.defaultConfirmTitle(for: mode), isDefault: true) { [weak self] in
            guard let self else {
                return
            }

            self.onConfirm(self.chosenPath)
        }

        // Start in the file list, not on the default button.
        makeFirstResponder(directoryList)
        updateFooter()
    }

    /// The directory the browser is currently showing.
    public var currentDirectory: String {
        directoryList.directory
    }

    /// The highlighted entry's path, ignoring the `..` row (`nil` when the
    /// selection is `..` or nothing is selected).
    public var selectedPath: String? {
        selectedChoice?.path
    }

    /// The path confirm would return right now.
    public var chosenPath: String {
        let directory = directoryList.directory

        if usesNameField {
            let name = nameField.text
            return name.isEmpty ? directory : DirectoryTree.join(directory, name)
        }

        if chooses == .directories {
            if let entry = selectedChoice, entry.isDirectory {
                return entry.path
            }

            return directory
        }

        return selectedChoice?.path ?? directory
    }

    /// Roomy enough for the sidebar and list; `sizeToFit(in:)` clamps to the
    /// screen.
    public override var preferredSize: Size {
        let base = super.preferredSize
        return Size(width: max(base.width, 56), height: max(base.height + 17, 23))
    }

    // MARK: - Layout pieces

    // The breadcrumb sits above either a sidebar-plus-list split (when there
    // are locations) or the bare list.
    private func browsingArea(icons: Icons) -> TUIView {
        guard !locations.isEmpty else {
            return directoryList
        }

        let sidebar = ListView(items: locations.map { "\($0.icon) \($0.title)" })

        // A location jumps the browser as soon as it is highlighted — a single
        // click or an arrow-key move — matching the classic sidebar feel.
        let jump: (Int?) -> Void = { [weak self] index in
            guard let self, let index, self.locations.indices.contains(index) else {
                return
            }

            self.directoryList.setDirectory(self.locations[index].path)
        }

        sidebar.onSelectionChanged = jump
        sidebar.onActivate = { jump($0) }

        let split = SplitView(axis: .horizontal, first: sidebar, second: directoryList)
        split.minimumFirstLength = 10
        split.minimumSecondLength = 18
        split.setDividerPosition(16)
        return split
    }

    private func filterRow() -> TUIView {
        let row = HStack(spacing: 1)
        row.addSubview(Label("Filter:", style: CellStyle(flags: .bold)))
        wildcardField.maximumSize = Size(width: 999, height: 1)
        row.addSubview(wildcardField)
        row.addSubview(hiddenToggle)
        return row
    }

    private func typeRow(fileTypes: [FileType]) -> TUIView {
        let popup = PopUpButton(items: fileTypes.map(\.title), selectedIndex: 0)

        popup.onSelectionChanged = { [weak self] index in
            guard let self, fileTypes.indices.contains(index) else {
                return
            }

            let text = fileTypes[index].patterns.joined(separator: ";")
            self.wildcardField.setText(text)
            self.applyWildcard(text)
        }

        let row = HStack(spacing: 1)
        row.addSubview(Label("Type:", style: CellStyle(flags: .bold)))
        row.addSubview(popup)
        row.addSubview(TUIView())   // spacer keeps the pop-up leading
        return row
    }

    private func nameRow(canCreate: Bool) -> TUIView {
        let row = HStack(spacing: 1)
        row.addSubview(Label("Name:", style: CellStyle(flags: .bold)))
        nameField.maximumSize = Size(width: 999, height: 1)
        row.addSubview(nameField)

        if canCreate {
            row.addSubview(Button("New Folder") { [weak self] in
                self?.beginNewFolder()
            })
        }

        return row
    }

    private func newFolderSection() -> TUIView {
        newFolderRow.addSubview(Label("New folder:", style: CellStyle(flags: .bold)))
        newFolderField.maximumSize = Size(width: 999, height: 1)
        newFolderRow.addSubview(newFolderField)
        newFolderRow.isHidden = true
        return newFolderRow
    }

    // MARK: - Wiring

    private func wire() {
        directoryList.onSelectionChanged = { [weak self] entry in
            self?.selectionChanged(to: entry)
        }

        directoryList.onNavigate = { [weak self] directory in
            self?.pathControl.setPath(directory)
            self?.updateFooter()
        }

        directoryList.onActivateFile = { [weak self] _ in
            self?.defaultButton?.activate()
        }

        pathControl.onPathSelected = { [weak self] path in
            self?.directoryList.setDirectory(path)
        }

        nameField.onSubmit = { [weak self] _ in
            self?.defaultButton?.activate()
        }

        nameField.onChanged = { [weak self] _ in
            self?.updateFooter()
        }

        wildcardField.onChanged = { [weak self] text in
            self?.applyWildcard(text)
        }

        hiddenToggle.onChange = { [weak self] on in
            self?.directoryList.showsHidden = on
        }

        newFolderField.onSubmit = { [weak self] _ in
            self?.commitNewFolder()
        }
    }

    // MARK: - Selection

    // The selected entry, ignoring the `..` row (never a confirm target).
    private var selectedChoice: DirectoryList.Entry? {
        guard let entry = directoryList.selectedEntry, !entry.isParent else {
            return nil
        }

        return entry
    }

    private func selectionChanged(to entry: DirectoryList.Entry?) {
        // In save mode, clicking a file offers its name for overwrite.
        if usesNameField, let entry, !entry.isDirectory, !entry.isParent {
            nameField.setText(DirectoryTree.lastComponent(of: entry.path))
        }

        updateFooter()
    }

    private func applyWildcard(_ text: String) {
        directoryList.filterPatterns = text
            .split(whereSeparator: { $0 == ";" || $0 == "," || $0 == " " })
            .map(String.init)
        updateFooter()
    }

    private func updateFooter() {
        footer.text = chosenPath
    }

    // MARK: - New folder

    private func beginNewFolder() {
        newFolderField.setText("")
        newFolderRow.isHidden = false
        newFolderRow.relayout()
        makeFirstResponder(newFolderField)
    }

    private func commitNewFolder() {
        newFolderRow.isHidden = true
        newFolderRow.relayout()
        addDirectory(named: newFolderField.text)
        makeFirstResponder(directoryList)
    }

    // Creates a subdirectory of the current directory and selects it. Shared
    // by the New Folder field and exercised directly by tests.
    @discardableResult
    func addDirectory(named name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)

        guard !trimmed.isEmpty else {
            return false
        }

        let path = DirectoryTree.join(directoryList.directory, trimmed)

        guard fileSystem.createDirectory(at: path) else {
            return false
        }

        directoryList.reload()
        directoryList.selectPath(path)
        return true
    }

    // MARK: - Titles / presets

    private static func defaultChooses(for mode: Mode) -> FileKind {
        mode == .selectFolder ? .directories : .filesAndDirectories
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

    private static func defaultConfirmTitle(for mode: Mode) -> String {
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
