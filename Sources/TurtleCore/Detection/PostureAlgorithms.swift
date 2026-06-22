import Foundation

// MARK: - 컨텍스트 / 프로토콜

public struct PostureAnalysisContext: Sendable {
    public var baseline: Baseline?
    public var sensitivity: Sensitivity
    public var viewpoint: ViewpointResult
    public var systemInfo: SystemInfo

    public init(
        baseline: Baseline?,
        sensitivity: Sensitivity,
        viewpoint: ViewpointResult
    ) {
        self.init(baseline: baseline, sensitivity: sensitivity, viewpoint: viewpoint, systemInfo: .current)
    }

    public init(
        baseline: Baseline?,
        sensitivity: Sensitivity,
        viewpoint: ViewpointResult,
        systemInfo: SystemInfo
    ) {
        self.baseline = baseline
        self.sensitivity = sensitivity
        self.viewpoint = viewpoint
        self.systemInfo = systemInfo
    }
}

public protocol PostureAlgorithm: Sendable {
    var id: PostureAlgorithmID { get }
    func analyze(_ pose: PoseLandmarks, context: PostureAnalysisContext) -> AnalyzedFrame
}

// MARK: - 공용 판정 (신호 종류별 baseline 상대 + 미보정 폴백)

public enum PostureJudge {
    public static func assess(_ signal: PostureSignal, baseline: Baseline?, sensitivity: Sensitivity) -> PostureAssessment {
        switch signal.kind {
        case .front2D:
            // 정면은 baseline 상대 판정이 우선이지만, 미보정 상태에서도 명확한 정상/비정상은 보수적으로 판정한다.
            let currentRatio = signal.angleDegrees / 90
            guard let baselineRatio = baseline?.frontHeadDropRatio else {
                if currentRatio >= Tuning.frontAbsoluteGoodRatio {
                    return .good
                }
                if currentRatio <= Tuning.frontAbsoluteBadRatio(for: sensitivity) {
                    return .bad
                }
                return .noEval
            }
            return currentRatio < baselineRatio - Tuning.frontRelativeDrop ? .bad : .good
        case .threeQuarter2D:
            return relativeAngle(signal.angleDegrees, baseline: baseline?.threeQuarterAngle, sensitivity: sensitivity)
        case .profile2D:
            return relativeAngle(signal.angleDegrees, baseline: baseline?.profileAngle, sensitivity: sensitivity)
        case .body3D:
            return relativeAngle(signal.angleDegrees, baseline: baseline?.bodyFrameAngle, sensitivity: sensitivity)
        case .depth3D:
            guard let baselineDepth = baseline?.depthDeltaNorm else {
                return .noEval
            }
            return signal.angleDegrees > baselineDepth + Tuning.depthRelativeForward ? .bad : .good
        case .frontFace:
            // 얼굴 박스 하단 y — 작을수록 머리가 앞·아래(전방머리/숙임).
            // 카메라 높이/방향에 민감하므로 보정 baseline 없이 절대 판정하지 않는다.
            let y = signal.angleDegrees
            guard let baselineY = baseline?.frontFaceBottomY else {
                return .noEval
            }
            return y < baselineY - Tuning.frontFaceRelativeDrop ? .bad : .good
        }
    }

    private static func relativeAngle(_ angle: Double, baseline: Double?, sensitivity: Sensitivity) -> PostureAssessment {
        if let baseline {
            return angle < baseline - Tuning.profileRelativeDrop ? .bad : .good
        }
        return angle < Tuning.absoluteBadAngle(for: sensitivity) ? .bad : .good
    }
}

// MARK: - 공용 헬퍼

enum AlgorithmSupport {
    static func shoulderReference(in pose: PoseLandmarks, side: Side) -> Point2D? {
        switch side {
        case .left:
            return pose.leftShoulder?.isTrackable == true
                ? pose.leftShoulder
                : (pose.neck?.isTrackable == true ? pose.neck : nil)
        case .right:
            return pose.rightShoulder?.isTrackable == true
                ? pose.rightShoulder
                : (pose.neck?.isTrackable == true ? pose.neck : nil)
        }
    }

    static func isHeadOnlyRotation(_ pose: PoseLandmarks) -> Bool {
        guard
            let left = pose.leftShoulder, left.isTrackable,
            let right = pose.rightShoulder, right.isTrackable
        else {
            return false
        }
        return abs(right.x - left.x) >= Tuning.headOnlyShoulderWidth
    }

    /// 정면 어깨폭 정규화 머리-어깨 수직 간격 비율(작아질수록 머리가 내려옴/숙임).
    static func frontHeadDropRatio(_ pose: PoseLandmarks) -> Double? {
        guard
            let leftShoulder = pose.leftShoulder, leftShoulder.isTrackable,
            let rightShoulder = pose.rightShoulder, rightShoulder.isTrackable
        else {
            return nil
        }
        let shoulderWidth = abs(rightShoulder.x - leftShoulder.x)
        guard shoulderWidth > 0.05 else {
            return nil
        }
        let headCandidates = [pose.leftEar, pose.rightEar, pose.leftEye, pose.rightEye, pose.nose].compactMap { point -> Point2D? in
            guard let point, point.isTrackable else {
                return nil
            }
            return point
        }
        guard !headCandidates.isEmpty else {
            return nil
        }
        let headY = headCandidates.map(\.y).reduce(0, +) / Double(headCandidates.count)
        let shoulderY = (leftShoulder.y + rightShoulder.y) / 2
        return (shoulderY - headY) / shoulderWidth
    }

    /// 양 눈을 잇는 선의 수평 대비 기울기(절대값, 도). 눈은 웹캠에서 고신뢰로 잡혀
    /// 어깨(저신뢰)·faceYaw/Roll(요동)보다 안정적인 좌우 기울기 보조 신호다.
    static func headTiltDegrees(_ pose: PoseLandmarks) -> Double? {
        guard
            let left = pose.leftEye, left.isReliable,
            let right = pose.rightEye, right.isReliable
        else {
            return nil
        }
        let dx = left.x - right.x
        let dy = left.y - right.y
        guard abs(dx) > 0.001 else {
            return nil
        }
        return abs(atan2(dy, dx) * 180 / .pi)
    }

    /// "바른 자세(good)"는 양성 증거가 있어야 한다 — 머리가 명확히 기울었으면(삐딱/큰 회전) good에서 제외하고 bad로 본다.
    /// 보수적 임계라 명백한 기울기만 잡고, 신뢰 가능한 눈이 없으면 그대로 둔다(섣불리 강등하지 않음).
    /// body pose의 eye-line이 없을 때(비정상 자세에서 흔함)는 faceRoll로 폴백한다(실측: 삐딱 시 faceRoll≈30° 정확).
    static func applyUprightGate(_ assessment: PostureAssessment, pose: PoseLandmarks) -> (assessment: PostureAssessment, reason: String?) {
        guard assessment == .good else {
            return (assessment, nil)
        }
        let tilt = headTiltDegrees(pose) ?? pose.faceRollDegrees.map(abs)
        guard let tilt, tilt > Tuning.maxHeadTiltDegrees else {
            return (assessment, nil)
        }
        return (.bad, "머리 기울임/삐딱(\(Int(tilt))°)")
    }

    /// body pose가 실패한 정면 응시 프레임에서 얼굴 박스 하단 y를 전방머리/숙임 보조 신호로 만든다(약 신호).
    /// 거리·높이 고정 전제에서 baseline보다 충분히 낮아지면 머리가 앞·아래로 나온 것(실측 근거 §0.2 측정).
    static func faceProxySignal(_ pose: PoseLandmarks) -> PostureSignal? {
        guard let box = pose.faceBoundingBox else {
            return nil
        }
        // 정면 응시일 때만 의미가 있다 — 고개를 돌리면(yaw 큼) 박스 위치가 다른 의미가 된다.
        if let yaw = pose.faceYawDegrees, abs(yaw) > Tuning.faceProxyMaxYaw {
            return nil
        }
        // 보조 신호라 신뢰도는 body 신호보다 낮게 둔다.
        return PostureSignal(kind: .frontFace, angleDegrees: box.y, confidence: 0.4)
    }

    static func quality3D(_ pose: PoseLandmarks) -> Double? {
        guard
            let pose3D = pose.pose3D,
            let left = pose3D.leftShoulder, left.isTrackable,
            let right = pose3D.rightShoulder, right.isTrackable,
            (pose3D.centerHead?.isTrackable == true || pose3D.topHead?.isTrackable == true)
        else {
            return nil
        }

        let dx = right.x - left.x
        let dy = right.y - left.y
        let dz = right.z - left.z
        let shoulderWidth = sqrt(dx * dx + dy * dy + dz * dz)
        guard shoulderWidth > 0.05 else {
            return nil
        }

        // 가려진(미추적) 머리/어깨 랜드마크는 품질 산정에서 제외한다.
        // 한쪽 귀가 confidence 0으로 들어와 품질을 0으로 만들고도 게이트를 통과하던 문제 방지.
        let proxyConfidences = [pose.leftShoulder, pose.rightShoulder, pose.nose, pose.leftEar, pose.rightEar, pose.leftEye, pose.rightEye]
            .compactMap { $0 }
            .filter { $0.isTrackable }
            .map(\.confidence)
        let proxyQuality = proxyConfidences.min() ?? 0.7
        let quality = min(left.confidence, right.confidence, proxyQuality)
        // 추적 임계 미만이면 신뢰할 수 없는 3D로 보고 신호를 만들지 않는다(신뢰도 0 신호 차단).
        guard quality >= Tuning.minimumTrackingConfidence else {
            return nil
        }
        return quality
    }
}

private extension ViewpointBand {
    var isStrictProfile: Bool {
        self == .profileLeft || self == .profileRight
    }

    var isProfileOrThreeQuarter: Bool {
        switch self {
        case .profileLeft, .profileRight, .threeQuarterLeft, .threeQuarterRight:
            return true
        case .front, .unknown:
            return false
        }
    }
}

// MARK: - 후보 A: 측면 기하 (Profile 2D)

public struct ProfileGeometryAlgorithm: PostureAlgorithm {
    public let id: PostureAlgorithmID = .profileGeometry
    public init() {}

    public func analyze(_ pose: PoseLandmarks, context: PostureAnalysisContext) -> AnalyzedFrame {
        let viewpoint = context.viewpoint
        guard let side = viewpoint.nearSide, viewpoint.band.isProfileOrThreeQuarter else {
            return AnalyzedFrame(assessment: .noEval, viewpoint: viewpoint, reason: "측면/3-4 시점 아님")
        }
        // 양 어깨가 넓게 보이는 strict profile은 머리만 돌린 상황일 수 있어 보류(시점 자동 분류 기반).
        if viewpoint.band.isStrictProfile, AlgorithmSupport.isHeadOnlyRotation(pose) {
            return AnalyzedFrame(assessment: .noEval, viewpoint: viewpoint, reason: "고개 돌림(몸통 회전 없음)")
        }
        guard
            let head = PostureAnalyzer.headReference(in: pose, side: side),
            let shoulder = AlgorithmSupport.shoulderReference(in: pose, side: side)
        else {
            return AnalyzedFrame(assessment: .noEval, viewpoint: viewpoint, reason: "머리/어깨 신뢰 부족")
        }
        let angle = Geometry.monotonicProfileAngle(head: head, shoulder: shoulder)
        let kind: SignalKind = viewpoint.band.isStrictProfile ? .profile2D : .threeQuarter2D
        let signal = PostureSignal(kind: kind, angleDegrees: angle, confidence: min(head.confidence, shoulder.confidence))
        let base = PostureJudge.assess(signal, baseline: context.baseline, sensitivity: context.sensitivity)
        let gate = AlgorithmSupport.applyUprightGate(base, pose: pose)
        return AnalyzedFrame(assessment: gate.assessment, signal: signal, viewpoint: viewpoint, reason: gate.reason)
    }
}

// MARK: - 후보 B: 정면 보조 (Front 2D)

public struct FrontProxyAlgorithm: PostureAlgorithm {
    public let id: PostureAlgorithmID = .frontProxy
    public init() {}

    public func analyze(_ pose: PoseLandmarks, context: PostureAnalysisContext) -> AnalyzedFrame {
        let viewpoint = context.viewpoint
        guard viewpoint.band == .front else {
            return AnalyzedFrame(assessment: .noEval, viewpoint: viewpoint, reason: "정면 시점 아님")
        }
        if let yaw = pose.faceYawDegrees, abs(yaw) > 25 {
            return AnalyzedFrame(assessment: .noEval, viewpoint: viewpoint, reason: "고개 돌림(yaw 큼)")
        }
        guard let ratio = AlgorithmSupport.frontHeadDropRatio(pose) else {
            return AnalyzedFrame(assessment: .noEval, viewpoint: viewpoint, reason: "정면 머리/어깨 신뢰 부족")
        }
        let signal = PostureSignal(kind: .front2D, angleDegrees: ratio * 90, confidence: min(0.6, viewpoint.confidence))
        let base = PostureJudge.assess(signal, baseline: context.baseline, sensitivity: context.sensitivity)
        let gate = AlgorithmSupport.applyUprightGate(base, pose: pose)
        let reason = gate.reason ?? (context.baseline?.frontHeadDropRatio == nil && gate.assessment == .noEval ? "정면 baseline 필요(보정)" : nil)
        return AnalyzedFrame(assessment: gate.assessment, signal: signal, viewpoint: viewpoint, reason: reason)
    }
}

// MARK: - 후보 C: 3D 신체 좌표계 시상각

public struct BodyFrame3DAlgorithm: PostureAlgorithm {
    public let id: PostureAlgorithmID = .bodyFrame3D
    public init() {}

    public func analyze(_ pose: PoseLandmarks, context: PostureAnalysisContext) -> AnalyzedFrame {
        guard context.systemInfo.isAppleSilicon else {
            return AnalyzedFrame(assessment: .noEval, viewpoint: context.viewpoint, reason: "3D 미지원 환경")
        }
        guard let quality = AlgorithmSupport.quality3D(pose), let pose3D = pose.pose3D else {
            return AnalyzedFrame(assessment: .noEval, viewpoint: context.viewpoint, reason: "3D 포즈 품질 부족")
        }
        guard let angle = Geometry.bodySagittalAngleDegrees(from: pose3D) else {
            return AnalyzedFrame(assessment: .noEval, viewpoint: context.viewpoint, reason: "3D 시상각 계산 실패")
        }

        let signal = PostureSignal(kind: .body3D, angleDegrees: angle, confidence: quality)
        return AnalyzedFrame(
            assessment: PostureJudge.assess(signal, baseline: context.baseline, sensitivity: context.sensitivity),
            signal: signal,
            viewpoint: context.viewpoint
        )
    }
}

// MARK: - 후보 D: 3D 전방 깊이차

public struct DepthDeltaAlgorithm: PostureAlgorithm {
    public let id: PostureAlgorithmID = .depthDelta
    public init() {}

    public func analyze(_ pose: PoseLandmarks, context: PostureAnalysisContext) -> AnalyzedFrame {
        guard context.systemInfo.isAppleSilicon else {
            return AnalyzedFrame(assessment: .noEval, viewpoint: context.viewpoint, reason: "3D 미지원 환경")
        }
        guard let quality = AlgorithmSupport.quality3D(pose), let pose3D = pose.pose3D else {
            return AnalyzedFrame(assessment: .noEval, viewpoint: context.viewpoint, reason: "3D 포즈 품질 부족")
        }
        guard let delta = Geometry.forwardDepthDeltaNormalized(from: pose3D) else {
            return AnalyzedFrame(assessment: .noEval, viewpoint: context.viewpoint, reason: "3D 깊이차 계산 실패")
        }

        let signal = PostureSignal(kind: .depth3D, angleDegrees: delta, confidence: quality)
        return AnalyzedFrame(
            assessment: PostureJudge.assess(signal, baseline: context.baseline, sensitivity: context.sensitivity),
            signal: signal,
            viewpoint: context.viewpoint,
            reason: context.baseline?.depthDeltaNorm == nil ? "깊이 baseline 필요(보정)" : nil
        )
    }
}

// MARK: - 후보 E: 적응 융합 (Fusion) — 권장 기본 (시점에 따라 측면/정면 자동 선택)

public struct FusionAlgorithm: PostureAlgorithm {
    public let id: PostureAlgorithmID = .fusion
    public init() {}

    private let profile = ProfileGeometryAlgorithm()
    private let front = FrontProxyAlgorithm()
    private let body3D = BodyFrame3DAlgorithm()
    private let depth3D = DepthDeltaAlgorithm()

    public func analyze(_ pose: PoseLandmarks, context: PostureAnalysisContext) -> AnalyzedFrame {
        let viewpoint = context.viewpoint
        var reasons: [String] = []

        if viewpoint.band.isProfileOrThreeQuarter {
            let frame = profile.analyze(pose, context: context)
            if frame.signal != nil {
                return frame
            }
            if let reason = frame.reason {
                reasons.append(reason)
            }
        }

        // 3D 입력이 실제로 들어온 경우에만 3D 분기를 평가한다.
        // (fusion은 3D를 요청하지 않거나 3D가 발화하지 않은 프레임에서 2D 경로로 깔끔히 넘어간다.)
        if context.systemInfo.isAppleSilicon, pose.pose3D != nil {
            let bodyFrame = body3D.analyze(pose, context: context)
            if bodyFrame.signal != nil {
                return bodyFrame
            }
            if let reason = bodyFrame.reason {
                reasons.append(reason)
            }

            let depthFrame = depth3D.analyze(pose, context: context)
            if depthFrame.signal != nil {
                return depthFrame
            }
            if let reason = depthFrame.reason {
                reasons.append(reason)
            }
        }

        if viewpoint.band == .front {
            let frontFrame = front.analyze(pose, context: context)
            if frontFrame.signal != nil {
                return frontFrame
            }
            if let reason = frontFrame.reason {
                reasons.append(reason)
            }
        } else if !viewpoint.band.isProfileOrThreeQuarter {
            reasons.append("시점 미상")
        }

        // body pose 경로가 모두 실패한 경우(비정상 자세에서 Vision body pose가 자주 실패) 얼굴 보조 신호로 판정한다.
        // 삐딱(머리 좌우 기울임)은 faceRoll로 잡는다. faceRoll은 yaw와 독립적이라(실측: 측면 yaw≈-45에서도 roll≈30 정확)
        // yaw 게이트가 걸린 faceProxySignal 밖에서 먼저 검사한다 — 측면 배치(yaw 큼)의 삐딱을 놓치지 않도록.
        if let roll = pose.faceRollDegrees.map(abs), roll > Tuning.maxHeadTiltDegrees {
            let faceSignal = AlgorithmSupport.faceProxySignal(pose)
                ?? pose.faceBoundingBox.map { PostureSignal(kind: .frontFace, angleDegrees: $0.y, confidence: 0.4) }
            return AnalyzedFrame(assessment: .bad, signal: faceSignal, viewpoint: viewpoint, reason: "머리 기울임/삐딱(\(Int(roll))°)")
        }

        // 전방머리/숙임은 얼굴 박스 하단 y로 잡는다(정면 응시 yaw 게이트 — faceProxySignal 내부).
        if let faceSignal = AlgorithmSupport.faceProxySignal(pose) {
            let base = PostureJudge.assess(faceSignal, baseline: context.baseline, sensitivity: context.sensitivity)
            let gate = AlgorithmSupport.applyUprightGate(base, pose: pose)
            let reason = gate.reason ?? (context.baseline?.frontFaceBottomY == nil ? "얼굴 위치 baseline 필요(보정)" : "얼굴 보조 신호")
            return AnalyzedFrame(assessment: gate.assessment, signal: faceSignal, viewpoint: viewpoint, reason: reason)
        }

        let reason = reasons.removingDuplicates().joined(separator: " · ")
        return AnalyzedFrame(assessment: .noEval, viewpoint: viewpoint, reason: reason.isEmpty ? "가용 신호 없음" : reason)
    }
}

private extension Array where Element: Hashable {
    func removingDuplicates() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}

// MARK: - 팩토리

public enum PostureAlgorithmFactory {
    public static func make(_ id: PostureAlgorithmID, analyzer: PostureAnalyzer = PostureAnalyzer()) -> any PostureAlgorithm {
        switch id {
        case .profileGeometry:
            return ProfileGeometryAlgorithm()
        case .frontProxy:
            return FrontProxyAlgorithm()
        case .bodyFrame3D:
            return BodyFrame3DAlgorithm()
        case .depthDelta:
            return DepthDeltaAlgorithm()
        case .fusion:
            return FusionAlgorithm()
        }
    }
}
