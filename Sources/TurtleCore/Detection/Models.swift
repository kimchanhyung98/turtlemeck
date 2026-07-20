import Foundation

public enum Sensitivity: String, Codable, Equatable, CaseIterable, Sendable {
    case low
    case medium
    case high

    public var title: String {
        switch self {
        case .low: "낮음"
        case .medium: "보통"
        case .high: "높음"
        }
    }

    public var description: String {
        switch self {
        case .low: "큰 변화만 알림"
        case .medium: "정확도와 알림 빈도의 균형"
        case .high: "작은 변화도 일찍 감지"
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
    case needsCalibration
}

public enum AlertEvent: String, Codable, Equatable, Sendable {
    case cautionStarted
    case recovered
}

public enum DepthDirection: String, Codable, Equatable, Sendable {
    case largerIsNear
    case smallerIsNear

    var multiplier: Double {
        self == .largerIsNear ? 1 : -1
    }
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

public struct NormalizedRect: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var area: Double { max(0, width) * max(0, height) }
    public var isInsideUnitSquare: Bool {
        x >= 0 && y >= 0 && maxX <= 1 && maxY <= 1 && width > 0 && height > 0
    }

    public func intersectionArea(with other: NormalizedRect) -> Double {
        let intersectionWidth = max(0, min(maxX, other.maxX) - max(x, other.x))
        let intersectionHeight = max(0, min(maxY, other.maxY) - max(y, other.y))
        return intersectionWidth * intersectionHeight
    }

    public var boundaryContactRatio: Double {
        guard area > 0 else { return 1 }
        if isInsideUnitSquare { return 0 }
        let insideWidth = max(0, min(maxX, 1) - max(x, 0))
        let insideHeight = max(0, min(maxY, 1) - max(y, 0))
        return 1 - (insideWidth * insideHeight / area)
    }

    public func inset(by fraction: Double) -> NormalizedRect {
        let fraction = min(0.49, max(0, fraction))
        return NormalizedRect(
            x: x + width * fraction,
            y: y + height * fraction,
            width: width * (1 - fraction * 2),
            height: height * (1 - fraction * 2)
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

    public init(
        nose: Point2D? = nil,
        leftEye: Point2D? = nil,
        rightEye: Point2D? = nil,
        leftEar: Point2D? = nil,
        rightEar: Point2D? = nil,
        neck: Point2D? = nil,
        leftShoulder: Point2D? = nil,
        rightShoulder: Point2D? = nil
    ) {
        self.nose = nose
        self.leftEye = leftEye
        self.rightEye = rightEye
        self.leftEar = leftEar
        self.rightEar = rightEar
        self.neck = neck
        self.leftShoulder = leftShoulder
        self.rightShoulder = rightShoulder
    }

    public var reliableHeadAnchors: [Point2D] {
        [nose, leftEye, rightEye, leftEar, rightEar].compactMap { $0 }.filter(\.isReliable)
    }
}

public struct RelativeDepthMap: Codable, Equatable, Sendable {
    public var width: Int
    public var height: Int
    public var values: [Double]
    public var direction: DepthDirection

    public init(width: Int, height: Int, values: [Double], direction: DepthDirection) {
        self.width = width
        self.height = height
        self.values = values
        self.direction = direction
    }

    public var isValid: Bool {
        width > 0 && height > 0 && values.count == width * height
    }

    public func values(in rect: NormalizedRect) -> [Double] {
        guard isValid, rect.isInsideUnitSquare else { return [] }
        let lowerX = max(0, min(width - 1, Int((rect.x * Double(width)).rounded(.down))))
        let upperX = max(lowerX, min(width - 1, Int((rect.maxX * Double(width)).rounded(.up)) - 1))
        let lowerY = max(0, min(height - 1, Int((rect.y * Double(height)).rounded(.down))))
        let upperY = max(lowerY, min(height - 1, Int((rect.maxY * Double(height)).rounded(.up)) - 1))
        var result: [Double] = []
        result.reserveCapacity((upperX - lowerX + 1) * (upperY - lowerY + 1))
        for y in lowerY...upperY {
            for x in lowerX...upperX {
                let value = values[y * width + x]
                if value.isFinite { result.append(value) }
            }
        }
        return result
    }
}

public struct DepthSummary: Codable, Equatable, Sendable {
    public var width: Int
    public var height: Int
    public var direction: DepthDirection
    public var minimum: Double?
    public var maximum: Double?

    public init(map: RelativeDepthMap) {
        width = map.width
        height = map.height
        direction = map.direction
        var lower: Double?
        var upper: Double?
        for value in map.values where value.isFinite {
            lower = lower.map { Swift.min($0, value) } ?? value
            upper = upper.map { Swift.max($0, value) } ?? value
        }
        minimum = lower
        maximum = upper
    }
}

public struct PostureROIs: Codable, Equatable, Sendable {
    public var head: NormalizedRect
    public var torso: NormalizedRect
    public var reference: NormalizedRect

    public init(head: NormalizedRect, torso: NormalizedRect, reference: NormalizedRect) {
        self.head = head
        self.torso = torso
        self.reference = reference
    }
}

public enum FrameExclusionReason: String, Codable, Equatable, Hashable, Sendable {
    case unstableCapture
    case noSubject
    case ambiguousSubject
    case missingHeadAnchor
    case missingNeck
    case missingShoulder
    case croppedUpperBody
    case excessiveRotation
    case invalidROIGeometry
    case insufficientDepthPixels
    case insufficientDepthRange
    case modelFailure
}

public struct FrameQuality: Codable, Equatable, Sendable {
    public var landmarkConfidence: Double
    public var headValidPixelRatio: Double
    public var torsoValidPixelRatio: Double
    public var referenceValidPixelRatio: Double
    public var referenceIQR: Double?
    public var roiBoundaryContactRatio: Double
    public var roiErosionFraction: Double

    public init(
        landmarkConfidence: Double = 0,
        headValidPixelRatio: Double = 0,
        torsoValidPixelRatio: Double = 0,
        referenceValidPixelRatio: Double = 0,
        referenceIQR: Double? = nil,
        roiBoundaryContactRatio: Double = 0,
        roiErosionFraction: Double = Tuning.roiErosionFraction
    ) {
        self.landmarkConfidence = landmarkConfidence
        self.headValidPixelRatio = headValidPixelRatio
        self.torsoValidPixelRatio = torsoValidPixelRatio
        self.referenceValidPixelRatio = referenceValidPixelRatio
        self.referenceIQR = referenceIQR
        self.roiBoundaryContactRatio = roiBoundaryContactRatio
        self.roiErosionFraction = roiErosionFraction
    }
}

public struct FrameAnalysis: Codable, Equatable, Sendable {
    public var landmarks: PoseLandmarks
    public var rois: PostureROIs?
    public var depth: DepthSummary?
    public var feature: Double?
    public var quality: FrameQuality
    public var exclusionReason: FrameExclusionReason?
    public var processingMilliseconds: [String: Double]

    public init(
        landmarks: PoseLandmarks,
        rois: PostureROIs? = nil,
        depth: DepthSummary? = nil,
        feature: Double? = nil,
        quality: FrameQuality = FrameQuality(),
        exclusionReason: FrameExclusionReason? = nil,
        processingMilliseconds: [String: Double] = [:]
    ) {
        self.landmarks = landmarks
        self.rois = rois
        self.depth = depth
        self.feature = feature
        self.quality = quality
        self.exclusionReason = exclusionReason
        self.processingMilliseconds = processingMilliseconds
    }

    public var isValid: Bool { feature != nil && exclusionReason == nil }
}

public enum BurstEvidence: String, Codable, Equatable, Sendable {
    case normal
    case worsened
    case insufficient
    case noEval
}

public struct BurstSummary: Codable, Equatable, Sendable {
    public var totalFrameCount: Int
    public var validFrameCount: Int
    public var medianFeature: Double?
    public var featureMAD: Double?
    public var exclusionCounts: [FrameExclusionReason: Int]

    public init(
        totalFrameCount: Int,
        validFrameCount: Int,
        medianFeature: Double?,
        featureMAD: Double?,
        exclusionCounts: [FrameExclusionReason: Int]
    ) {
        self.totalFrameCount = totalFrameCount
        self.validFrameCount = validFrameCount
        self.medianFeature = medianFeature
        self.featureMAD = featureMAD
        self.exclusionCounts = exclusionCounts
    }
}

public struct BurstVerdict: Codable, Equatable, Sendable {
    public var evidence: BurstEvidence
    public var summary: BurstSummary
    public var baselineDelta: Double?
    public var reason: String?

    public init(evidence: BurstEvidence, summary: BurstSummary, baselineDelta: Double? = nil, reason: String? = nil) {
        self.evidence = evidence
        self.summary = summary
        self.baselineDelta = baselineDelta
        self.reason = reason
    }

    public var assessment: PostureAssessment {
        switch evidence {
        case .normal: .good
        case .worsened: .bad
        case .insufficient, .noEval: .noEval
        }
    }

    public var requiresCalibration: Bool {
        reason == "baseline required" || reason == "capture configuration changed"
    }
}

public struct Baseline: Codable, Equatable, Sendable {
    public var center: Double
    public var dispersion: Double
    public var burstCount: Int
    public var createdAt: Date
    public var captureConfiguration: CaptureConfiguration

    public init(
        center: Double,
        dispersion: Double,
        burstCount: Int,
        createdAt: Date = Date(),
        captureConfiguration: CaptureConfiguration
    ) {
        self.center = center
        self.dispersion = dispersion
        self.burstCount = burstCount
        self.createdAt = createdAt
        self.captureConfiguration = captureConfiguration
    }
}

public struct CaptureConfiguration: Codable, Equatable, Sendable {
    public var cameraUniqueID: String
    public var width: Int
    public var height: Int
    public var orientation: String

    public init(cameraUniqueID: String, width: Int, height: Int, orientation: String) {
        self.cameraUniqueID = cameraUniqueID
        self.width = width
        self.height = height
        self.orientation = orientation
    }
}

public struct PostureDiagnostic: Codable, Equatable, Sendable {
    public var assessment: PostureAssessment
    public var productState: PostureState
    public var evidence: BurstEvidence
    public var summary: BurstSummary
    public var baselineCenter: Double?
    public var baselineDelta: Double?
    public var reason: String?
    public var frames: [TimedFrame]
    public var stageProcessingMilliseconds: [String: Double]
    public var debugArtifactPath: String?

    public init(
        assessment: PostureAssessment,
        productState: PostureState = .noEval,
        evidence: BurstEvidence,
        summary: BurstSummary,
        baselineCenter: Double? = nil,
        baselineDelta: Double? = nil,
        reason: String? = nil,
        frames: [TimedFrame] = [],
        stageProcessingMilliseconds: [String: Double] = [:],
        debugArtifactPath: String? = nil
    ) {
        self.assessment = assessment
        self.productState = productState
        self.evidence = evidence
        self.summary = summary
        self.baselineCenter = baselineCenter
        self.baselineDelta = baselineDelta
        self.reason = reason
        self.frames = frames
        self.stageProcessingMilliseconds = stageProcessingMilliseconds
        self.debugArtifactPath = debugArtifactPath
    }
}
