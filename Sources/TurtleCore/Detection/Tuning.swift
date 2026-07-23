import Foundation

/// 제품 데이터 검증 전의 잠정 품질·판정 값이다. 모델이나 도메인 흐름을 선택하는 설정이 아니다.
public enum Tuning {
    public static let minimumLandmarkConfidence = 0.15
    public static let minimumHeadAnchorConfidence = 0.5
    public static let minimumShoulderWidth = 0.08
    public static let maximumShoulderSlope = 0.18
    // 턱 괴기·기울기처럼 팔이나 자세가 어깨를 가리면 어깨 confidence가 무너진다(비정상 실측 0.14~0.31,
    // 정상 실측 최소 0.51). 이 아래면 '머리는 있으나 정상 판정 불가'로 비정상 증거 처리한다.
    // PoseNet 손목 채널은 배경 고정점 오검출(유령 손목)로 판정 근거에서 제외했다 — 2026-07-22 실측.
    public static let minimumAssessableShoulderConfidence = 0.35
    // 반대쪽 어깨 confidence가 낮을 때, 머리 인접 어깨보다 이만큼 위로 튄 점만
    // 의자·헤드레스트 오검출로 허용한다(정상 측면 실측 차이 0.125~0.225).
    public static let minimumSideShoulderVerticalSeparation = 0.08
    // (어깨midY − 신뢰 head anchor 중앙값 y)/어깨폭. anchor 중앙값 기준 실측: 정상 최소 0.945,
    // 옆 기움 0.70, 턱괴기+숙임 0.81. 임계는 정상 최소값 아래 여유(≥0.045)를 두고 잡는다.
    public static let minimumHeadShoulderGapRatio = 0.90
    // 어깨 없이 머리만 잡힌 후보가 사용자인지 원거리 배경 인물인지 가르는 눈 사이 거리 하한.
    // 착석 사용자 실측 0.05~0.10, 수 미터 밖 인물은 그 수분의 일 수준이다.
    public static let minimumSubjectEyeDistance = 0.03
    // 보정 시점 대비 구도(어깨 기준 위치·폭) 변화 허용치. 이탈 시 판정 대신 재보정을 안내한다.
    // 실측: 같은 구도의 버스트 간 변동은 midY ≤0.016 / 폭 ≤5%, 실제 구도 변경은 midY 0.072 / 폭 11~17%.
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
