import Foundation

public struct ViewpointClassifier {
    public init() {}

    public func classify(_ pose: PoseLandmarks) -> ViewpointResult {
        let leftEar = pose.leftEar?.isReliable == true
        let rightEar = pose.rightEar?.isReliable == true
        let leftEye = pose.leftEye?.isReliable == true
        let rightEye = pose.rightEye?.isReliable == true
        let yaw = pose.faceYawDegrees
        let yawMagnitude = abs(yaw ?? 0)

        if leftEar && rightEar && yawMagnitude < 25 {
            return ViewpointResult(band: .front, confidence: 0.9)
        }

        if leftEar != rightEar {
            let side: Side = leftEar ? .left : .right
            return angledResult(side: side, yawMagnitude: yawMagnitude, confidence: 0.82)
        }

        if let yaw {
            if yawMagnitude >= 60 {
                return ViewpointResult(band: yaw < 0 ? .profileLeft : .profileRight, confidence: 0.72, nearSide: yaw < 0 ? .left : .right)
            }
            if yawMagnitude >= 20 {
                return ViewpointResult(band: yaw < 0 ? .threeQuarterLeft : .threeQuarterRight, confidence: 0.66, nearSide: yaw < 0 ? .left : .right)
            }
            if leftEye && rightEye {
                return ViewpointResult(band: .front, confidence: 0.7)
            }
        }

        if leftEye != rightEye {
            let side: Side = leftEye ? .left : .right
            return angledResult(side: side, yawMagnitude: yawMagnitude, confidence: 0.62)
        }

        return ViewpointResult(band: .unknown, confidence: 0)
    }

    private func angledResult(side: Side, yawMagnitude: Double, confidence: Double) -> ViewpointResult {
        if yawMagnitude >= 60 {
            return ViewpointResult(band: side == .left ? .profileLeft : .profileRight, confidence: confidence, nearSide: side)
        }
        return ViewpointResult(band: side == .left ? .threeQuarterLeft : .threeQuarterRight, confidence: max(0.58, confidence - 0.06), nearSide: side)
    }
}
