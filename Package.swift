// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DocMark",
    platforms: [.macOS("26.0")],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.6.0"),
    ],
    targets: [
        .target(
            name: "DocMarkCore",
            dependencies: [.product(name: "Markdown", package: "swift-markdown")]
        ),
        .executableTarget(name: "DocMark", dependencies: ["DocMarkCore"]),
        .testTarget(name: "DocMarkCoreTests", dependencies: ["DocMarkCore"]),
        .testTarget(name: "DocMarkTests", dependencies: ["DocMark", "DocMarkCore"]),
    ],
    swiftLanguageModes: [.v5]
)
