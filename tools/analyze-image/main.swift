import AppKit
import Foundation
import TurtleCore

let arguments = CommandLine.arguments.dropFirst()

guard let path = arguments.first else {
    FileHandle.standardError.write(Data("usage: analyze-image <image-path>\n".utf8))
    exit(2)
}

let url = URL(fileURLWithPath: String(path))
guard
    let image = NSImage(contentsOf: url),
    let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
else {
    FileHandle.standardError.write(Data("could not load image: \(path)\n".utf8))
    exit(2)
}

do {
    let detector = PoseDetector()
    let landmarks = try detector.detect(cgImage: cgImage, include3D: SystemInfo.current.isAppleSilicon)
    let settings = Settings.defaults
    let analyzed = PostureAnalyzer().analyze(
        landmarks,
        baseline: settings.baseline,
        cameraPlacement: settings.cameraPlacement,
        sensitivity: settings.sensitivity
    )

    let signal = analyzed.signal.map { "\($0.kind.rawValue) angle=\(String(format: "%.1f", $0.angleDegrees)) confidence=\(String(format: "%.2f", $0.confidence))" } ?? "none"
    print("assessment=\(analyzed.assessment.rawValue)")
    print("viewpoint=\(analyzed.viewpoint?.band.rawValue ?? "unknown")")
    print("signal=\(signal)")
    if let reason = analyzed.reason {
        print("reason=\(reason)")
    }
} catch {
    FileHandle.standardError.write(Data("analysis failed: \(error)\n".utf8))
    exit(1)
}
