// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "turtlemac",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "TurtleCore", targets: ["TurtleCore"]),
        .executable(name: "turtlemac", targets: ["turtlemac"]),
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
        .executableTarget(name: "turtlemac", dependencies: ["TurtleCore"]),
        .executableTarget(name: "analyze-image", dependencies: ["TurtleCore"], path: "tools/analyze-image")
    ]
)
