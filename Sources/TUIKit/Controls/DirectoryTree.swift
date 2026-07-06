import Foundation

/// One entry inside a directory.
public struct FileSystemEntry: Equatable, Sendable {
    /// Entry name (no path components).
    public var name: String

    /// Whether the entry is a directory.
    public var isDirectory: Bool

    /// Creates an entry.
    ///
    /// - Parameters:
    ///   - name: Entry name (no path components).
    ///   - isDirectory: Whether the entry is a directory.
    public init(name: String, isDirectory: Bool) {
        self.name = name
        self.isDirectory = isDirectory
    }
}

/// Source of directory listings for file-oriented controls.
///
/// `DirectoryTree` (and later the open/save dialogs, per AICoding rule 30)
/// read the file system only through this protocol, so tests — and unusual
/// applications, like an archive browser — can supply their own.
public protocol FileSystemProvider {
    /// Entries directly inside a directory.
    ///
    /// Unreadable or nonexistent paths return an empty list; providers do
    /// not throw into the view layer.
    ///
    /// - Parameter path: Absolute directory path.
    /// - Returns: The directory's entries, unsorted.
    func entries(at path: String) -> [FileSystemEntry]
}

/// `FileSystemProvider` backed by the real file system.
public struct LocalFileSystem: FileSystemProvider {
    /// Creates a local file system provider.
    public init() {}

    /// Lists a directory via `FileManager`; failures read as empty.
    ///
    /// - Parameter path: Absolute directory path.
    /// - Returns: The directory's entries, unsorted.
    public func entries(at path: String) -> [FileSystemEntry] {
        let manager = FileManager.default

        guard let names = try? manager.contentsOfDirectory(atPath: path) else {
            return []
        }

        return names.map { name in
            var isDirectory: ObjCBool = false
            let entryPath = path.hasSuffix("/") ? path + name : path + "/" + name
            manager.fileExists(atPath: entryPath, isDirectory: &isDirectory)
            return FileSystemEntry(name: name, isDirectory: isDirectory.boolValue)
        }
    }
}

/// File-system outline: a `TreeView` over a `FileSystemProvider`.
///
/// Directories load lazily on first expansion (one listing per directory,
/// via `TreeNode`'s child provider), sorted directories-first then
/// case-insensitively by name. The control is useful on its own and is the
/// tree half of the future open/save dialogs (6.14).
///
/// ```swift
/// let files = DirectoryTree(root: "/Users/bobby/Projects")
/// files.onSelectionChanged = { path in preview(path) }
/// files.onActivate = { path in open(path) }
/// ```
///
/// All navigation, disclosure, and mouse behavior is `TreeView`'s; this
/// control only supplies the nodes and translates events into paths.
@MainActor
public final class DirectoryTree: TUIView {
    /// Absolute path of the root directory.
    public private(set) var rootPath: String

    /// Whether files appear (directories always do).
    public var showsFiles: Bool {
        didSet {
            if showsFiles != oldValue {
                reload()
            }
        }
    }

    /// Called when the selected path changes (`nil` when cleared).
    public var onSelectionChanged: (String?) -> Void = { _ in }

    /// Called when a path is activated with Return.
    public var onActivate: (String) -> Void = { _ in }

    // The wrapped outline; DirectoryTree is deliberately a composition —
    // its public surface is paths, not nodes.
    private let tree = TreeView()

    // Directory listings come only from here.
    private let fileSystem: FileSystemProvider

    // Paths known to be directories (recorded as nodes are built).
    private var directoryPaths: Set<String> = []

    /// Creates a directory tree.
    ///
    /// - Parameters:
    ///   - root: Absolute path of the root directory.
    ///   - fileSystem: Listing source. Defaults to the local file system.
    ///   - showsFiles: Whether files appear. Defaults to `true`.
    public init(
        root: String,
        fileSystem: FileSystemProvider = LocalFileSystem(),
        showsFiles: Bool = true
    ) {
        self.rootPath = root
        self.fileSystem = fileSystem
        self.showsFiles = showsFiles
        super.init(frame: .zero)

        tree.anchors = .fill()
        addSubview(tree)

        tree.onSelectionChanged = { [weak self] node in
            self?.onSelectionChanged(node.flatMap(Self.path(of:)))
        }

        tree.onActivate = { [weak self] node in
            if let path = Self.path(of: node) {
                self?.onActivate(path)
            }
        }

        reload()
    }

    /// The selected path, when any.
    public var selectedPath: String? {
        tree.selectedNode.flatMap(Self.path(of:))
    }

    /// Whether the selected path is a directory (`nil` when nothing is
    /// selected).
    public var selectedPathIsDirectory: Bool? {
        selectedPath.map { directoryPaths.contains($0) }
    }

    // Whether a path shown by this tree is a directory.
    func isDirectory(_ path: String) -> Bool {
        directoryPaths.contains(path)
    }

    /// Rebuilds the tree from the file system, collapsing everything.
    ///
    /// Call after external changes (files created, deleted, renamed).
    public func reload() {
        directoryPaths = []
        tree.roots = [makeNode(path: rootPath, title: Self.lastComponent(of: rootPath))]
    }

    /// Points the tree at a different root and reloads.
    ///
    /// - Parameter root: Absolute path of the new root directory.
    public func setRoot(_ root: String) {
        rootPath = root
        reload()
    }

    /// Expands the root directory (one level), a common starting state.
    public func expandRoot() {
        if let root = tree.roots.first {
            tree.expand(root)
        }
    }

    /// The directories currently expanded, parents before children — the
    /// session-persistence counterpart of ``expand(path:)``.
    public var expandedPaths: [String] {
        var result: [String] = []

        func walk(_ node: TreeNode) {
            guard node.isExpanded, let path = Self.path(of: node) else {
                return
            }

            result.append(path)

            for child in node.children {
                walk(child)
            }
        }

        for root in tree.roots {
            walk(root)
        }

        return result
    }

    /// Expands the directory at a path, expanding ancestors on the way
    /// (lazy children load as each level opens). Paths outside the tree
    /// are ignored.
    ///
    /// - Parameter path: Absolute directory path.
    public func expand(path: String) {
        guard var node = tree.roots.first, let rootValue = Self.path(of: node) else {
            return
        }

        let rootPrefix = rootValue.hasSuffix("/") ? rootValue : rootValue + "/"

        guard path == rootValue || path.hasPrefix(rootPrefix) else {
            return
        }

        tree.expand(node)

        while let current = Self.path(of: node), current != path {
            let next = node.children.first { child in
                guard let childPath = Self.path(of: child) else {
                    return false
                }

                return path == childPath || path.hasPrefix(childPath + "/")
            }

            guard let descendant = next else {
                return
            }

            node = descendant

            if let descendantPath = Self.path(of: descendant), directoryPaths.contains(descendantPath) {
                tree.expand(descendant)
            }
        }
    }

    // MARK: - Node building

    // Builds the node for one directory entry; directories get a lazy
    // child provider that lists them on first expansion.
    private func makeNode(path: String, title: String, isDirectory: Bool = true) -> TreeNode {
        let node: TreeNode

        if isDirectory {
            // [weak self]: nodes retain this closure and the tree retains
            // the nodes — a strong self here would be a retain cycle.
            node = TreeNode(title, childProvider: { [weak self] in
                guard let self else {
                    return []
                }

                var entries = self.fileSystem.entries(at: path)

                if !self.showsFiles {
                    entries.removeAll { !$0.isDirectory }
                }

                entries.sort {
                    if $0.isDirectory != $1.isDirectory {
                        return $0.isDirectory
                    }

                    return $0.name.lowercased() < $1.name.lowercased()
                }

                return entries.map { entry in
                    self.makeNode(
                        path: Self.join(path, entry.name),
                        title: entry.name,
                        isDirectory: entry.isDirectory
                    )
                }
            })
        } else {
            node = TreeNode(title)
        }

        node.representedValue = path

        if isDirectory {
            directoryPaths.insert(path)
        }

        return node
    }

    private static func path(of node: TreeNode) -> String? {
        node.representedValue as? String
    }

    // MARK: - Path helpers (shared with FileDialog)

    static func join(_ path: String, _ name: String) -> String {
        path.hasSuffix("/") ? path + name : path + "/" + name
    }

    static func lastComponent(of path: String) -> String {
        let trimmed = path.hasSuffix("/") && path.count > 1 ? String(path.dropLast()) : path
        let component = trimmed.split(separator: "/").last.map(String.init)
        return component ?? trimmed
    }

    static func parent(of path: String) -> String {
        let trimmed = path.hasSuffix("/") && path.count > 1 ? String(path.dropLast()) : path

        guard let slash = trimmed.lastIndex(of: "/") else {
            return trimmed
        }

        let parent = String(trimmed[..<slash])
        return parent.isEmpty ? "/" : parent
    }
}
