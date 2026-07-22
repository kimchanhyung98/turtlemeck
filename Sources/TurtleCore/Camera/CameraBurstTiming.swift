import Foundation

public enum CameraBurstTiming {
    public static let warmupSeconds = 0.8
    public static let collectionSeconds = 2.4
    public static let processingGraceSeconds = 2.0
    public static let maximumAnalysisFrames = 5
    public static let minimumAnalysisFrameInterval = 0.4
    public static let maximumCalibrationAttempts = 3
    public static let calibrationRetryDelaySeconds = 10.0
    public static var totalDuration: Double { warmupSeconds + collectionSeconds }
    public static var finishDelay: Double { totalDuration + processingGraceSeconds }

    public static func collectionTime(elapsed: Double) -> Double? {
        guard elapsed >= warmupSeconds, elapsed <= totalDuration else { return nil }
        return elapsed - warmupSeconds
    }

    public static func shouldSample(collectionTime: Double, after previous: Double?) -> Bool {
        guard let previous else { return true }
        return collectionTime - previous >= minimumAnalysisFrameInterval
    }

    public static func remainingCheckDelay(
        configuredSeconds: Int,
        startedAt: Date,
        now: Date = Date()
    ) -> Int {
        max(0, Int(ceil(Double(configuredSeconds) - now.timeIntervalSince(startedAt))))
    }
}
