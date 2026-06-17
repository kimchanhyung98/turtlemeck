import Foundation

public enum CalibrationRejectReason: String, Codable, Equatable, Sendable {
    case noReliableFrames
    case alreadySlouched
}

public enum CalibrationResult: Equatable, Sendable {
    case accepted(Baseline)
    case rejected(CalibrationRejectReason)
}

public struct Calibrator {
    public init() {}

    public func capture(from frames: [AnalyzedFrame]) -> CalibrationResult {
        let signals = frames.compactMap(\.signal).filter { $0.confidence >= 0.5 }
        guard !signals.isEmpty else {
            return .rejected(.noReliableFrames)
        }

        let profileAngle = percentile(signals.filter { $0.kind == .profile2D || $0.kind == .body3D }.map(\.angleDegrees), 0.75)
        if let profileAngle {
            guard profileAngle >= Tuning.profileBaselineRejectAngle else {
                return .rejected(.alreadySlouched)
            }
        }

        let frontRatio = percentile(signals.filter { $0.kind == .front2D }.map { $0.angleDegrees / 90 }, 0.75)
        let threeQuarterAngle = percentile(signals.filter { $0.kind == .threeQuarter2D }.map(\.angleDegrees), 0.75)

        guard profileAngle != nil || frontRatio != nil || threeQuarterAngle != nil else {
            return .rejected(.noReliableFrames)
        }

        return .accepted(Baseline(profileAngle: profileAngle, frontHeadDropRatio: frontRatio, threeQuarterAngle: threeQuarterAngle))
    }

    private func percentile(_ values: [Double], _ p: Double) -> Double? {
        let sorted = values.sorted()
        guard !sorted.isEmpty else {
            return nil
        }
        guard sorted.count > 1 else {
            return sorted[0]
        }

        let rank = max(0, min(1, p)) * Double(sorted.count - 1)
        let lower = Int(rank.rounded(.down))
        let upper = Int(rank.rounded(.up))
        let fraction = rank - Double(lower)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * fraction
    }
}
