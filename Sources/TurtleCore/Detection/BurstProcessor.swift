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

    public init(sustainSeconds: Double = 1.8, minimumValidFrames: Int = 3) {
        self.sustainSeconds = sustainSeconds
        self.minimumValidFrames = minimumValidFrames
    }

    /// 유효(noEval 아님) 프레임이 충분하고 bad가 sustainSeconds 이상 연속될 때만 bad로 판정한다.
    /// 짧은 bad 스파이크나 중간 noEval/good은 연속을 끊어 false-positive를 줄인다.
    public func process(_ frames: [TimedFrame]) -> BurstVerdict {
        let orderedFrames = frames.sorted { $0.time < $1.time }
        let validFrameCount = orderedFrames.filter { $0.frame.assessment != .noEval }.count
        guard validFrameCount >= minimumValidFrames else {
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
}
