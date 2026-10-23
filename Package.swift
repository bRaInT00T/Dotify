// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Dotify",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Docs only: `swift package generate-documentation`. Not linked into the app.
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.0"),
    ],
    targets: [
        .executableTarget(name: "Dotify", path: "Sources/Dotify"),
        .testTarget(name: "DotifyTests", dependencies: ["Dotify"], path: "Tests/DotifyTests"),
    ]
)
