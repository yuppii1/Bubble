// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Bubble",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Bubble", targets: ["BubbleMacOS"])
    ],
    dependencies: [
    ],
    targets: [
        .target(
            name: "BubbleCore",
            dependencies: [],
            path: "Sources/BubbleCore"
        ),
        .executableTarget(
            name: "BubbleMacOS",
            dependencies: ["BubbleCore"],
            path: "Sources/BubbleMacOS",
            exclude: ["TestMain.swift"],
            resources: [.process("banner.png")]
        ),
        .executableTarget(
            name: "BubbleCLI",
            dependencies: ["BubbleCore"],
            path: "Sources/BubbleMacOS",
            exclude: ["AITagger.swift", "FolderMonitor.swift", "ClipboardService.swift", "banner.png"],
            sources: ["TestMain.swift"]
        )
    ]
)
