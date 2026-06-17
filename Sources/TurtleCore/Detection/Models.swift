import Foundation

public enum Side: String, Codable, Equatable, Sendable {
    case left
    case right
}

public enum ViewpointBand: String, Codable, Equatable, Sendable {
    case front
    case threeQuarterLeft
    case threeQuarterRight
    case profileLeft
    case profileRight
    case unknown
}

public enum CameraPlacement: String, Codable, Equatable, CaseIterable, Sendable {
    case center
    case left
    case right
}

public enum Sensitivity: String, Codable, Equatable, CaseIterable, Sendable {
    case low
    case medium
    case high

    public var title: String {
        switch self {
        case .low:
            return "낮음"
        case .medium:
            return "보통"
        case .high:
            return "높음"
        }
    }

    public var description: String {
        switch self {
        case .low:
            return "큰 구부정만 알림(알림 적음)"
        case .medium:
            return "정확도와 알림 빈도의 균형"
        case .high:
            return "작은 구부정도 일찍 포착(알림 많음)"
        }
    }
}

public enum PostureAssessment: String, Codable, Equatable, Sendable {
    case good
    case bad
    case noEval
}

public enum PostureState: String, Codable, Equatable, Sendable {
    case good
    case bad
    case calibrating
    case noEval
    case paused
    case blocked
}

public enum AlertEvent: String, Codable, Equatable, Sendable {
    case cautionStarted
    case recovered
}

public enum SignalKind: String, Codable, Equatable, Hashable, Sendable {
    case profile2D
    case threeQuarter2D
    case front2D
    case body3D
}

public struct Point2D: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var confidence: Double

    public init(x: Double, y: Double, confidence: Double) {
        self.x = x
        self.y = y
        self.confidence = confidence
    }

    public var isReliable: Bool {
        confidence >= Tuning.minimumLandmarkConfidence
    }
}

public struct Point3D: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double
    public var confidence: Double

    public init(x: Double, y: Double, z: Double, confidence: Double) {
        self.x = x
        self.y = y
        self.z = z
        self.confidence = confidence
    }

    public var isReliable: Bool {
        confidence >= Tuning.minimumLandmarkConfidence
    }
}

public struct Pose3D: Codable, Equatable, Sendable {
    public var leftShoulder: Point3D?
    public var rightShoulder: Point3D?
    public var root: Point3D?
    public var spine: Point3D?
    public var centerHead: Point3D?
    public var topHead: Point3D?

    public init(
        leftShoulder: Point3D? = nil,
        rightShoulder: Point3D? = nil,
        root: Point3D? = nil,
        spine: Point3D? = nil,
        centerHead: Point3D? = nil,
        topHead: Point3D? = nil
    ) {
        self.leftShoulder = leftShoulder
        self.rightShoulder = rightShoulder
        self.root = root
        self.spine = spine
        self.centerHead = centerHead
        self.topHead = topHead
    }

    public func rotatedAroundY(degrees: Double) -> Pose3D {
        Pose3D(
            leftShoulder: leftShoulder?.rotatedAroundY(degrees: degrees),
            rightShoulder: rightShoulder?.rotatedAroundY(degrees: degrees),
            root: root?.rotatedAroundY(degrees: degrees),
            spine: spine?.rotatedAroundY(degrees: degrees),
            centerHead: centerHead?.rotatedAroundY(degrees: degrees),
            topHead: topHead?.rotatedAroundY(degrees: degrees)
        )
    }
}

extension Point3D {
    func rotatedAroundY(degrees: Double) -> Point3D {
        let radians = degrees * .pi / 180
        let cosine = cos(radians)
        let sine = sin(radians)
        return Point3D(
            x: x * cosine + z * sine,
            y: y,
            z: -x * sine + z * cosine,
            confidence: confidence
        )
    }
}

public struct PoseLandmarks: Codable, Equatable, Sendable {
    public var nose: Point2D?
    public var leftEye: Point2D?
    public var rightEye: Point2D?
    public var leftEar: Point2D?
    public var rightEar: Point2D?
    public var neck: Point2D?
    public var leftShoulder: Point2D?
    public var rightShoulder: Point2D?
    public var faceYawDegrees: Double?
    public var faceRollDegrees: Double?
    public var pose3D: Pose3D?

    public init(
        nose: Point2D? = nil,
        leftEye: Point2D? = nil,
        rightEye: Point2D? = nil,
        leftEar: Point2D? = nil,
        rightEar: Point2D? = nil,
        neck: Point2D? = nil,
        leftShoulder: Point2D? = nil,
        rightShoulder: Point2D? = nil,
        faceYawDegrees: Double? = nil,
        faceRollDegrees: Double? = nil,
        pose3D: Pose3D? = nil
    ) {
        self.nose = nose
        self.leftEye = leftEye
        self.rightEye = rightEye
        self.leftEar = leftEar
        self.rightEar = rightEar
        self.neck = neck
        self.leftShoulder = leftShoulder
        self.rightShoulder = rightShoulder
        self.faceYawDegrees = faceYawDegrees
        self.faceRollDegrees = faceRollDegrees
        self.pose3D = pose3D
    }
}

public struct ViewpointResult: Codable, Equatable, Sendable {
    public var band: ViewpointBand
    public var confidence: Double
    public var nearSide: Side?

    public init(band: ViewpointBand, confidence: Double, nearSide: Side? = nil) {
        self.band = band
        self.confidence = confidence
        self.nearSide = nearSide
    }
}

public struct PostureSignal: Codable, Equatable, Sendable {
    public var kind: SignalKind
    public var angleDegrees: Double
    public var confidence: Double

    public init(kind: SignalKind, angleDegrees: Double, confidence: Double) {
        self.kind = kind
        self.angleDegrees = angleDegrees
        self.confidence = confidence
    }
}

public struct AnalyzedFrame: Codable, Equatable, Sendable {
    public var assessment: PostureAssessment
    public var signal: PostureSignal?
    public var viewpoint: ViewpointResult?
    public var reason: String?

    public init(assessment: PostureAssessment, signal: PostureSignal? = nil, viewpoint: ViewpointResult? = nil, reason: String? = nil) {
        self.assessment = assessment
        self.signal = signal
        self.viewpoint = viewpoint
        self.reason = reason
    }
}

public struct Baseline: Codable, Equatable, Sendable {
    public var profileAngle: Double?
    public var frontHeadDropRatio: Double?
    public var threeQuarterAngle: Double?

    public init(profileAngle: Double?, frontHeadDropRatio: Double?, threeQuarterAngle: Double?) {
        self.profileAngle = profileAngle
        self.frontHeadDropRatio = frontHeadDropRatio
        self.threeQuarterAngle = threeQuarterAngle
    }
}
