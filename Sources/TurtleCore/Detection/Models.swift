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

public enum PostureAlgorithmID: String, Codable, Equatable, CaseIterable, Sendable {
    case profileGeometry
    case frontProxy
    case bodyFrame3D
    case depthDelta
    case fusion

    public var title: String {
        switch self {
        case .profileGeometry:
            return "측면 기하"
        case .frontProxy:
            return "정면 보조"
        case .bodyFrame3D:
            return "3D 신체축"
        case .depthDelta:
            return "3D 깊이차"
        case .fusion:
            return "적응 융합"
        }
    }

    public var description: String {
        switch self {
        case .profileGeometry:
            return "측면/3-4 머리-어깨 단조 각"
        case .frontProxy:
            return "정면 어깨폭 정규화 추세"
        case .bodyFrame3D:
            return "3D 신체 좌표계 기반 시상각"
        case .depthDelta:
            return "이마-몸통 전방 깊이차"
        case .fusion:
            return "시점/플랫폼에 따라 자동 선택(권장)"
        }
    }

    public var requests3D: Bool {
        switch self {
        case .bodyFrame3D, .depthDelta:
            return true
        case .profileGeometry, .frontProxy, .fusion:
            return false
        }
    }
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
    /// 자세 추적이 지속적으로 실패해(noEval 연속) 개인 기준자세 데이터가 필요한 상태.
    case needsCalibration
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
    case depth3D
    case frontFace

    public var label: String {
        switch self {
        case .profile2D:
            return "측면각"
        case .threeQuarter2D:
            return "3-4각"
        case .front2D:
            return "정면비"
        case .body3D:
            return "3D시상각"
        case .depth3D:
            return "깊이차"
        case .frontFace:
            return "얼굴위치"
        }
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

    public var isTrackable: Bool {
        confidence >= Tuning.minimumTrackingConfidence
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

    public var isTrackable: Bool {
        confidence >= Tuning.minimumTrackingConfidence
    }
}

public struct Pose3D: Codable, Equatable, Sendable {
    public var leftShoulder: Point3D?
    public var rightShoulder: Point3D?
    public var spine: Point3D?
    public var centerHead: Point3D?
    public var topHead: Point3D?

    public init(
        leftShoulder: Point3D? = nil,
        rightShoulder: Point3D? = nil,
        spine: Point3D? = nil,
        centerHead: Point3D? = nil,
        topHead: Point3D? = nil
    ) {
        self.leftShoulder = leftShoulder
        self.rightShoulder = rightShoulder
        self.spine = spine
        self.centerHead = centerHead
        self.topHead = topHead
    }

    public func rotatedAroundY(degrees: Double) -> Pose3D {
        Pose3D(
            leftShoulder: leftShoulder?.rotatedAroundY(degrees: degrees),
            rightShoulder: rightShoulder?.rotatedAroundY(degrees: degrees),
            spine: spine?.rotatedAroundY(degrees: degrees),
            centerHead: centerHead?.rotatedAroundY(degrees: degrees),
            topHead: topHead?.rotatedAroundY(degrees: degrees)
        )
    }
}

private extension Point3D {
    func rotatedAroundY(degrees: Double) -> Point3D {
        let radians = degrees * .pi / 180
        let cosValue = cos(radians)
        let sinValue = sin(radians)
        return Point3D(
            x: x * cosValue + z * sinValue,
            y: y,
            z: -x * sinValue + z * cosValue,
            confidence: confidence
        )
    }
}

public struct FaceBox: Codable, Equatable, Sendable {
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

    /// 정규화 얼굴 영역 넓이(0~1). 카메라 거리 고정 전제에서 클수록 머리가 카메라에 가까움(전방머리 추정 보조).
    public var area: Double { width * height }
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
    public var facePitchDegrees: Double?
    public var faceBoundingBox: FaceBox?
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
        facePitchDegrees: Double? = nil,
        faceBoundingBox: FaceBox? = nil,
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
        self.facePitchDegrees = facePitchDegrees
        self.faceBoundingBox = faceBoundingBox
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
    /// 정면 응시 시 얼굴 박스 하단 y(있을 때). 신호 종류와 무관하게 보정에서 frontFace baseline 수집에 쓴다.
    public var faceBottomY: Double?

    public init(assessment: PostureAssessment, signal: PostureSignal? = nil, viewpoint: ViewpointResult? = nil, reason: String? = nil, faceBottomY: Double? = nil) {
        self.assessment = assessment
        self.signal = signal
        self.viewpoint = viewpoint
        self.reason = reason
        self.faceBottomY = faceBottomY
    }
}

public struct Baseline: Codable, Equatable, Sendable {
    public var profileAngle: Double?
    public var frontHeadDropRatio: Double?
    public var threeQuarterAngle: Double?
    public var bodyFrameAngle: Double?
    public var depthDeltaNorm: Double?
    /// 정면 응시 시 얼굴 박스 하단 y(정규화, 좌하단 원점). 거리·높이 고정 전제에서 baseline보다 충분히 낮아지면 전방머리/숙임.
    public var frontFaceBottomY: Double?

    public init(
        profileAngle: Double?,
        frontHeadDropRatio: Double?,
        threeQuarterAngle: Double?,
        bodyFrameAngle: Double? = nil,
        depthDeltaNorm: Double? = nil,
        frontFaceBottomY: Double? = nil
    ) {
        self.profileAngle = profileAngle
        self.frontHeadDropRatio = frontHeadDropRatio
        self.threeQuarterAngle = threeQuarterAngle
        self.bodyFrameAngle = bodyFrameAngle
        self.depthDeltaNorm = depthDeltaNorm
        self.frontFaceBottomY = frontFaceBottomY
    }
}

/// 메뉴/디버그에서 현재 측정값과 판정을 그대로 보여주기 위한 진단 스냅샷.
public struct PostureDiagnostic: Sendable, Equatable {
    public var algorithm: PostureAlgorithmID
    public var assessment: PostureAssessment
    public var signalKind: SignalKind?
    public var value: Double?
    public var confidence: Double?
    public var viewpoint: ViewpointBand?
    public var reason: String?

    public init(
        algorithm: PostureAlgorithmID,
        assessment: PostureAssessment,
        signalKind: SignalKind? = nil,
        value: Double? = nil,
        confidence: Double? = nil,
        viewpoint: ViewpointBand? = nil,
        reason: String? = nil
    ) {
        self.algorithm = algorithm
        self.assessment = assessment
        self.signalKind = signalKind
        self.value = value
        self.confidence = confidence
        self.viewpoint = viewpoint
        self.reason = reason
    }
}
