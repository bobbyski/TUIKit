import Foundation

/// A document type — what a window opens, saves, and is dirty about.
///
/// ```text
///   Notes.md •            ← the window title carries the dirty marker
///   ┌ Save changes to Notes.md? ┐
///   │ [Don't Save] [Cancel] [Save] │   ← close asks, when dirty
/// ```
///
/// Hand it the app, the file types, and two closures — how to *read* bytes
/// into your content and how to *write* your content out — and it owns the
/// rest: Open… / Save / Save As… through `FileDialog`, the dirty flag and
/// title marker, a close-confirm `Dialog`, and a recents list (persisted
/// through `Preferences` when you give it one). OmegaCLIDE and the browser
/// both reinvented this; now it is one object.
///
/// ```swift
/// let document = DocumentController(app: app, types: [.init(title: "Markdown", patterns: ["*.md"])],
///     read: { data in editor.setText(String(decoding: data, as: UTF8.self)) },
///     write: { Data(editor.text.utf8) })
/// document.onTitleChanged = { window.title = $0 }
/// editor.onChanged = { _ in document.markDirty() }
/// closeItem.action = { document.close { app.dismiss(window) } }
/// ```
@MainActor
public final class DocumentController {
    /// Path of the file on disk, or `nil` for an unsaved new document.
    public private(set) var path: String?

    /// Whether the content differs from what is on disk.
    public private(set) var isDirty = false

    /// The name shown when there is no file yet.
    public var untitledName = "Untitled"

    /// Recently opened or saved paths, newest first (at most `recentsLimit`).
    public private(set) var recents: [String] = []

    /// How many recents to keep.
    public var recentsLimit = 10

    /// Where recents persist between runs, when set (key `recentDocuments`).
    public var recentsStore: Preferences? {
        didSet {
            loadRecents()
        }
    }

    /// Receives the title — name plus a ` •` while dirty — whenever it changes.
    public var onTitleChanged: (String) -> Void = { _ in }

    /// Called after the document's path or dirty state changes.
    public var onStateChanged: () -> Void = {}

    /// Called with an error message when reading or writing fails.
    public var onError: (String) -> Void = { _ in }

    /// File types offered by the dialogs.
    public var types: [FileDialog.FileType]

    /// Where the dialogs start.
    public var directory: String

    private weak var app: App?
    private let read: (Data) throws -> Void
    private let write: () throws -> Data

    /// Creates a controller.
    ///
    /// - Parameters:
    ///   - app: The app that presents the dialogs.
    ///   - types: File types the dialogs offer.
    ///   - directory: Where the dialogs start. Defaults to the current directory.
    ///   - read: Loads bytes into the content.
    ///   - write: Produces the bytes to save.
    public init(
        app: App,
        types: [FileDialog.FileType] = [],
        directory: String = FileManager.default.currentDirectoryPath,
        read: @escaping (Data) throws -> Void,
        write: @escaping () throws -> Data
    ) {
        self.app = app
        self.types = types
        self.directory = directory
        self.read = read
        self.write = write
    }

    /// The title: the file name (or `untitledName`), plus ` •` while dirty.
    public var title: String {
        let name = path.map { ($0 as NSString).lastPathComponent } ?? untitledName
        return isDirty ? name + " •" : name
    }

    // MARK: - State

    /// Notes that the content changed.
    public func markDirty() {
        guard !isDirty else {
            return
        }

        isDirty = true
        changed()
    }

    /// Notes that the content matches the disk again (after an external save).
    public func markClean() {
        guard isDirty else {
            return
        }

        isDirty = false
        changed()
    }

    /// Starts a new, untitled document. Asks first when the current one is dirty.
    ///
    /// - Parameter reset: Empties the content.
    public func new(reset: @escaping () -> Void) {
        confirmDiscard { [weak self] in
            guard let self else { return }
            reset()
            self.path = nil
            self.isDirty = false
            self.changed()
        }
    }

    // MARK: - Files

    /// Opens a file directly (no dialog).
    ///
    /// - Parameter filePath: The file.
    /// - Returns: `false` when reading failed (`onError` was called).
    @discardableResult
    public func open(_ filePath: String) -> Bool {
        guard let data = FileManager.default.contents(atPath: filePath) else {
            onError("Could not read \(filePath)")
            return false
        }

        do {
            try read(data)
        } catch {
            onError("Could not open \(filePath): \(error)")
            return false
        }

        path = filePath
        isDirty = false
        remember(filePath)
        changed()
        return true
    }

    /// Presents Open…, asking first when the current document is dirty.
    public func open() {
        confirmDiscard { [weak self] in
            self?.presentFileDialog(mode: .open) { [weak self] chosen in
                self?.open(chosen)
            }
        }
    }

    /// Saves to the current path, or presents Save As… when there is none.
    ///
    /// - Parameter completion: Runs after a successful save.
    public func save(then completion: @escaping () -> Void = {}) {
        guard let path else {
            saveAs(then: completion)
            return
        }

        if write(to: path) {
            completion()
        }
    }

    /// Presents Save As….
    ///
    /// - Parameter completion: Runs after a successful save.
    public func saveAs(then completion: @escaping () -> Void = {}) {
        presentFileDialog(mode: .save) { [weak self] chosen in
            guard let self else { return }
            if self.write(to: chosen) {
                completion()
            }
        }
    }

    /// Closes: straight through when clean, or after Save / Don't Save when
    /// dirty (Cancel does nothing).
    ///
    /// - Parameter completion: Runs when the close goes ahead.
    public func close(then completion: @escaping () -> Void) {
        confirmDiscard(completion)
    }

    // MARK: - Plumbing

    private func write(to filePath: String) -> Bool {
        do {
            let data = try write()
            try data.write(to: URL(fileURLWithPath: filePath), options: .atomic)
        } catch {
            onError("Could not save \(filePath): \(error)")
            return false
        }

        path = filePath
        isDirty = false
        remember(filePath)
        changed()
        return true
    }

    // Runs `proceed` at once when clean; otherwise asks Save / Don't Save / Cancel.
    private func confirmDiscard(_ proceed: @escaping () -> Void) {
        guard isDirty else {
            proceed()
            return
        }

        guard let app else {
            return
        }

        let dialog = Dialog(title: "Save changes to \(title.replacingOccurrences(of: " •", with: ""))?", message: "Your changes will be lost if you don't save them.")
        dialog.addButton("&Don't Save", isDestructive: true) { proceed() }
        dialog.addButton("&Cancel", isCancel: true)
        dialog.addButton("&Save", isDefault: true) { [weak self] in
            self?.save(then: proceed)
        }
        dialog.onDismiss = { [weak dialog, weak app] in
            if let dialog, let app {
                app.dismiss(dialog)
            }
        }
        dialog.sizeToFit(in: app.desktop.bounds.size)
        app.present(dialog)
        dialog.sizeToFit(in: app.desktop.bounds.size)
    }

    private func presentFileDialog(mode: FileDialog.Mode, chosen: @escaping (String) -> Void) {
        guard let app else {
            return
        }

        let dialog = FileDialog(mode: mode, root: directory, fileTypes: types)
        dialog.onConfirm = chosen
        dialog.onDismiss = { [weak dialog, weak app] in
            if let dialog, let app {
                app.dismiss(dialog)
            }
        }
        dialog.sizeToFit(in: app.desktop.bounds.size)
        app.present(dialog)
        dialog.sizeToFit(in: app.desktop.bounds.size)
    }

    private func remember(_ filePath: String) {
        recents.removeAll { $0 == filePath }
        recents.insert(filePath, at: 0)

        if recents.count > recentsLimit {
            recents.removeLast(recents.count - recentsLimit)
        }

        recentsStore?.set(recents.joined(separator: "\n"), forKey: "recentDocuments")
    }

    private func loadRecents() {
        guard let stored = recentsStore?.string(forKey: "recentDocuments") else {
            return
        }

        recents = stored.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    private func changed() {
        onTitleChanged(title)
        onStateChanged()
    }
}
