import AppKit
import Foundation
import TurtleCore

let arguments = CommandLine.arguments.dropFirst()

guard let path = arguments.first else {
    FileHandle.standardError.write(Data("usage: analyze-image <image-path> [algorithm] [baseline-face-y]\n".utf8))
    exit(2)
}

let settings = Settings.defaults
let algorithmArgument = arguments.dropFirst().first
let algorithmID = algorithmArgument.flatMap { PostureAlgorithmID(rawValue: $0) } ?? settings.postureAlgorithm
// 3번째 인자(옵션): 정면 얼굴 baseline y 주입 — 미보정에서 noEval로 보류되는 전방머리 face proxy를 baseline-상대로 라이브 검증.
let baselineFaceY = arguments.dropFirst(2).first.flatMap { Double($0) }
let include3D: Bool
include3D = algorithmID.requests3D && SystemInfo.current.canRequestVision3D

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
    var landmarks = try detector.detect(cgImage: cgImage, include3D: include3D)
    if algorithmID.requestsCoreMLRelativeDepth {
        landmarks.relativeDepth = CoreMLRelativeDepthProvider().estimate(cgImage: cgImage, landmarks: landmarks)
    }

    // 선택형 알고리즘 ID를 2번째 인자로 받을 수 있다(미지정 시 기본값 = 적응 융합). 실제 앱과 동일 경로로 분석.
    let viewpoint = ViewpointClassifier().classify(landmarks)
    let context = PostureAnalysisContext(
        baseline: baselineFaceY.map { Baseline(profileAngle: nil, frontHeadDropRatio: nil, threeQuarterAngle: nil, frontFaceBottomY: $0) } ?? settings.baseline,
        sensitivity: settings.sensitivity,
        viewpoint: viewpoint
    )
    let analyzed = PostureAlgorithmFactory.make(algorithmID).analyze(landmarks, context: context)

    let signal = analyzed.signal.map { "\($0.kind.rawValue) angle=\(String(format: "%.1f", $0.angleDegrees)) confidence=\(String(format: "%.2f", $0.confidence))" } ?? "none"
    print("algorithm=\(algorithmID.rawValue)")
    print("assessment=\(analyzed.assessment.rawValue)")
    print("viewpoint=\(analyzed.viewpoint?.band.rawValue ?? "unknown")")
    print("signal=\(signal)")
    if let reason = analyzed.reason {
        print("reason=\(reason)")
    }
    // 진단: raw 랜드마크 — unknown 시점/noEval 원인 규명용(어떤 관절·confidence·yaw가 분류를 막는가)
    func f2(_ p: Point2D?) -> String {
        guard let p else { return "—" }
        return String(format: "(%.2f,%.2f|c%.2f)", p.x, p.y, p.confidence)
    }
    print("landmarks: nose=\(f2(landmarks.nose)) lEye=\(f2(landmarks.leftEye)) rEye=\(f2(landmarks.rightEye)) lEar=\(f2(landmarks.leftEar)) rEar=\(f2(landmarks.rightEar)) neck=\(f2(landmarks.neck)) lSh=\(f2(landmarks.leftShoulder)) rSh=\(f2(landmarks.rightShoulder))")
    let boxDesc = landmarks.faceBoundingBox.map { String(format: "%.3fx%.3f(a=%.4f y=%.3f)", $0.width, $0.height, $0.area, $0.y) } ?? "—"
    print("face: yaw=\(landmarks.faceYawDegrees.map { String(format: "%.1f", $0) } ?? "—") roll=\(landmarks.faceRollDegrees.map { String(format: "%.1f", $0) } ?? "—") pitch=\(landmarks.facePitchDegrees.map { String(format: "%.1f", $0) } ?? "—") box=\(boxDesc) pose3D=\(landmarks.pose3D == nil ? "nil" : "present")")
} catch {
    FileHandle.standardError.write(Data("analysis failed: \(error)\n".utf8))
    exit(1)
}
