import Foundation

public enum Tuning {
    /// 보정 저장/통계에 사용할 높은 신뢰도 기준.
    public static let minimumLandmarkConfidence = 0.5
    /// 실시간 추적은 Vision 웹캠 confidence가 낮게 나오는 경우가 많아 더 낮은 기준으로 신호를 만든다.
    public static let minimumTrackingConfidence = 0.2
    public static let profileBaselineRejectAngle = 55.0
    public static let mediumAbsoluteBadAngle = 58.0
    public static let frontRelativeDrop = 0.08
    public static let frontAbsoluteGoodRatio = 0.82
    public static let profileRelativeDrop = 7.0
    public static let headOnlyShoulderWidth = 0.32
    /// 양 눈을 잇는 선의 수평 대비 기울기(도). 이보다 크면 머리가 명확히 기울거나(삐딱) 크게 돌아간 것으로 보고
    /// "바른 자세(good)"에서 제외한다. 웹캠에서 바른 자세의 눈선 기울기 변동(실측 0~19°)보다 충분히 높게 잡아
    /// 바른 자세 오탐(false-bad)을 막는 보수적 값. 단일 프레임 노이즈는 버스트/상태기계 지속 요건이 흡수한다.
    public static let maxHeadTiltDegrees = 28.0
    /// 3D 이마-몸통 정규화 깊이차가 baseline 대비 이만큼 더 앞으로 나오면 주의(추세 신호).
    public static let depthRelativeForward = 0.06
    /// face 보조 신호: 정면 응시로 볼 yaw 상한. 이보다 크면 고개 돌림으로 보고 얼굴 위치 신호를 쓰지 않는다.
    public static let faceProxyMaxYaw = 25.0
    /// 얼굴 박스 하단 y가 baseline 대비 이만큼 낮아지면 전방머리/숙임(추세 신호). 잠정값 — 자체 로그 튜닝 필요.
    public static let frontFaceRelativeDrop = 0.18

    public static func absoluteBadAngle(for sensitivity: Sensitivity) -> Double {
        switch sensitivity {
        case .low:
            return 52
        case .medium:
            return mediumAbsoluteBadAngle
        case .high:
            return 64
        }
    }

    public static func frontAbsoluteBadRatio(for sensitivity: Sensitivity) -> Double {
        switch sensitivity {
        case .low:
            return 0.55
        case .medium:
            return 0.68
        case .high:
            return 0.78
        }
    }
}
