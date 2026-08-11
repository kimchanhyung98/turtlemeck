import Foundation

/// 자세 판정에서 사용하는 순위 기반 통계를 제공한다.
public enum Statistics {
    /// 기존 판정과 호환되도록 짝수 표본에서는 가운데 두 값의 평균을 반환한다.
    public static func median(_ values: [Double]) -> Double? {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return nil }
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2
            : sorted[middle]
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
