// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Lettore",
    defaultLocalization: "it",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "LettoreCore", targets: ["LettoreCore"]),
        .library(name: "LettoreEngine", targets: ["LettoreEngine"]),
        .library(name: "LettoreSystem", targets: ["LettoreSystem"]),
        .library(name: "LettoreUI", targets: ["LettoreUI"]),
        .executable(name: "LettoreApp", targets: ["LettoreApp"])
    ],
    dependencies: [
        // Dipendenze esterne future (es. onnxruntime-swift)
    ],
    targets: [
        .target(
            name: "LettoreCore",
            dependencies: [],
            path: "Sources/LettoreCore"
        ),
        .target(
            name: "LettoreEngine",
            dependencies: ["LettoreCore"],
            path: "Sources/LettoreEngine"
        ),
        .target(
            name: "LettoreSystem",
            dependencies: ["LettoreCore"],
            path: "Sources/LettoreSystem"
        ),
        .target(
            name: "LettoreUI",
            dependencies: ["LettoreCore", "LettoreEngine", "LettoreSystem"],
            path: "Sources/LettoreUI"
        ),
        .executableTarget(
            name: "LettoreApp",
            dependencies: ["LettoreCore", "LettoreEngine", "LettoreSystem", "LettoreUI"],
            path: "Sources/LettoreApp"
        ),
        .testTarget(
            name: "LettoreCoreTests",
            dependencies: ["LettoreCore", "LettoreEngine", "LettoreSystem"],
            path: "Tests/LettoreCoreTests"
        )
    ]
)
