import Foundation

/// 시점(viewpoint) band를 자동 분석 방식으로 매핑한다.
///
/// 데이터 근거(로컬 실측):
/// - 정면은 전방 머리 이동이 광축 방향이라 depth가 필요하다. 2D body pose가 비는 정면 웹캠 프레임에서는
///   Core ML 상대깊이 앵커를 만들 수 없으므로 `mlAuto`를 유지해 Vision 3D fallback을 함께 평가한다.
/// - 측면/3-4는 전방 이동이 2D 시상면에 직접 보이며, `profileGeometry`(profile2D/threeQuarter2D)만이 보정 임계(0.2)를 넘겨 실제 판정을 산출했다.
///
/// `unknown`은 판단 보류(nil) — 호출자가 직전 라우팅 방식을 유지한다.
public struct ViewpointRouter {
    public init() {}

    public func route(_ band: ViewpointBand) -> PostureAlgorithmID? {
        switch band {
        case .front:
            return .mlAuto
        case .profileLeft, .profileRight, .threeQuarterLeft, .threeQuarterRight:
            return .profileGeometry
        case .unknown:
            return nil
        }
    }
}
