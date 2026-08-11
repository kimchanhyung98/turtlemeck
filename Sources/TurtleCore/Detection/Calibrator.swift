import Foundation

public enum CalibrationRejectReason: String, Codable, Equatable, Sendable {
    case cameraPermissionDenied
    case cameraUnavailable
    case noReliableBursts
    case unstableBaseline
    /// 구도 안내 대신 자세 안내가 필요한 보정 실패다.
    case postureUnassessable
}

public enum CalibrationResult: Equatable, Sendable {
    case accepted(Baseline)
    case rejected(CalibrationRejectReason)
}

public struct Calibrator: Sendable {
    public init() {}

    /// 보정 버스트의 신뢰도 기준이며 수집 루프의 조기 종료에도 동일하게 적용한다.
    public static func isReliable(_ summary: BurstSummary) -> Bool {
        let unassessableCount = summary.exclusionCounts
            .filter { $0.key.isSubjectUnassessable }
            .reduce(0) { $0 + $1.value }
        return unassessableCount * 2 <= summary.totalFrameCount &&
            summary.validFrameCount >= Tuning.minimumValidFrames &&
            (summary.featureMAD ?? .infinity) <= Tuning.maximumBurstMAD &&
            summary.medianFeature != nil
    }

    public func capture(
        from summaries: [BurstSummary],
        captureConfiguration: CaptureConfiguration?,
        now: Date = Date()
    ) -> CalibrationResult {
        guard let captureConfiguration else {
            return .rejected(.noReliableBursts)
        }
        let valid = summaries.filter(Self.isReliable)
        guard valid.count >= Tuning.requiredCalibrationBursts else {
            // 자세 평가 불가가 과반이면 구도 오류와 구분한다.
            let unassessable = summaries
                .flatMap { $0.exclusionCounts }
                .filter { $0.key.isSubjectUnassessable }
                .reduce(0) { $0 + $1.value }
            let totalFrames = summaries.reduce(0) { $0 + $1.totalFrameCount }
            if unassessable >= Tuning.minimumValidFrames, unassessable * 2 > totalFrames {
                return .rejected(.postureUnassessable)
            }
            return .rejected(.noReliableBursts)
        }
        let centers = valid.compactMap(\.medianFeature)
        guard let center = Statistics.median(centers) else {
            return .rejected(.noReliableBursts)
        }
        let betweenBurstMAD = Statistics.median(centers.map { abs($0 - center) }) ?? .infinity
        guard betweenBurstMAD <= Tuning.maximumCalibrationMAD else {
            return .rejected(.unstableBaseline)
        }
        let withinBurstMAD = Statistics.median(valid.compactMap(\.featureMAD)) ?? 0
        return .accepted(Baseline(
            center: center,
            dispersion: max(withinBurstMAD, betweenBurstMAD),
            burstCount: valid.count,
            createdAt: now,
            captureConfiguration: captureConfiguration,
            shoulderMidY: Statistics.median(valid.compactMap(\.medianShoulderMidY)),
            shoulderWidth: Statistics.median(valid.compactMap(\.medianShoulderWidth))
        ))
    }
}
