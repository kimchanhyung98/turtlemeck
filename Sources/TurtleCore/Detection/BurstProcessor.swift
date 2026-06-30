import Foundation

public struct TimedFrame: Equatable, Sendable {
    public var time: Double
    public var frame: AnalyzedFrame
    public var index: Int?

    public init(time: Double, frame: AnalyzedFrame, index: Int? = nil) {
        self.time = time
        self.frame = frame
        self.index = index
    }
}

public struct BurstVerdict: Equatable, Sendable {
    public var assessment: PostureAssessment

    public init(assessment: PostureAssessment) {
        self.assessment = assessment
    }
}

public struct BurstProcessor {
    private let sustainSeconds: Double
    private let minimumValidFrames: Int
    private let sparseBadMinimumConfidence: Double

    public init(sustainSeconds: Double = 1.8, minimumValidFrames: Int = 3, sparseBadMinimumConfidence: Double = 0.6) {
        self.sustainSeconds = sustainSeconds
        self.minimumValidFrames = minimumValidFrames
        self.sparseBadMinimumConfidence = sparseBadMinimumConfidence
    }

    /// 유효(noEval 아님) 프레임이 충분하면 bad가 sustainSeconds 이상 연속될 때 bad로 판정한다.
    /// ML 깊이/3D 신호는 프레임 밀도가 낮을 수 있어, sparse high-confidence bad evidence도 상태기계로 전달한다.
    public func process(_ frames: [TimedFrame]) -> BurstVerdict {
        let orderedFrames = frames.sorted { $0.time < $1.time }
        let validFrames = orderedFrames.filter { $0.frame.assessment != .noEval }
        guard validFrames.count >= minimumValidFrames else {
            if isSparseHighConfidenceBad(validFrames) {
                return BurstVerdict(assessment: .bad)
            }
            return BurstVerdict(assessment: .noEval)
        }

        var badRunStart: Double?
        var badRunEnd: Double?

        for item in orderedFrames {
            if item.frame.assessment == .bad {
                if badRunStart == nil {
                    badRunStart = item.time
                }
                badRunEnd = item.time
                if let start = badRunStart, let end = badRunEnd, end - start >= sustainSeconds {
                    return BurstVerdict(assessment: .bad)
                }
            } else {
                badRunStart = nil
                badRunEnd = nil
            }
        }

        return BurstVerdict(assessment: .good)
    }

    private func isSparseHighConfidenceBad(_ frames: [TimedFrame]) -> Bool {
        guard !frames.isEmpty else {
            return false
        }
        return frames.allSatisfy { item in
            guard
                item.frame.assessment == .bad,
                let signal = item.frame.signal,
                signal.confidence >= sparseBadMinimumConfidence
            else {
                return false
            }
            return signal.kind.isSparseBadEligible
        }
    }
}

private extension SignalKind {
    var isSparseBadEligible: Bool {
        switch self {
        case .depth3D, .body3D, .relativeDepth:
            return true
        case .profile2D, .threeQuarter2D, .front2D, .frontFace:
            return false
        }
    }
}
