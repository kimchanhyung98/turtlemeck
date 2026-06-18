import Foundation

public struct PostureTransition: Equatable, Sendable {
    public var state: PostureState
    public var alert: AlertEvent?

    public init(state: PostureState, alert: AlertEvent?) {
        self.state = state
        self.alert = alert
    }
}

public struct PostureStateMachine {
    private let requiredBadBursts: Int
    private var badStreak = 0
    private var currentState: PostureState = .good

    public init(requiredBadBursts: Int = 2) {
        self.requiredBadBursts = max(1, requiredBadBursts)
    }

    public mutating func apply(_ verdict: BurstVerdict) -> PostureTransition {
        switch verdict.assessment {
        case .bad:
            badStreak += 1
            if badStreak >= requiredBadBursts {
                let wasBad = currentState == .bad
                currentState = .bad
                return PostureTransition(state: .bad, alert: wasBad ? nil : .cautionStarted)
            }
            return PostureTransition(state: currentState, alert: nil)
        case .good:
            badStreak = 0
            let wasBad = currentState == .bad
            currentState = .good
            return PostureTransition(state: .good, alert: wasBad ? .recovered : nil)
        case .noEval:
            currentState = .noEval
            return PostureTransition(state: .noEval, alert: nil)
        }
    }
}
