import Foundation

public enum CalibrationRejectReason: String, Codable, Equatable, Sendable {
    case noReliableBursts
    case unstableBaseline
    /// 머리는 감지됐지만 자세 때문에 평가 불가한 프레임이 우세 — 구도가 아니라 자세를 고치라고 안내한다.
    case postureUnassessable
}

public enum CalibrationResult: Equatable, Sendable {
    case accepted(Baseline)
    case rejected(CalibrationRejectReason)
}

public struct Calibrator: Sendable {
    public init() {}

    /// 보정에 쓸 수 있는 버스트 기준. 수집 루프의 조기 종료 판단도 같은 기준을 사용해야 한다.
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
            // 유효 버스트가 없는 이유가 '자세 때문에 평가 불가'(턱 괴기·머리 처짐 등)가 우세한 것이면
            // 구도 안내 대신 자세 안내를 할 수 있게 사유를 구분한다.
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
        guard let center = median(centers) else {
            return .rejected(.noReliableBursts)
        }
        let betweenBurstMAD = median(centers.map { abs($0 - center) }) ?? .infinity
        guard betweenBurstMAD <= Tuning.maximumCalibrationMAD else {
            return .rejected(.unstableBaseline)
        }
        let withinBurstMAD = median(valid.compactMap(\.featureMAD)) ?? 0
        return .accepted(Baseline(
            center: center,
            dispersion: max(withinBurstMAD, betweenBurstMAD),
            burstCount: valid.count,
            createdAt: now,
            captureConfiguration: captureConfiguration,
            // 보정 시점의 구도(어깨 기준)를 함께 저장해, 책상 배치·리드 각도 변경 시 재보정을 안내한다.
            shoulderMidY: median(valid.compactMap(\.medianShoulderMidY)),
            shoulderWidth: median(valid.compactMap(\.medianShoulderWidth))
        ))
    }

    private func median(_ values: [Double]) -> Double? {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return nil }
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}
