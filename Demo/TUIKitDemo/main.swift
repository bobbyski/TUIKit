import Foundation
import TUIKit   // re-exports RichSwift (Markup, Table, Syntax, …)

// TUIKitDemo — the living gallery of TUIKit capabilities.
//
// Per the AICoding rules, this demo doubles as a tutorial: it should always
// read as the recommended way to use the public API, and it grows a section
// for each control as it lands so it can be used for eyeball testing.
//
// Modes:
//   swift run TUIKitDemo                 static gallery (cells/views/layout)
//   swift run TUIKitDemo --interactive   declarative + manual example windows
//   swift run TUIKitDemo --events        live driver event viewer
//
// This file is deliberately tiny: it is the only place with top-level code (a
// requirement for a `main.swift`), so it does nothing but pick a mode. Each mode
// lives in its own file — `DemoApp` (the interactive desktop/menu shell) plus the
// window factories under `Declarative/` and `Traditional/`; `runEventViewer` in
// `Traditional/EventViewer.swift`; `runStaticGallery` in `Gallery.swift`.

if CommandLine.arguments.contains("--interactive") {
    try await DemoApp().run()
} else if CommandLine.arguments.contains("--events") {
    try await runEventViewer()
} else {
    runStaticGallery()
}
