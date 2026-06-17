import Foundation

public struct TimedFrame: Equatable, Sendable {
    public var time: Double
    public var frame: AnalyzedFrame

    public init(time: Double, frame: AnalyzedFrame) {
        self.time = time
        self.frame = frame
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

    public func process(_ frames: [TimedFrame]) -> BurstVerdict {
        let validFrames = frames.filter { $0.frame.assessment != .noEval }.sorted { $0.time < $1.time }
        guard validFrames.count >= minimumValidFrames else {
            return BurstVerdict(assessment: .noEval)
        }

        var badRunStart: Double?
        var badRunEnd: Double?

        for item in validFrames {
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
