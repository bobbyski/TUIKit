/// A single directory's contents, browsed one level at a time.
///
/// Where `DirectoryTree` is a nested outline, `DirectoryList` is the classic
/// file-chooser pane: it shows exactly one directory, a `..` row leads back
/// to the parent, and activating a folder *replaces* the listing with that
/// folder's. It is the middle pane of `FileDialog`, but is useful on its own
/// wherever a flat, navigable file list fits better than a tree.
///
/// Rows are ordered `..`, then directories, then files, each prefixed with a
/// one-cell icon (see ``FileDialog/Icons``). Files are filtered by a wildcard
/// (``filterPatterns``) and, unless ``showsHidden`` is set, dot-files are
/// hidden; directories always appear so navigation is never filtered away.
///
/// ```swift
/// let list = DirectoryList(directory: "/Users/bobby", fileSystem: disk)
/// list.onSelectionChanged = { entry in footer.text = entry?.path ?? "" }
/// list.onNavigate         = { dir in crumbs.setPath(dir) }
/// list.onActivateFile     = { path in open(path) }
/// ```
///
/// All keyboard and mouse behavior is the wrapped `ListView`'s; this control
/// supplies the rows and turns activations into navigation or file events.
@MainActor
public final class DirectoryList: TUIView {
    /// One visible row: a path and what kind of thing it points at.
    public struct Entry: Equatable, Sendable {
        /// Absolute path of the entry.
        public var path: String

        /// Whether the entry is a directory (the `..` row is a directory).
        public var isDirectory: Bool

        /// Whether this is the `..` parent row.
        public var isParent: Bool
    }

    /// Absolute path of the directory currently shown.
    public private(set) var directory: String

    /// Whether files appear (directories always do).
    public var showsFiles: Bool {
        didSet {
            if showsFiles != oldValue {
                reload()
            }
        }
    }

    /// Whether dot-files appear.
    public var showsHidden: Bool {
        didSet {
            if showsHidden != oldValue {
                reload()
            }
        }
    }

    /// Wildcard patterns files must match (empty matches every file).
    public var filterPatterns: [String] = [] {
        didSet {
            if filterPatterns != oldValue {
                reload()
            }
        }
    }

    /// Glyphs drawn before each row.
    public var icons: FileDialog.Icons {
        didSet {
            if icons != oldValue {
                rebuildRows()
            }
        }
    }

    /// Called when the highlighted row changes (`nil` when cleared).
    public var onSelectionChanged: (Entry?) -> Void = { _ in }

    /// Called when the shown directory changes (through navigation or
    /// ``setDirectory(_:)``).
    public var onNavigate: (String) -> Void = { _ in }

    /// Called when a file row is activated (Return or double-click).
    public var onActivateFile: (String) -> Void = { _ in }

    // The wrapped list and the row model parallel to its items.
    private let list = ListView()
    private let fileSystem: FileSystemProvider
    private var rows: [Entry] = []

    /// Creates a directory list.
    ///
    /// - Parameters:
    ///   - directory: Absolute path of the directory to show first.
    ///   - fileSystem: Listing source. Defaults to the local file system.
    ///   - showsFiles: Whether files appear. Defaults to `true`.
    ///   - icons: Row glyphs. Defaults to the single-width text set.
    public init(
        directory: String,
        fileSystem: FileSystemProvider = LocalFileSystem(),
        showsFiles: Bool = true,
        icons: FileDialog.Icons = .default
    ) {
        self.directory = directory
        self.fileSystem = fileSystem
        self.showsFiles = showsFiles
        self.showsHidden = false
        self.icons = icons
        super.init(frame: .zero)

        list.anchors = .fill()
        addSubview(list)

        list.onSelectionChanged = { [weak self] index in
            self?.reportSelection(index)
        }

        list.onActivate = { [weak self] index in
            self?.activate(index)
        }

        reload()
    }

    /// The highlighted entry, when any.
    public var selectedEntry: Entry? {
        list.selectedIndex.flatMap { rows.indices.contains($0) ? rows[$0] : nil }
    }

    // The current row model, in display order — host/test read access.
    var visibleRows: [Entry] {
        rows
    }

    /// Shows a different directory and reloads (navigation event fires).
    ///
    /// - Parameter path: Absolute directory path.
    public func setDirectory(_ path: String) {
        guard path != directory else {
            return
        }

        directory = path
        reload()
        onNavigate(directory)
    }

    /// Re-reads the current directory from the file system.
    ///
    /// Selection lands on the first real entry (past `..`) when there is one,
    /// so a freshly shown directory always highlights content, not the way
    /// back out.
    public func reload() {
        rows = buildRows()
        rebuildRows()
        list.select(rows.count > 1 ? 1 : (rows.isEmpty ? nil : 0), notify: true)
    }

    /// Selects the row for a path, when it is currently visible.
    ///
    /// - Parameter path: Absolute path to highlight.
    public func selectPath(_ path: String) {
        guard let index = rows.firstIndex(where: { $0.path == path }) else {
            return
        }

        list.select(index, notify: true)
    }

    // Focus lands directly on the inner `ListView` (the sole focusable in
    // this subtree), so `DirectoryList` is not itself a tab stop.

    // MARK: - Rows

    // The entry model for the current directory, filtered and ordered.
    private func buildRows() -> [Entry] {
        var result: [Entry] = []

        if DirectoryTree.parent(of: directory) != directory {
            result.append(Entry(path: DirectoryTree.parent(of: directory), isDirectory: true, isParent: true))
        }

        var directories: [Entry] = []
        var files: [Entry] = []

        for entry in fileSystem.entries(at: directory) {
            if !showsHidden, entry.name.hasPrefix(".") {
                continue
            }

            let path = DirectoryTree.join(directory, entry.name)

            if entry.isDirectory {
                directories.append(Entry(path: path, isDirectory: true, isParent: false))
            } else if showsFiles, Glob.matchesAny(entry.name, patterns: filterPatterns) {
                files.append(Entry(path: path, isDirectory: false, isParent: false))
            }
        }

        let byName: (Entry, Entry) -> Bool = {
            DirectoryTree.lastComponent(of: $0.path).lowercased()
                < DirectoryTree.lastComponent(of: $1.path).lowercased()
        }

        result.append(contentsOf: directories.sorted(by: byName))
        result.append(contentsOf: files.sorted(by: byName))
        return result
    }

    // Pushes the current rows into the list as icon-prefixed titles.
    private func rebuildRows() {
        list.items = rows.map { entry in
            let icon: Character

            if entry.isParent {
                return "\(icons.parent) .."
            } else if entry.isDirectory {
                icon = icons.folder
            } else {
                icon = icons.file
            }

            return "\(icon) \(DirectoryTree.lastComponent(of: entry.path))"
        }
    }

    private func reportSelection(_ index: Int?) {
        guard let index, rows.indices.contains(index) else {
            onSelectionChanged(nil)
            return
        }

        onSelectionChanged(rows[index])
    }

    private func activate(_ index: Int) {
        guard rows.indices.contains(index) else {
            return
        }

        let entry = rows[index]

        if entry.isDirectory {
            setDirectory(entry.path)
        } else {
            onActivateFile(entry.path)
        }
    }
}
