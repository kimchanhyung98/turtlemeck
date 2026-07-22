import AppKit
import Foundation
import TurtleCore

let paths = Array(CommandLine.arguments.dropFirst())
guard !paths.isEmpty else {
    FileHandle.standardError.write(Data("usage: analyze-image <image-path> [image-path ...]\n".utf8))
    exit(2)
}

func describe(_ name: String, _ point: Point2D?) -> String {
    guard let point else { return "\(name)=-" }
    return "\(name)=(\(String(format: "%.3f", point.x)),\(String(format: "%.3f", point.y)),c=\(String(format: "%.2f", point.confidence)))"
}

func printLandmarks(_ landmarks: PoseLandmarks) {
    print("landmarks  " + landmarks.namedPoints.map { describe($0.name, $0.point) }.joined(separator: " "))
    let anchors = landmarks.reliableHeadAnchors
    if let leftShoulder = landmarks.leftShoulder, let rightShoulder = landmarks.rightShoulder,
       let headX = Statistics.median(anchors.map(\.x)),
       let headY = Statistics.median(anchors.map(\.y)) {
        let shoulderWidth = hypot(leftShoulder.x - rightShoulder.x, leftShoulder.y - rightShoulder.y)
        // 게이트(Tuning.minimumHeadShoulderGapRatio)와 동일한 정의: 신뢰 head anchor 중앙값 기준.
        let gap = ((leftShoulder.y + rightShoulder.y) / 2 - headY) / shoulderWidth
        print("headShoulderGapRatio=\(String(format: "%.3f", gap)) shoulderWidth=\(String(format: "%.3f", shoulderWidth))")
        for (name, wrist) in [("leftWrist", landmarks.leftWrist), ("rightWrist", landmarks.rightWrist)] {
            guard let wrist else { continue }
            let ratio = hypot(wrist.x - headX, wrist.y - headY) / shoulderWidth
            print("\(name)HeadDistanceRatio=\(String(format: "%.3f", ratio))")
        }
    }
}

let detector = PoseDetector()
let depthProvider = CoreMLRelativeDepthProvider()
var selectors: [URL: UpperBodySubjectSelector] = [:]

for path in paths {
    let url = URL(fileURLWithPath: path)
    let directory = url.deletingLastPathComponent().standardizedFileURL
    guard
        let image = NSImage(contentsOf: url),
        let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    else {
        FileHandle.standardError.write(Data("could not load image: \(path)\n".utf8))
        exit(2)
    }

    if paths.count > 1 {
        print("path=\(path)")
    }

    do {
        let candidates = try detector.detectCandidates(cgImage: cgImage)
        var selector = selectors[directory, default: UpperBodySubjectSelector()]
        let selection = selector.select(from: candidates)
        selectors[directory] = selector
        switch selection {
        case .rejected(let reason):
            print("valid=false")
            print("reason=\(reason.rawValue)")
            if let first = candidates.first {
                printLandmarks(first)
            }
        case .selected(let landmarks):
            let depth = depthProvider.estimate(cgImage: cgImage)
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
            printLandmarks(landmarks)
        }
    } catch {
        FileHandle.standardError.write(Data("analysis failed for \(path): \(error)\n".utf8))
        exit(1)
    }
}
