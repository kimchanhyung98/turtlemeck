import Foundation

/// 버스트 간 시점 변화에 히스테리시스를 적용해 라우팅 방식을 안정적으로 전환한다.
///
/// - `hysteresis`(K)만큼 **연속**으로 새 시점이 지배해야 방식을 바꾼다(플래핑 방지 = "몇 틱 후 시점 분석").
/// - `unknown` 시점은 판단을 보류해 직전 방식을 유지하고, 진행 중이던 전환 streak을 끊는다.
public struct ViewpointRouteSelector {
    private let router = ViewpointRouter()
    private let hysteresis: Int
    public private(set) var current: PostureAlgorithmID
    private var pendingCandidate: PostureAlgorithmID?
    private var pendingCount = 0

    public init(initial: PostureAlgorithmID = .coreMLRelativeDepth, hysteresis: Int = 2) {
        self.current = initial
        self.hysteresis = max(1, hysteresis)
    }

    /// 한 버스트의 지배 시점 band를 입력하고 (갱신될 수 있는) 라우팅 방식을 돌려준다.
    @discardableResult
    public mutating func update(dominantBand: ViewpointBand) -> PostureAlgorithmID {
        guard let candidate = router.route(dominantBand) else {
            // unknown: 직전 방식 유지 + streak 끊기
            pendingCandidate = nil
            pendingCount = 0
            return current
        }
        if candidate == current {
            pendingCandidate = nil
            pendingCount = 0
            return current
        }
        if candidate == pendingCandidate {
            pendingCount += 1
        } else {
            pendingCandidate = candidate
            pendingCount = 1
        }
        if pendingCount >= hysteresis {
            current = candidate
            pendingCandidate = nil
            pendingCount = 0
        }
        return current
    }
}
