// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "turtlemeck",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "TurtleCore", targets: ["TurtleCore"]),
        .executable(name: "turtlemeck", targets: ["turtlemeck"]),
        .executable(name: "analyze-image", targets: ["analyze-image"])
    ],
    targets: [
        .target(
            name: "TurtleCore",
            exclude: [
                "App/CLAUDE.md",
                "Camera/CLAUDE.md",
                "Detection/CLAUDE.md",
                "Launch/CLAUDE.md",
                "MenuBar/CLAUDE.md",
                "Notifications/CLAUDE.md",
                "Onboarding/CLAUDE.md",
                "Storage/CLAUDE.md"
            ]
        ),
        .executableTarget(name: "turtlemeck", dependencies: ["TurtleCore"]),
        .executableTarget(name: "analyze-image", dependencies: ["TurtleCore"], path: "tools/analyze-image"),
        .testTarget(name: "TurtleCoreTests", dependencies: ["TurtleCore"])
    ]
)
