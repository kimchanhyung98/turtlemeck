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
            name: "TurtleCore"
        ),
        .executableTarget(name: "turtlemeck", dependencies: ["TurtleCore"]),
        .executableTarget(name: "analyze-image", dependencies: ["TurtleCore"], path: "tools/analyze-image"),
        .executableTarget(name: "workflow-tests", dependencies: ["TurtleCore"], path: "Tests/TurtleCoreTests")
    ]
)
