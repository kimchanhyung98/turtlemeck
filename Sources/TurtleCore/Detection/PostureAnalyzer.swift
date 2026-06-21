import Foundation

public struct PostureAnalyzer: Sendable {
    private let classifier: ViewpointClassifier
    private let systemInfo: SystemInfo

    public init(classifier: ViewpointClassifier = ViewpointClassifier(), systemInfo: SystemInfo = .current) {
        self.classifier = classifier
        self.systemInfo = systemInfo
    }

    public func analyze(
        _ pose: PoseLandmarks,
        baseline: Baseline?,
        sensitivity: Sensitivity,
        viewpointOverride: ViewpointResult? = nil
    ) -> AnalyzedFrame {
        let viewpoint = viewpointOverride ?? classifier.classify(pose)
        // 양 어깨가 넓게 보이는 profile은 머리만 돌린 상황일 수 있어 보류(시점 자동 분류 기반).
        // 이 경우 2D CVA는 막되, Apple Silicon 3D 신호가 있으면 fallback으로 사용한다.
        let shouldHoldProfile2D = viewpoint.band.isProfile && isLikelyHeadOnlyRotation(pose)

        if !shouldHoldProfile2D, let frame = analyze2DProfileIfReliable(pose, viewpoint: viewpoint, baseline: baseline, sensitivity: sensitivity) {
            return frame
        }

        if systemInfo.isAppleSilicon, let signal = analyze3D(pose) {
            return AnalyzedFrame(
                assessment: classify(angle: signal.angleDegrees, baselineAngle: baseline?.bodyFrameAngle, sensitivity: sensitivity),
                signal: signal,
                viewpoint: viewpoint
            )
        }

        if shouldHoldProfile2D {
            return AnalyzedFrame(assessment: .noEval, viewpoint: viewpoint, reason: "head rotation without torso rotation")
        }

        if let frame = analyzeFrontOrThreeQuarter(pose, viewpoint: viewpoint, baseline: baseline, sensitivity: sensitivity) {
            return frame
        }

        return AnalyzedFrame(assessment: .noEval, viewpoint: viewpoint, reason: "insufficient reliable posture signal")
    }

    public static func headReference(in pose: PoseLandmarks, side: Side) -> Point2D? {
        switch side {
        case .left:
            return firstReliable([pose.leftEar, pose.leftEye, pose.nose])
        case .right:
            return firstReliable([pose.rightEar, pose.rightEye, pose.nose])
        }
    }

    private static func firstReliable(_ points: [Point2D?]) -> Point2D? {
        points.compactMap { $0 }.first { $0.isTrackable }
    }

    private func analyze2DProfileIfReliable(
        _ pose: PoseLandmarks,
        viewpoint: ViewpointResult,
        baseline: Baseline?,
        sensitivity: Sensitivity
    ) -> AnalyzedFrame? {
        guard let side = viewpoint.nearSide, viewpoint.band.isProfile else {
            return nil
        }

        guard
            let head = Self.headReference(in: pose, side: side),
            let shoulder = shoulderReference(in: pose, side: side)
        else {
            return nil
        }

        let angle = Geometry.cvaAngleDegrees(head: head, shoulder: shoulder)
        let signal = PostureSignal(kind: .profile2D, angleDegrees: angle, confidence: min(head.confidence, shoulder.confidence))
        return AnalyzedFrame(
            assessment: classify(angle: angle, baselineAngle: baseline?.profileAngle, sensitivity: sensitivity),
            signal: signal,
            viewpoint: viewpoint
        )
    }

    private func analyze3D(_ pose: PoseLandmarks) -> PostureSignal? {
        guard
            let pose3D = pose.pose3D,
            let angle = Geometry.bodySagittalAngleDegrees(from: pose3D)
        else {
            return nil
        }
        return PostureSignal(kind: .body3D, angleDegrees: angle, confidence: 0.85)
    }

    private func analyzeFrontOrThreeQuarter(
        _ pose: PoseLandmarks,
        viewpoint: ViewpointResult,
        baseline: Baseline?,
        sensitivity: Sensitivity
    ) -> AnalyzedFrame? {
        switch viewpoint.band {
        case .front:
            guard let current = frontHeadDropRatio(pose) else {
                return AnalyzedFrame(assessment: .noEval, viewpoint: viewpoint, reason: "front requires reliable head and shoulder landmarks")
            }
            let signal = PostureSignal(kind: .front2D, angleDegrees: current * 90, confidence: viewpoint.confidence)
            let assessment = PostureJudge.assess(signal, baseline: baseline, sensitivity: sensitivity)
            return AnalyzedFrame(
                assessment: assessment,
                signal: signal,
                viewpoint: viewpoint,
                reason: baseline?.frontHeadDropRatio == nil && assessment == .noEval ? "front requires baseline" : nil
            )
        case .threeQuarterLeft, .threeQuarterRight:
            guard
                let side = viewpoint.nearSide,
                let head = Self.headReference(in: pose, side: side),
                let shoulder = shoulderReference(in: pose, side: side)
            else {
                return nil
            }
            let angle = Geometry.cvaAngleDegrees(head: head, shoulder: shoulder)
            let signal = PostureSignal(kind: .threeQuarter2D, angleDegrees: angle, confidence: min(0.72, min(head.confidence, shoulder.confidence)))
            return AnalyzedFrame(
                assessment: classify(angle: angle, baselineAngle: baseline?.threeQuarterAngle, sensitivity: sensitivity),
                signal: signal,
                viewpoint: viewpoint
            )
        case .profileLeft, .profileRight, .unknown:
            return nil
        }
    }

    private func shoulderReference(in pose: PoseLandmarks, side: Side) -> Point2D? {
        switch side {
        case .left:
            return pose.leftShoulder?.isTrackable == true
                ? pose.leftShoulder
                : (pose.neck?.isTrackable == true ? pose.neck : nil)
        case .right:
            return pose.rightShoulder?.isTrackable == true
                ? pose.rightShoulder
                : (pose.neck?.isTrackable == true ? pose.neck : nil)
        }
    }

    private func isLikelyHeadOnlyRotation(_ pose: PoseLandmarks) -> Bool {
        guard
            let left = pose.leftShoulder, left.isTrackable,
            let right = pose.rightShoulder, right.isTrackable
        else {
            return false
        }
        return abs(right.x - left.x) >= Tuning.headOnlyShoulderWidth
    }

    private func frontHeadDropRatio(_ pose: PoseLandmarks) -> Double? {
        // 정면 신호는 절대 CVA가 아니라 어깨폭으로 정규화한 머리-어깨 수직 간격이다.
        guard
            let leftShoulder = pose.leftShoulder, leftShoulder.isTrackable,
            let rightShoulder = pose.rightShoulder, rightShoulder.isTrackable
        else {
            return nil
        }

        let shoulderWidth = abs(rightShoulder.x - leftShoulder.x)
        guard shoulderWidth > 0.05 else {
            return nil
        }

        let headCandidates = [pose.leftEar, pose.rightEar, pose.leftEye, pose.rightEye, pose.nose].compactMap { point -> Point2D? in
            guard let point, point.isTrackable else {
                return nil
            }
            return point
        }
        guard !headCandidates.isEmpty else {
            return nil
        }
        let headY = headCandidates.map(\.y).reduce(0, +) / Double(headCandidates.count)
        let shoulderY = (leftShoulder.y + rightShoulder.y) / 2
        return (shoulderY - headY) / shoulderWidth
    }

    private func classify(angle: Double, baselineAngle: Double?, sensitivity: Sensitivity) -> PostureAssessment {
        if let baselineAngle {
            return angle < baselineAngle - Tuning.profileRelativeDrop ? .bad : .good
        }
        return angle < Tuning.absoluteBadAngle(for: sensitivity) ? .bad : .good
    }
}

private extension ViewpointBand {
    var isProfile: Bool {
        self == .profileLeft || self == .profileRight
    }
}
