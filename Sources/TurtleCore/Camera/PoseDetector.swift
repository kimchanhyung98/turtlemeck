import AVFoundation
import CoreMedia
import CoreGraphics
import Foundation
import Vision

public final class PoseDetector {
    public init() {}

    public func detect(sampleBuffer: CMSampleBuffer, include3D: Bool) throws -> PoseLandmarks {
        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .up, options: [:])
        return try perform(handler: handler, include3D: include3D)
    }

    public func detect(cgImage: CGImage, include3D: Bool) throws -> PoseLandmarks {
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        return try perform(handler: handler, include3D: include3D)
    }

    private func perform(handler: VNImageRequestHandler, include3D: Bool) throws -> PoseLandmarks {
        let bodyRequest = VNDetectHumanBodyPoseRequest()
        let faceRequest = VNDetectFaceLandmarksRequest()
        var requests: [VNRequest] = [bodyRequest, faceRequest]
        var body3DRequest: VNDetectHumanBodyPose3DRequest?

        if include3D, #available(macOS 14.0, *) {
            let request = VNDetectHumanBodyPose3DRequest()
            body3DRequest = request
            requests.append(request)
        }

        try handler.perform(requests)

        let body = bodyRequest.results?.first
        let face = faceRequest.results?.first

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
            pose3D: extract3D(from: body3DRequest?.results?.first)
        )
    }

    private func point(_ joint: VNHumanBodyPoseObservation.JointName, in observation: VNHumanBodyPoseObservation?) -> Point2D? {
        guard let recognized = try? observation?.recognizedPoint(joint) else {
            return nil
        }
        return Point2D(
            x: recognized.location.x,
            y: 1 - recognized.location.y,
            confidence: Double(recognized.confidence)
        )
    }

    @available(macOS 14.0, *)
    private func extract3D(from observation: VNHumanBodyPose3DObservation?) -> Pose3D? {
        guard let observation else {
            return nil
        }

        let centerShoulder = point3D(.centerShoulder, in: observation)
        let root = point3D(.root, in: observation)
        let spine = point3D(.spine, in: observation)
        let centerHead = point3D(.centerHead, in: observation)
        let topHead = point3D(.topHead, in: observation)
        let leftShoulder = point3D(.leftShoulder, in: observation) ?? centerShoulder?.offset(x: -0.2)
        let rightShoulder = point3D(.rightShoulder, in: observation) ?? centerShoulder?.offset(x: 0.2)

        return Pose3D(
            leftShoulder: leftShoulder,
            rightShoulder: rightShoulder,
            root: root,
            spine: spine,
            centerHead: centerHead,
            topHead: topHead
        )
    }

    @available(macOS 14.0, *)
    private func point3D(_ joint: VNHumanBodyPose3DObservation.JointName, in observation: VNHumanBodyPose3DObservation) -> Point3D? {
        guard let recognized = try? observation.recognizedPoint(joint) else {
            return nil
        }
        let position = recognized.position.columns.3
        return Point3D(
            x: Double(position.x),
            y: Double(position.y),
            z: Double(position.z),
            confidence: 0.9
        )
    }
}

private extension Double {
    var radiansToDegrees: Double {
        self * 180 / .pi
    }
}

private extension Point3D {
    func offset(x: Double) -> Point3D {
        Point3D(x: self.x + x, y: y, z: z, confidence: confidence)
    }
}
