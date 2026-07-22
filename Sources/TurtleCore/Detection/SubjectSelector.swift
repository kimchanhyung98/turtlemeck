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
        guard !scored.isEmpty else {
            // 머리는 신뢰 가능하게 보이는데 어깨가 없으면 '사람 없음'이 아니라 '평가 불가 자세'다.
            // 단, 사용자 크기(눈 사이 거리)에 못 미치는 머리는 원거리 배경 인물이므로 사람 없음으로 남긴다.
            let headDetected = candidates.contains(where: isSubjectScaleHead)
            return .rejected(headDetected ? .missingShoulder : .noSubject)
        }

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
            let right = landmarks.rightShoulder, right.isReliable,
            // 원거리 배경 인물은 대상 후보로 선택하지 않는다.
            distance(left, right) >= Tuning.minimumShoulderWidth
        else { return nil }
        let center = Point2D(x: (left.x + right.x) / 2, y: (left.y + right.y) / 2, confidence: min(left.confidence, right.confidence))
        return Candidate(landmarks: landmarks, center: center, shoulderWidth: distance(left, right))
    }

    private func isSubjectScaleHead(_ landmarks: PoseLandmarks) -> Bool {
        guard
            !landmarks.reliableHeadAnchors.isEmpty,
            let leftEye = landmarks.leftEye, leftEye.confidence >= Tuning.minimumHeadAnchorConfidence,
            let rightEye = landmarks.rightEye, rightEye.confidence >= Tuning.minimumHeadAnchorConfidence
        else { return false }
        return distance(leftEye, rightEye) >= Tuning.minimumSubjectEyeDistance
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
