// swift-tools-version: 6.3
// Copyright (c) 2026 Bobby Skinner
// SPDX-License-Identifier: MIT
// See the LICENSE file at the repository root for the full text.

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
//
// `getenv`, not `ProcessInfo`'s environment: swift.org Swift 6.3.1, the release
// the Linux and Windows cross-compile SDKs pair with, crashes compiling any
// manifest that reads it against the macOS 27 SDK (ActiveUI's
// CROSSPLATFORM_PLAN.md, fact 8; TUIKIT_CHANGE_REQUESTS.md R16).
let richSwiftPath = getenv("RICHSWIFT_PATH").map { String(cString: $0) }
    ?? "/Users/bobby/src/frameworks/RichSwift"

let vectorTerminalSDKPath = getenv("VECTORTERMINALSDK_PATH").map { String(cString: $0) }
    ?? "/Users/bobby/AIResearch/GraphicalTerminal/Code/VectorTerminalSDK"

// Swift macros can be left out, for cross-compiles (ActiveUI's
// CROSSPLATFORM_PLAN.md). A macro target brings in swift-syntax, and
// swift-syntax's own manifest reads `ProcessInfo`'s environment, which crashes
// swift.org Swift 6.3.1, the release the Linux and Windows SDKs pair with.
// TUIKIT_NO_MACROS=1 leaves out the @Bound macro, its plugin target,
// swift-syntax, and the demo, whose model is @Bound throughout. Every other
// target is unchanged, and with the variable unset so is the whole package.
let macrosEnabled = getenv("TUIKIT_NO_MACROS") == nil
let noMacroSettings: [SwiftSetting] = macrosEnabled ? [] : [.define("TUIKIT_NO_MACROS")]

let package = Package(
    name: "TUIKit",
    platforms: [
        // macOS 15 (Sequoia): the real floor. Nothing in the family needs a
        // newer API — VectorTerminalSDK, RichSwift and CodeEditorCore all
        // allow 15, and there is no @available anywhere in-house. The old
        // "16.0" was a phantom release the toolchain clamped up to 26,
        // which silently demanded Tahoe for no gained capability.
        // (Bobby, 2026-09-21: "please go to 15".)
        .macOS("15.0"),
        // iOS 17 for BASICStudio on iPhone and iPad: the floor ActiveUI's iOS
        // apps use, and past the iOS 16 that `Duration` needs.
        .iOS("17.0"),
    ],
    products: [
        // Dynamic, not automatic. An automatic library is static, and
        // SwiftPM then emits no `libTUIKit` at all — it links the objects
        // straight into each executable it builds. That is invisible while
        // everything using TUIKit is a target in this package, and a wall
        // the moment something outside it links TUIKit: a CSharpSwift
        // program does exactly that (its C# classes subclass TUIKit's),
        // and had nothing to link against.
        .library(
            name: "TUIKit",
            type: .dynamic,
            targets: ["TUIKit"]
        ),
        // The source-code editor (Phase 15) is the sibling package
        // `Code/TUICodeEditor`, not a second product here: this library is
        // dynamic, and a second product in this package would carry its own
        // static copy of the TUIKit target — two TUIKits in any app linking
        // both, which SwiftPM (and Xcode 27) refuse outright.
    ],
    dependencies: [
        // In-house only — RichSwift renders rich *content* (markup, tables,
        // panels, markdown, syntax); TUIKit owns the interactive layer.
        .package(path: richSwiftPath),
    ] + (macrosEnabled ? [
        // swift-syntax powers the @Bound data-binding macro only (Data layer,
        // Phase 14.6): the one non-in-house dependency, confined to the macro
        // plugin so the library's runtime stays dependency-free.
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "603.0.0"),
    ] : []) + [
        // In-house VectorTerminal Graphics wrapper (Phase 10): APC escape
        // sequences, retained vector scene, under-text layer. Raw VTG bytes
        // live only in the driver layer; plain terminals never see one.
        .package(path: vectorTerminalSDKPath),
    ],
    targets: (macrosEnabled ? [
        // Compiler-plugin target implementing the @Bound macro.
        .macro(
            name: "TUIKitMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        ),
    ] : []) + [
        .target(
            name: "TUIKit",
            dependencies: [
                .product(name: "RichSwift", package: "RichSwift"),
                .product(name: "VectorTerminalSDK", package: "VectorTerminalSDK"),
            ] + (macrosEnabled ? ["TUIKitMacros"] : []),
            swiftSettings: noMacroSettings
        ),
    ] + (macrosEnabled ? [
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
    ] : []) + [
        .testTarget(
            name: "TUIKitTests",
            dependencies: ["TUIKit"],
            swiftSettings: noMacroSettings
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
