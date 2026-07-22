import Foundation

/// 판정 경로 전반이 공유하는 순위 통계. median은 percentile(0.5)과 같은 선형 보간 정의를 쓴다.
public enum Statistics {
    public static func median(_ values: [Double]) -> Double? {
        percentile(values, 0.5)
    }

    public static func percentile(_ values: [Double], _ fraction: Double) -> Double? {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return nil }
        let rank = min(1, max(0, fraction)) * Double(sorted.count - 1)
        let lower = Int(rank.rounded(.down))
        let upper = Int(rank.rounded(.up))
        return sorted[lower] + (sorted[upper] - sorted[lower]) * (rank - Double(lower))
    }

    public static func interquartileRange(_ values: [Double]) -> Double? {
        guard let lower = percentile(values, 0.25), let upper = percentile(values, 0.75) else { return nil }
        return upper - lower
    }
}
