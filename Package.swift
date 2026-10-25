// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ViewTube",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Atualizações dentro do app (Verificar Atualizações…), MIT.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0"),
    ],
    targets: [
        // App AppKit + SwiftUI: janela, barra de menus, WebKit e Now Playing.
        .executableTarget(
            name: "ViewTube",
            dependencies: [
                "ViewTubeCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
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
