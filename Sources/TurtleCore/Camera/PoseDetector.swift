import CoreGraphics
import CoreMedia
import CoreML
import Foundation
import ImageIO
import Vision

public final class PoseDetector {
    private let poseNet = PoseNetDetector()

    public init() {}

    public func detectCandidates(
        sampleBuffer: CMSampleBuffer,
        orientation: CGImagePropertyOrientation = .up
    ) throws -> [PoseLandmarks] {
        let poseNetCandidates = (try? poseNet.detect(sampleBuffer: sampleBuffer)) ?? []
        if poseNetCandidates.contains(where: isUsableUpperBody) {
            return poseNetCandidates
        }
        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: orientation, options: [:])
        return merged(fallback: try perform(handler: handler), poseNet: poseNetCandidates)
    }

    public func detectCandidates(
        cgImage: CGImage,
        orientation: CGImagePropertyOrientation = .up
    ) throws -> [PoseLandmarks] {
        let poseNetCandidates = (try? poseNet.detect(cgImage: cgImage)) ?? []
        if poseNetCandidates.contains(where: isUsableUpperBody) {
            return poseNetCandidates
        }
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
        return merged(fallback: try perform(handler: handler), poseNet: poseNetCandidates)
    }

    /// Vision도 후보를 못 내면 PoseNet 부분 검출을 보존한다.
    /// 하류에서 '사람 없음'과 '머리는 있으나 어깨 미신뢰'를 구분하는 데 필요하다.
    private func merged(fallback: [PoseLandmarks], poseNet: [PoseLandmarks]) -> [PoseLandmarks] {
        fallback.isEmpty ? poseNet : fallback
    }

    private func perform(handler: VNImageRequestHandler) throws -> [PoseLandmarks] {
        let request = VNDetectHumanBodyPoseRequest()
        let devices = try request.supportedComputeStageDevices
        for (stage, supported) in devices {
            if let cpu = supported.first(where: { device in
                if case .cpu = device { return true }
                return false
            }) {
                request.setComputeDevice(cpu, for: stage)
            }
        }
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
            rightShoulder: point(.rightShoulder, in: observation),
            leftWrist: point(.leftWrist, in: observation),
            rightWrist: point(.rightWrist, in: observation)
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

    private func isUsableUpperBody(_ landmarks: PoseLandmarks) -> Bool {
        guard
            !landmarks.reliableHeadAnchors.isEmpty,
            let left = landmarks.leftShoulder, left.isReliable,
            let right = landmarks.rightShoulder, right.isReliable
        else { return false }
        return hypot(left.x - right.x, left.y - right.y) >= Tuning.minimumShoulderWidth
            && abs(left.y - right.y) <= Tuning.maximumShoulderSlope
    }
}
