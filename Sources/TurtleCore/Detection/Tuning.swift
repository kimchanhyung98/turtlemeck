import Foundation

public enum Tuning {
    public static let minimumLandmarkConfidence = 0.5
    public static let profileBaselineRejectAngle = 55.0
    public static let mediumAbsoluteBadAngle = 58.0
    public static let frontRelativeDrop = 0.08
    public static let profileRelativeDrop = 7.0
    public static let headOnlyShoulderWidth = 0.32

    public static func absoluteBadAngle(for sensitivity: Sensitivity) -> Double {
        switch sensitivity {
        case .low:
            return 52
        case .medium:
            return mediumAbsoluteBadAngle
        case .high:
            return 64
        }
    }
}
