import AVFoundation
import CoreMedia
import CoreGraphics
import Foundation
import simd
import Vision

public final class PoseDetector {
    public init() {}

    public func detect(sampleBuffer: CMSampleBuffer, include3D: Bool = false) throws -> PoseLandmarks {
        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .up, options: [:])
        return try perform(handler: handler, include3D: include3D)
    }

    public func detect(cgImage: CGImage, include3D: Bool = false) throws -> PoseLandmarks {
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        return try perform(handler: handler, include3D: include3D)
    }

    private func perform(handler: VNImageRequestHandler, include3D: Bool) throws -> PoseLandmarks {
        if include3D {
            if #available(macOS 14.0, *) {
                let bodyRequest = VNDetectHumanBodyPoseRequest()
                let faceRequest = VNDetectFaceLandmarksRequest()
                let request = VNDetectHumanBodyPose3DRequest()
                do {
                    try handler.perform([bodyRequest, faceRequest, request])
                    return landmarks(
                        body: bodyRequest.results?.first,
                        face: faceRequest.results?.first,
                        pose3D: extract3D(from: request.results?.first)
                    )
                } catch {
                    return try perform2D(handler: handler)
                }
            } else {
                return try perform2D(handler: handler)
            }
        } else {
            return try perform2D(handler: handler)
        }
    }

    private func perform2D(handler: VNImageRequestHandler) throws -> PoseLandmarks {
        let bodyRequest = VNDetectHumanBodyPoseRequest()
        let faceRequest = VNDetectFaceLandmarksRequest()
        try handler.perform([bodyRequest, faceRequest])
        return landmarks(body: bodyRequest.results?.first, face: faceRequest.results?.first, pose3D: nil)
    }

    private func landmarks(
        body: VNHumanBodyPoseObservation?,
        face: VNFaceObservation?,
        pose3D: Pose3D?
    ) -> PoseLandmarks {
        return PoseLandmarks(
            nose: point(.nose, in: body),
            leftEye: point(.leftEye, in: body),
            rightEye: point(.rightEye, in: body),
            leftEar: point(.leftEar, in: body),
            rightEar: point(.rightEar, in: body),
            neck: point(.neck, in: body),
            leftShoulder: point(.leftShoulder, in: body),
            rightShoulder: point(.rightShoulder, in: body),
            faceYawDegrees: face?.yaw?.doubleValue.radiansToDegrees,
            faceRollDegrees: face?.roll?.doubleValue.radiansToDegrees,
            // pitch·얼굴 박스: body pose 실패 시 face 보조 신호(삐딱·전방머리 판정)에 쓴다.
            facePitchDegrees: face?.pitch?.doubleValue.radiansToDegrees,
            faceBoundingBox: face.map {
                FaceBox(
                    x: Double($0.boundingBox.origin.x),
                    y: Double($0.boundingBox.origin.y),
                    width: Double($0.boundingBox.size.width),
                    height: Double($0.boundingBox.size.height)
                )
            },
            pose3D: pose3D
        )
    }

    private func point(_ joint: VNHumanBodyPoseObservation.JointName, in observation: VNHumanBodyPoseObservation?) -> Point2D? {
        guard let recognized = try? observation?.recognizedPoint(joint) else {
            return nil
        }
        // Vision 2D는 좌하단 원점 정규화 좌표 → 화면 기준(좌상단)으로 y를 뒤집는다.
        return Point2D(
            x: recognized.location.x,
            y: 1 - recognized.location.y,
            confidence: Double(recognized.confidence)
        )
    }

    private func extract3D(from observation: VNHumanBodyPose3DObservation?) -> Pose3D? {
        guard let observation else {
            return nil
        }
        if #available(macOS 14.0, *) {
            return Pose3D(
                leftShoulder: point3D(.leftShoulder, in: observation),
                rightShoulder: point3D(.rightShoulder, in: observation),
                spine: point3D(.spine, in: observation),
                centerHead: point3D(.centerHead, in: observation),
                topHead: point3D(.topHead, in: observation)
            )
        }
        return nil
    }

    @available(macOS 14.0, *)
    private func point3D(_ joint: VNHumanBodyPose3DObservation.JointName, in observation: VNHumanBodyPose3DObservation) -> Point3D? {
        guard let recognized = try? observation.recognizedPoint(joint) else {
            return nil
        }
        // Vision 3D 점에는 per-joint confidence가 없어 고정값을 둔다. 실제 품질 게이팅은 AlgorithmSupport.quality3D가 geometry와 신뢰도 높은 2D proxy를 함께 본다.
        let position = recognized.position
        return Point3D(
            x: Double(position.columns.3.x),
            y: Double(position.columns.3.y),
            z: Double(position.columns.3.z),
            confidence: 0.9
        )
    }
}

private extension Double {
    var radiansToDegrees: Double {
        self * 180 / .pi
    }
}
