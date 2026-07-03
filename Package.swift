// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

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
    ],
    targets: [
        .target(
            name: "TUIKit",
            dependencies: [
                .product(name: "RichSwift", package: "RichSwift"),
            ]
        ),
        // TUIKit re-exports RichSwift, so consumers (demo, tests, apps)
        // depend on TUIKit alone and get the RichSwift API automatically.
        .executableTarget(
            name: "TUIKitDemo",
            dependencies: ["TUIKit"],
            path: "Demo/TUIKitDemo"
        ),
        .testTarget(
            name: "TUIKitTests",
            dependencies: ["TUIKit"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
