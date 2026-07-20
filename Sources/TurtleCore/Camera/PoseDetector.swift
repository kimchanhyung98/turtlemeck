import CoreGraphics
import CoreMedia
import Foundation
import ImageIO
import Vision

public final class PoseDetector {
    public init() {}

    public func detectCandidates(
        sampleBuffer: CMSampleBuffer,
        orientation: CGImagePropertyOrientation = .up
    ) throws -> [PoseLandmarks] {
        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: orientation, options: [:])
        return try perform(handler: handler)
    }

    public func detectCandidates(
        cgImage: CGImage,
        orientation: CGImagePropertyOrientation = .up
    ) throws -> [PoseLandmarks] {
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
        return try perform(handler: handler)
    }

    private func perform(handler: VNImageRequestHandler) throws -> [PoseLandmarks] {
        let request = VNDetectHumanBodyPoseRequest()
        try handler.perform([request])
        return (request.results ?? []).map(landmarks)
    }

    private func landmarks(from observation: VNHumanBodyPoseObservation) -> PoseLandmarks {
        PoseLandmarks(
            nose: point(.nose, in: observation),
            leftEye: point(.leftEye, in: observation),
            rightEye: point(.rightEye, in: observation),
            leftEar: point(.leftEar, in: observation),
            rightEar: point(.rightEar, in: observation),
            neck: point(.neck, in: observation),
            leftShoulder: point(.leftShoulder, in: observation),
            rightShoulder: point(.rightShoulder, in: observation)
        )
    }

    private func point(_ joint: VNHumanBodyPoseObservation.JointName, in observation: VNHumanBodyPoseObservation) -> Point2D? {
        guard let recognized = try? observation.recognizedPoint(joint) else { return nil }
        // Vision 좌하단 원점을 분석 도메인의 좌상단 원점으로 명시적으로 변환한다.
        return Point2D(
            x: recognized.location.x,
            y: 1 - recognized.location.y,
            confidence: Double(recognized.confidence)
        )
    }
}
