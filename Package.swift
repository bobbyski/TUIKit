// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import Foundation
import CompilerPluginSupport

// The in-house dependencies resolve from local checkouts, not from GitHub.
//
// Bobby, 2026-08-22: "live local repos for now — until I finish the CI/CD
// server." The tags on GitHub lag whatever is being worked on across the
// family, and a change that spans TUIKit and the SDK cannot be built at all
// while one half is only committed locally. `canvas.detach()` is the worked
// example: it existed on the SDK's develop branch, unpushed, so ANSIDriver
// could not call it and terminals kept talking to a shell that had moved on.
//
// CodeEditorCore below has been a local path for the same reason since it and
// TUIKit began co-evolving; this extends that to the rest of the in-house set.
// swift-syntax stays remote — it is Apple's, it is tagged, and it is not
// something anyone here edits.
//
// Overridable so this survives a machine with a different layout, and so the
// CI/CD server can point at its own checkouts without editing the manifest.
let richSwiftPath = ProcessInfo.processInfo.environment["RICHSWIFT_PATH"]
    ?? "/Users/bobby/src/frameworks/RichSwift"

let vectorTerminalSDKPath = ProcessInfo.processInfo.environment["VECTORTERMINALSDK_PATH"]
    ?? "/Users/bobby/AIResearch/GraphicalTerminal/Code/VectorTerminalSDK"

let package = Package(
    name: "TUIKit",
    platforms: [
        // macOS 16 is VectorTerminalSDK's floor (Phase 10 VTG chrome). Was
        // macOS 15 through TUIKit 1.0 — flagged in NEEDS_HUMAN.md.
        .macOS("16.0"),
    ],
    products: [
        .library(
            name: "TUIKit",
            targets: ["TUIKit"]
        ),
        // The source-code editor (Phase 15). A separate product so an app
        // that only needs forms and menus never links grammars or diff
        // engines; see Docs/CodeEditorPlan.md.
        .library(
            name: "TUICodeEditor",
            targets: ["TUICodeEditor"]
        ),
    ],
    dependencies: [
        // In-house only — RichSwift renders rich *content* (markup, tables,
        // panels, markdown, syntax); TUIKit owns the interactive layer.
        .package(path: richSwiftPath),
        // swift-syntax powers the @Bound data-binding macro only (Data layer,
        // Phase 14.6): the one non-in-house dependency, confined to the macro
        // plugin so the library's runtime stays dependency-free.
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "603.0.0"),
        // In-house VectorTerminal Graphics wrapper (Phase 10): APC escape
        // sequences, retained vector scene, under-text layer. Raw VTG bytes
        // live only in the driver layer; plain terminals never see one.
        .package(path: vectorTerminalSDKPath),
        // The UI-free half of the editor: document, commands, tokenizer,
        // gutter models. Foundation-only by construction, so it stays
        // adoptable by a GUI editor. LOCAL PATH while the two co-evolve.
        .package(path: "../CodeEditorCore"),
    ],
    targets: [
        // Compiler-plugin target implementing the @Bound macro.
        .macro(
            name: "TUIKitMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        ),
        .target(
            name: "TUIKit",
            dependencies: [
                .product(name: "RichSwift", package: "RichSwift"),
                .product(name: "VectorTerminalSDK", package: "VectorTerminalSDK"),
                "TUIKitMacros",
            ]
        ),
        // TUIKit re-exports RichSwift, so consumers (demo, tests, apps)
        // depend on TUIKit alone and get the RichSwift API automatically.
        .executableTarget(
            name: "TUIKitDemo",
            dependencies: ["TUIKit"],
            path: "Demo/TUIKitDemo",
            resources: [
                // The Contact Book's seed data (US presidents), loaded via
                // Bundle.module at startup.
                .process("Resources"),
            ]
        ),
        .target(
            name: "TUICodeEditor",
            dependencies: [
                "TUIKit",
                .product(name: "CodeEditorCore", package: "CodeEditorCore"),
            ]
        ),
        .testTarget(
            name: "TUICodeEditorTests",
            dependencies: ["TUICodeEditor"]
        ),
        .testTarget(
            name: "TUIKitTests",
            dependencies: ["TUIKit"]
        ),
        // `swift run TUIKitGallery` — a launcher that execs the real gallery in
        // the TUIGallery sibling package (it cannot live here: it shows the
        // siblings, which depend on TUIKit).
        .executableTarget(
            name: "TUIKitGallery",
            path: "Demo/TUIKitGalleryLauncher"
        ),
        // `swift run TUIKitInlineDemo` — the inline presentation: a few rows
        // at the cursor asking for parameters, the shell continuing below.
        .executableTarget(
            name: "TUIKitInlineDemo",
            dependencies: ["TUIKit"],
            path: "Demo/TUIKitInlineDemo"
        ),
        // The tutorial's runnable milestones (Docs/Tutorial/): a library so
        // the anti-rot tests can render every chapter headlessly. Uses ONLY
        // public TUIKit API (no @testable) — the tutorial can't quietly rely
        // on internals.
        .target(
            name: "TUIKitTutorialMilestones",
            dependencies: ["TUIKit"],
            path: "Tutorial/Milestones"
        ),
        // `swift run TUIKitTutorial ch3` runs a chapter's milestone live.
        .executableTarget(
            name: "TUIKitTutorial",
            dependencies: ["TUIKitTutorialMilestones"],
            path: "Tutorial/Runner"
        ),
        // Renders every milestone through the headless driver so a chapter
        // that drifts from the API fails CI instead of rotting.
        .testTarget(
            name: "TUIKitTutorialTests",
            dependencies: ["TUIKitTutorialMilestones", "TUIKit"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
