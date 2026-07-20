import Foundation

/// 제품 데이터 검증 전의 잠정 품질·판정 값이다. 모델이나 도메인 흐름을 선택하는 설정이 아니다.
public enum Tuning {
    public static let minimumLandmarkConfidence = 0.5
    public static let minimumShoulderWidth = 0.08
    public static let maximumShoulderSlope = 0.18
    public static let frameBoundaryMargin = 0.015
    public static let roiErosionFraction = 0.15
    public static let maximumROIBoundaryContactRatio = 0.0
    public static let maximumROIOverlapRatio = 0.2
    public static let minimumROIPixels = 12
    public static let minimumValidDepthRatio = 0.8
    public static let minimumReferenceIQR = 1e-6
    public static let maximumSubjectJump = 0.3
    public static let minimumSubjectSeparation = 0.04
    public static let ambiguousSubjectSizeRatio = 0.8
    public static let maximumBurstMAD = 0.35
    public static let minimumValidFrames = 3
    public static let minimumValidFrameRatio = 0.6
    public static let requiredCalibrationBursts = 3
    public static let maximumCalibrationMAD = 0.25
    public static let requiredBadBursts = 2
    public static let requiredRecoveryBursts = 2
    public static let requiredNoEvalBursts = 3
    public static let defaultDepthDirection: DepthDirection = .largerIsNear

    public static func worseningMargin(for sensitivity: Sensitivity, baselineDispersion: Double) -> Double {
        let floor: Double
        switch sensitivity {
        case .low: floor = 0.45
        case .medium: floor = 0.35
        case .high: floor = 0.25
        }
        return max(floor, baselineDispersion * 3)
    }

    public static func recoveryMargin(baselineDispersion: Double) -> Double {
        max(0.12, baselineDispersion * 1.5)
    }
}
