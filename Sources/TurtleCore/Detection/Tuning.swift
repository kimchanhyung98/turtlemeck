import Foundation

/// 제품 데이터로 확정하기 전의 임시 품질·판정 임계값이다.
public enum Tuning {
    public static let minimumLandmarkConfidence = 0.15
    public static let minimumHeadAnchorConfidence = 0.5
    public static let minimumShoulderWidth = 0.08
    public static let maximumShoulderSlope = 0.18
    // 악화 자세의 어깨 신뢰도는 0.14~0.31, 정상 자세의 최솟값은 0.51이었다.
    // 0.35 미만은 머리가 보여도 정상 판정 불가로 처리한다.
    public static let minimumAssessableShoulderConfidence = 0.35
    // 측면 구도에서 반대쪽 어깨가 머리 쪽 어깨보다 이 값 이상 위로 튀면 배경 오검출로 본다.
    // 정상 측면 구도의 실측 차이는 0.125~0.225였다.
    public static let minimumSideShoulderVerticalSeparation = 0.08
    // (어깨 기준 y - 머리 기준점 중앙값 y) / 어깨너비 비율의 하한이다.
    // 실측값은 정상 ≥0.945, 옆 기울임 0.70, 턱 괴고 숙임 0.81이며 0.90으로 여유를 둔다.
    public static let minimumHeadShoulderGapRatio = 0.90
    // 어깨가 없는 후보에서 사용자인지 먼 배경 인물인지 가르는 눈 사이 거리 하한이다.
    // 착석 사용자는 0.05~0.10, 먼 배경 인물은 그보다 훨씬 작았다.
    public static let minimumSubjectEyeDistance = 0.03
    // 보정 시점의 어깨 위치와 너비에서 벗어나면 판정하지 않고 재보정한다.
    // 같은 구도의 변동은 y ≤ 0.016·너비 ≤ 5%, 실제 구도 변화는 y = 0.072·너비 = 11~17%였다.
    public static let maximumShoulderAnchorShiftY = 0.05
    public static let maximumShoulderAnchorWidthRatio = 0.10
    public static let frameBoundaryMargin = 0.015
    public static let roiErosionFraction = 0.15
    public static let maximumROIBoundaryContactRatio = 0.55
    public static let maximumROIOverlapRatio = 0.2
    public static let minimumROIPixels = 12
    public static let minimumValidDepthRatio = 0.8
    public static let minimumReferenceIQR = 1e-6
    public static let maximumSubjectJump = 0.3
    public static let minimumSubjectSeparation = 0.04
    public static let ambiguousSubjectSizeRatio = 0.8
    public static let maximumBurstMAD = 0.35
    public static let minimumValidFrames = 2
    public static let minimumValidFrameRatio = 0.4
    public static let requiredCalibrationBursts = 1
    public static let maximumCalibrationMAD = 0.25
    public static let requiredBadBursts = 2
    public static let requiredRecoveryBursts = 2
    public static let requiredNoEvalBursts = 3
    public static let defaultDepthDirection: DepthDirection = .largerIsNear

    public static func worseningMargin(baselineDispersion: Double) -> Double {
        max(0.35, baselineDispersion * 3)
    }

    public static func recoveryMargin(baselineDispersion: Double) -> Double {
        max(0.25, worseningMargin(baselineDispersion: baselineDispersion) - 0.10)
    }
}
