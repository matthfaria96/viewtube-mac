// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ViewTube",
    platforms: [.macOS(.v14)],
    targets: [
        // App AppKit + SwiftUI: janela, barra de menus, WebKit e Now Playing.
        .executableTarget(
            name: "ViewTube",
            dependencies: ["ViewTubeCore"],
            path: "Sources/ViewTube"
        ),
        // Núcleo puro (Foundation + CryptoKit): links, modos, SponsorBlock. Testável sem UI.
        .target(
            name: "ViewTubeCore",
            path: "Sources/ViewTubeCore"
        ),
        .testTarget(
            name: "ViewTubeCoreTests",
            dependencies: ["ViewTubeCore"],
            path: "Tests/ViewTubeCoreTests"
        ),
    ]
)
