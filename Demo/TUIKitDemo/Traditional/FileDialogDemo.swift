import Foundation
import TUIKit

// File Dialog Demo — a purpose-built window for exercising `FileDialog`, the
// Windows-style open/save chooser (Sources/TUIKit/Controls/FileDialog.swift).
//
// Each button presents the dialog in one of its three modes against the real
// file system, so you can drive every part of it interactively:
//
//   • a locations sidebar (Home / Computer / mounted Volumes),
//   • a breadcrumb bar over a one-directory-at-a-time list with a `..` row,
//   • the Filter field + Show-hidden checkbox + the Type pop-up, and
//   • New Folder (Save mode only).
//
// The "Emoji icons" checkbox swaps the single-width default glyphs (▸ · ↑ ⌂)
// for the emoji set (📁 📄 …) so you can see how each renders in your terminal.
extension DemoApp {
    func makeFileDialogDemo(index: Int) -> FloatingWindow {
        let app = self.app
        let window = FloatingWindow(
            title: "File Dialog \(index)",
            frame: Rect(x: 10 + index * 3, y: 3 + index * 2, width: 62, height: 18)
        )
        window.themeContext = .secondaryWindows
        window.onCloseRequest = { [weak window] in if let window { app.dismiss(window) } }

        let root = FileManager.default.currentDirectoryPath
        let status = Label("Pick an action — the chosen path shows here.", style: CellStyle(flags: .dim))

        // A shared Type pop-up filter set for the Open/Save dialogs.
        let fileTypes = [
            FileDialog.FileType(title: "Swift source (*.swift)", patterns: ["*.swift"]),
            FileDialog.FileType(title: "Text (*.txt, *.md)", patterns: ["*.txt", "*.md"]),
            FileDialog.FileType(title: "All files (*)", patterns: ["*"]),
        ]

        // Toggled by the checkbox; read when each dialog is built.
        var useEmoji = false
        func icons() -> FileDialog.Icons { useEmoji ? .emoji : .default }

        // Present a dialog centered on screen and report its result to `status`.
        func present(_ dialog: FileDialog, verb: String) {
            dialog.onConfirm = { status.text = "\(verb): \($0)" }
            dialog.onDismiss = { [weak dialog] in if let dialog { app.dismiss(dialog) } }
            dialog.sizeToFit(in: app.desktop.bounds.size)
            app.present(dialog)
            dialog.sizeToFit(in: app.desktop.bounds.size)
            status.text = "\(verb): choosing… (Esc cancels)"
        }

        let open = Button("&Open…") {
            present(
                FileDialog(mode: .open, root: root, fileTypes: fileTypes, icons: icons()),
                verb: "opened"
            )
        }

        let save = Button("&Save…") {
            let dialog = FileDialog(mode: .save, root: root, fileTypes: fileTypes, icons: icons())
            dialog.suggestedName = "Untitled.txt"
            present(dialog, verb: "save to")
        }

        let folder = Button("Choose &Folder…") {
            present(
                FileDialog(mode: .selectFolder, root: root, icons: icons()),
                verb: "folder"
            )
        }

        let emoji = Checkbox("Emoji icons (only if your terminal draws them one cell wide)")
        emoji.onChange = { useEmoji = $0 }

        window.content.setContent {
            VStack(spacing: 1, insets: EdgeInsets(all: 1)) {
                Label("FileDialog — Windows-style open / save / choose-folder").bold()
                Label(
                    "Sidebar · .. parent · Filter + Show hidden · Type pop-up · New Folder (Save).",
                    style: CellStyle(flags: .dim)
                )

                HStack(spacing: 2) { open; save; folder; Spacer() }
                emoji

                Spacer()
                status
            }
        }

        window.makeFirstResponder(open)
        return window
    }
}
