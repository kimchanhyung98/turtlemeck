import Foundation

public struct PostureTransition: Equatable, Sendable {
    public var state: PostureState
    public var alert: AlertEvent?

    public init(state: PostureState, alert: AlertEvent?) {
        self.state = state
        self.alert = alert
    }
}

public struct PostureStateMachine: Sendable {
    private let requiredBadBursts: Int
    private let requiredRecoveryBursts: Int
    private let requiredNoEvalBursts: Int
    private var badStreak = 0
    private var recoveryStreak = 0
    private var noEvalStreak = 0
    private var currentState: PostureState = .noEval

    public init(
        requiredBadBursts: Int = Tuning.requiredBadBursts,
        requiredRecoveryBursts: Int = Tuning.requiredRecoveryBursts,
        requiredNoEvalBursts: Int = Tuning.requiredNoEvalBursts
    ) {
        self.requiredBadBursts = max(1, requiredBadBursts)
        self.requiredRecoveryBursts = max(1, requiredRecoveryBursts)
        self.requiredNoEvalBursts = max(1, requiredNoEvalBursts)
    }

    public mutating func reset(to state: PostureState = .noEval) {
        badStreak = 0
        recoveryStreak = 0
        noEvalStreak = 0
        currentState = state
    }

    public mutating func apply(_ verdict: BurstVerdict) -> PostureTransition {
        switch verdict.evidence {
        case .worsened:
            noEvalStreak = 0
            recoveryStreak = 0
            guard currentState != .bad else {
                badStreak = 0
                return PostureTransition(state: .bad, alert: nil)
            }
            badStreak += 1
            if badStreak >= requiredBadBursts {
                badStreak = 0
                currentState = .bad
                return PostureTransition(state: .bad, alert: .cautionStarted)
            }
            return PostureTransition(state: currentState, alert: nil)

        case .normal:
            noEvalStreak = 0
            badStreak = 0
            guard currentState == .bad else {
                recoveryStreak = 0
                currentState = .good
                return PostureTransition(state: .good, alert: nil)
            }
            recoveryStreak += 1
            if recoveryStreak >= requiredRecoveryBursts {
                recoveryStreak = 0
                currentState = .good
                // 회복 이벤트는 통계용이며, 알림 여부는 NotificationPolicy가 별도로 거른다.
                return PostureTransition(state: .good, alert: .recovered)
            }
            return PostureTransition(state: .bad, alert: nil)

        case .insufficient:
            badStreak = 0
            recoveryStreak = 0
            noEvalStreak += 1
            if noEvalStreak >= requiredNoEvalBursts {
                currentState = .noEval
            }
            return PostureTransition(state: currentState, alert: nil)

        case .noEval:
            badStreak = 0
            recoveryStreak = 0
            noEvalStreak += 1
            if noEvalStreak >= requiredNoEvalBursts {
                currentState = .noEval
            }
            return PostureTransition(state: currentState, alert: nil)
        }
    }
}
