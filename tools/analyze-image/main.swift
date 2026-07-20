import AppKit
import Foundation
import TurtleCore

guard let path = CommandLine.arguments.dropFirst().first else {
    FileHandle.standardError.write(Data("usage: analyze-image <image-path>\n".utf8))
    exit(2)
}

let url = URL(fileURLWithPath: path)
guard
    let image = NSImage(contentsOf: url),
    let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
else {
    FileHandle.standardError.write(Data("could not load image: \(path)\n".utf8))
    exit(2)
}

do {
    let candidates = try PoseDetector().detectCandidates(cgImage: cgImage)
    var selector = UpperBodySubjectSelector()
    switch selector.select(from: candidates) {
    case .rejected(let reason):
        print("valid=false")
        print("reason=\(reason.rawValue)")
    case .selected(let landmarks):
        let depth = CoreMLRelativeDepthProvider().estimate(cgImage: cgImage)
        let analysis = PostureFrameAnalyzer().analyze(landmarks: landmarks, depthMap: depth)
        print("valid=\(analysis.isValid)")
        if let feature = analysis.feature {
            print("feature=\(String(format: "%.6f", feature))")
        }
        if let iqr = analysis.quality.referenceIQR {
            print("referenceIQR=\(String(format: "%.6f", iqr))")
        }
        if let reason = analysis.exclusionReason {
            print("reason=\(reason.rawValue)")
        }
    }
} catch {
    FileHandle.standardError.write(Data("analysis failed: \(error)\n".utf8))
    exit(1)
}
