import Foundation

public enum SubjectSelection: Equatable, Sendable {
    case selected(PoseLandmarks)
    case rejected(FrameExclusionReason)
}

/// 상체 크기와 이전 프레임 위치를 기준으로 버스트 안의 대상을 유지한다.
public struct UpperBodySubjectSelector: Sendable {
    private var previousCenter: Point2D?

    public init() {}

    public mutating func reset() {
        previousCenter = nil
    }

    public mutating func select(from candidates: [PoseLandmarks]) -> SubjectSelection {
        let scored = candidates.compactMap(score)
        guard !scored.isEmpty else {
            // 사용자 크기의 머리가 보이면 어깨가 없어도 '사람 없음'이 아닌 '자세 평가 불가'다.
            // 작은 머리는 먼 배경 인물로 보고 '사람 없음'을 유지한다.
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
            let geometry = landmarks.upperBodyGeometry,
            geometry.shoulderWidth >= Tuning.minimumShoulderWidth
        else { return nil }
        let center = Point2D(
            x: geometry.centerX,
            y: geometry.shoulderY,
            confidence: geometry.assessableShoulderConfidence
        )
        return Candidate(landmarks: landmarks, center: center, shoulderWidth: geometry.shoulderWidth)
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
