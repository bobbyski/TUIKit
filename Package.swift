// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "TUIKit",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "TUIKit",
            targets: ["TUIKit"]
        ),
    ],
    dependencies: [
        // In-house only — RichSwift renders rich *content* (markup, tables,
        // panels, markdown, syntax); TUIKit owns the interactive layer.
        .package(url: "https://github.com/bobbyski/RichSwift.git", from: "0.1.0"),
        // swift-syntax powers the @Bound data-binding macro only (Data layer,
        // Phase 14.6): the one non-in-house dependency, confined to the macro
        // plugin so the library's runtime stays dependency-free.
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "603.0.0"),
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
        .testTarget(
            name: "TUIKitTests",
            dependencies: ["TUIKit"]
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
