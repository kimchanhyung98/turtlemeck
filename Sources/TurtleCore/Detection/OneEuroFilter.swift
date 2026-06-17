import Foundation

/// 자세 각도 신호의 떨림을 줄이는 1€ 필터(Casiez et al.).
/// timestamp 경로는 움직임이 빠를수록 cutoff를 올려 지연을 줄이고, alpha 초기화는 기존 테스트용 EMA 호환 모드다.
public struct OneEuroFilter {
    private enum Mode {
        case oneEuro
        case ema(alpha: Double)
    }

    private let mode: Mode
    private let minCutoff: Double
    private let beta: Double
    private let dCutoff: Double
    private var previous: Double?
    private var previousDerivative = 0.0
    private var previousTimestamp: Double?
    private var syntheticTimestamp = 0.0

    public init(minCutoff: Double = 1.0, beta: Double = 0.05, dCutoff: Double = 1.0) {
        self.mode = .oneEuro
        self.minCutoff = max(0.001, minCutoff)
        self.beta = max(0, beta)
        self.dCutoff = max(0.001, dCutoff)
    }

    public init(alpha: Double) {
        self.mode = .ema(alpha: max(0, min(1, alpha)))
        self.minCutoff = 1
        self.beta = 0
        self.dCutoff = 1
    }

    public mutating func filter(_ value: Double) -> Double {
        syntheticTimestamp += 0.2
        return filter(value, timestamp: syntheticTimestamp)
    }

    public mutating func filter(_ value: Double, timestamp: Double) -> Double {
        switch mode {
        case .ema(let alpha):
            return filterEMA(value, alpha: alpha)
        case .oneEuro:
            return filterOneEuro(value, timestamp: timestamp)
        }
    }

    public mutating func reset() {
        previous = nil
        previousDerivative = 0
        previousTimestamp = nil
        syntheticTimestamp = 0
    }

    private mutating func filterEMA(_ value: Double, alpha: Double) -> Double {
        guard let previous else {
            self.previous = value
            return value
        }
        let filtered = previous * alpha + value * (1 - alpha)
        self.previous = filtered
        return filtered
    }

    private mutating func filterOneEuro(_ value: Double, timestamp: Double) -> Double {
        defer { previousTimestamp = timestamp }

        guard let previous, let previousTimestamp else {
            self.previous = value
            return value
        }

        let dt = max(timestamp - previousTimestamp, 0.001)
        let rawDerivative = (value - previous) / dt
        let derivativeAlpha = smoothingAlpha(cutoff: dCutoff, dt: dt)
        let derivative = smooth(rawDerivative, previous: previousDerivative, alpha: derivativeAlpha)
        previousDerivative = derivative

        let cutoff = minCutoff + beta * abs(derivative)
        let valueAlpha = smoothingAlpha(cutoff: cutoff, dt: dt)
        let filtered = smooth(value, previous: previous, alpha: valueAlpha)
        self.previous = filtered
        return filtered
    }

    private func smoothingAlpha(cutoff: Double, dt: Double) -> Double {
        let tau = 1 / (2 * Double.pi * cutoff)
        return 1 / (1 + tau / dt)
    }

    private func smooth(_ value: Double, previous: Double, alpha: Double) -> Double {
        alpha * value + (1 - alpha) * previous
    }
}
