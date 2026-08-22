import Foundation

// `swift run TUIKitGallery` from the TUIKit package still works: the gallery
// itself lives in the TUIGallery sibling (it shows TUIBoards, TUIDiagram and
// TUITerminal, which depend on TUIKit, so it cannot live here). This hands
// the terminal straight over to it — exec, not a child — so keys, resize and
// the exit all belong to the real gallery.

let packageRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()   // TUIKitGalleryLauncher
    .deletingLastPathComponent()   // Demo
    .deletingLastPathComponent()   // TUIKit
let gallery = packageRoot.deletingLastPathComponent().appendingPathComponent("TUIGallery").path

guard FileManager.default.fileExists(atPath: gallery + "/Package.swift") else {
    FileHandle.standardError.write(Data("The gallery lives in the TUIGallery sibling package, expected at \(gallery) — not found.\n".utf8))
    exit(1)
}

FileHandle.standardError.write(Data("TUIKitGallery lives in \(gallery) — launching it from there.\n".utf8))

let arguments = ["swift", "run", "--package-path", gallery, "TUIKitGallery"]
let argv = arguments.map { strdup($0) } + [nil]
execvp("swift", argv)
perror("execvp swift")
exit(1)
