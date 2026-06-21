import Foundation

public struct ViewpointClassifier: Sendable {
    public init() {}

    public func classify(_ pose: PoseLandmarks) -> ViewpointResult {
        let leftEar = pose.leftEar?.isTrackable == true
        let rightEar = pose.rightEar?.isTrackable == true
        let leftEye = pose.leftEye?.isTrackable == true
        let rightEye = pose.rightEye?.isTrackable == true
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
            // body 관절(눈/귀)이 없어도 정면 응시(yaw 작음)면 face 기반으로 front로 본다(약 신뢰).
            // 비정상 자세에서 Vision body pose가 실패해도 fusion의 얼굴 보조 신호 경로로 평가하게 한다.
            return ViewpointResult(band: .front, confidence: 0.45)
        }

        if leftEye != rightEye {
            let side: Side = leftEye ? .left : .right
            return angledResult(side: side, yawMagnitude: yawMagnitude, confidence: 0.62)
        }

        if hasFrontUpperBodySignal(pose), yawMagnitude < 25 {
            return ViewpointResult(band: .front, confidence: 0.58)
        }

        return ViewpointResult(band: .unknown, confidence: 0)
    }

    private func hasFrontUpperBodySignal(_ pose: PoseLandmarks) -> Bool {
        guard
            let leftShoulder = pose.leftShoulder, leftShoulder.isTrackable,
            let rightShoulder = pose.rightShoulder, rightShoulder.isTrackable
        else {
            return false
        }

        let shoulderWidth = abs(rightShoulder.x - leftShoulder.x)
        guard shoulderWidth > 0.08 else {
            return false
        }

        let hasHeadPoint = [
            pose.nose,
            pose.leftEye,
            pose.rightEye,
            pose.leftEar,
            pose.rightEar
        ].contains { $0?.isTrackable == true }
        return hasHeadPoint
    }

    private func angledResult(side: Side, yawMagnitude: Double, confidence: Double) -> ViewpointResult {
        if yawMagnitude >= 60 {
            return ViewpointResult(band: side == .left ? .profileLeft : .profileRight, confidence: confidence, nearSide: side)
        }
        return ViewpointResult(band: side == .left ? .threeQuarterLeft : .threeQuarterRight, confidence: max(0.58, confidence - 0.06), nearSide: side)
    }
}
