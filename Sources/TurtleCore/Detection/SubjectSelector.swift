import Foundation

public enum SubjectSelection: Equatable, Sendable {
    case selected(PoseLandmarks)
    case rejected(FrameExclusionReason)
}

/// 배열 순서가 아니라 상체 크기와 이전 프레임 위치로 한 버스트의 대상을 유지한다.
public struct UpperBodySubjectSelector: Sendable {
    private var previousCenter: Point2D?

    public init() {}

    public mutating func reset() {
        previousCenter = nil
    }

    public mutating func select(from candidates: [PoseLandmarks]) -> SubjectSelection {
        let scored = candidates.compactMap(score)
        guard !scored.isEmpty else { return .rejected(.noSubject) }

        let selected: Candidate
        if let previousCenter {
            let ordered = scored.sorted { distance($0.center, previousCenter) < distance($1.center, previousCenter) }
            guard distance(ordered[0].center, previousCenter) <= Tuning.maximumSubjectJump else {
                return .rejected(.ambiguousSubject)
            }
            if ordered.count > 1 {
                let firstDistance = distance(ordered[0].center, previousCenter)
                let secondDistance = distance(ordered[1].center, previousCenter)
                guard secondDistance - firstDistance >= Tuning.minimumSubjectSeparation else {
                    return .rejected(.ambiguousSubject)
                }
            }
            selected = ordered[0]
        } else {
            let ordered = scored.sorted { $0.shoulderWidth > $1.shoulderWidth }
            if ordered.count > 1, ordered[1].shoulderWidth >= ordered[0].shoulderWidth * Tuning.ambiguousSubjectSizeRatio {
                return .rejected(.ambiguousSubject)
            }
            selected = ordered[0]
        }
        previousCenter = selected.center
        return .selected(selected.landmarks)
    }

    private func score(_ landmarks: PoseLandmarks) -> Candidate? {
        guard
            !landmarks.reliableHeadAnchors.isEmpty,
            let left = landmarks.leftShoulder, left.isReliable,
            let right = landmarks.rightShoulder, right.isReliable
        else { return nil }
        let center = Point2D(x: (left.x + right.x) / 2, y: (left.y + right.y) / 2, confidence: min(left.confidence, right.confidence))
        return Candidate(landmarks: landmarks, center: center, shoulderWidth: distance(left, right))
    }

    private func distance(_ lhs: Point2D, _ rhs: Point2D) -> Double {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }
}

private struct Candidate: Sendable {
    var landmarks: PoseLandmarks
    var center: Point2D
    var shoulderWidth: Double
}
