import Foundation
@testable import TurtleCore

func registerDetectionTests() {
    TestRegistry.test("CVA angle is vertical when head is directly above shoulder") {
        let angle = Geometry.cvaAngleDegrees(head: confident(0.4, 0.2), shoulder: confident(0.4, 0.8))
        try expectApprox(angle, 90, tolerance: 0.01, "vertical CVA")
    }

    TestRegistry.test("CVA angle drops as head moves forward") {
        let angle = Geometry.cvaAngleDegrees(head: confident(0.8, 0.4), shoulder: confident(0.4, 0.8))
        try expect(angle < 50, "forward head should lower CVA below caution boundary")
    }

    TestRegistry.test("front viewpoint uses both ears and shoulders") {
        let pose = PoseLandmarks(
            leftEar: confident(0.35, 0.3),
            rightEar: confident(0.65, 0.3),
            leftShoulder: confident(0.3, 0.7),
            rightShoulder: confident(0.7, 0.7),
            faceYawDegrees: 4
        )
        let result = ViewpointClassifier().classify(pose)
        try expectEqual(result.band, .front, "both ears should classify front")
        try expect(result.confidence > 0.7, "front confidence")
    }

    TestRegistry.test("single visible right ear and yaw classify right profile") {
        let pose = PoseLandmarks(
            rightEar: confident(0.58, 0.28),
            rightShoulder: confident(0.62, 0.75),
            faceYawDegrees: 72
        )
        let result = ViewpointClassifier().classify(pose)
        try expectEqual(result.band, .profileRight, "right ear profile")
        try expectEqual(result.nearSide, .right, "right side is near")
    }

    TestRegistry.test("single visible left ear and yaw classify left three-quarter") {
        let pose = PoseLandmarks(
            leftEar: confident(0.42, 0.28),
            leftShoulder: confident(0.38, 0.75),
            faceYawDegrees: -38
        )
        let result = ViewpointClassifier().classify(pose)
        try expectEqual(result.band, .threeQuarterLeft, "left ear three-quarter")
        try expectEqual(result.nearSide, .left, "left side is near")
    }

    TestRegistry.test("missing ears can classify profile from yaw and eye visibility") {
        let pose = PoseLandmarks(
            leftEye: confident(0.45, 0.26),
            rightEye: nil,
            faceYawDegrees: -68
        )
        let result = ViewpointClassifier().classify(pose)
        try expectEqual(result.band, .profileLeft, "eye and yaw fallback")
    }

    TestRegistry.test("unknown viewpoint when landmarks and yaw are weak") {
        let pose = PoseLandmarks(nose: lowConfidence(0.5, 0.3), faceYawDegrees: nil)
        let result = ViewpointClassifier().classify(pose)
        try expectEqual(result.band, .unknown, "weak landmarks should not guess")
    }

    TestRegistry.test("front viewpoint falls back to nose and shoulders") {
        let pose = PoseLandmarks(
            nose: confident(0.5, 0.3),
            leftShoulder: confident(0.32, 0.72),
            rightShoulder: confident(0.68, 0.72),
            faceYawDegrees: nil
        )
        let result = ViewpointClassifier().classify(pose)
        try expectEqual(result.band, .front, "upper-body webcam signal should classify front")
    }

    TestRegistry.test("front viewpoint accepts low-confidence tracking landmarks") {
        let pose = PoseLandmarks(
            nose: lowConfidence(0.5, 0.3),
            leftShoulder: lowConfidence(0.32, 0.72),
            rightShoulder: lowConfidence(0.68, 0.72),
            faceYawDegrees: nil
        )
        let result = ViewpointClassifier().classify(pose)
        try expectEqual(result.band, .front, "low-confidence webcam landmarks should still be trackable")
    }

    TestRegistry.test("profile head reference falls back from ear to eye") {
        let pose = PoseLandmarks(
            rightEye: confident(0.62, 0.26),
            rightShoulder: confident(0.56, 0.72)
        )
        let point = PostureAnalyzer.headReference(in: pose, side: .right)
        try expectApprox(point?.x ?? -1, 0.62, tolerance: 0.001, "right eye fallback x")
    }

    TestRegistry.test("profile head reference falls back from eye to nose") {
        let pose = PoseLandmarks(
            nose: confident(0.59, 0.26),
            rightShoulder: confident(0.56, 0.72)
        )
        let point = PostureAnalyzer.headReference(in: pose, side: .right)
        try expectApprox(point?.x ?? -1, 0.59, tolerance: 0.001, "nose fallback x")
    }

    TestRegistry.test("upright profile is good without baseline") {
        let pose = PoseLandmarks(
            rightEar: confident(0.56, 0.28),
            rightShoulder: confident(0.54, 0.78),
            faceYawDegrees: 72
        )
        let analyzed = PostureAnalyzer().analyze(pose, baseline: nil, sensitivity: .medium)
        try expectEqual(analyzed.assessment, .good, "upright profile should pass absolute threshold")
        try expect(analyzed.signal?.angleDegrees ?? 0 > 65, "upright angle")
    }

    TestRegistry.test("forward profile is bad without baseline") {
        let pose = PoseLandmarks(
            rightEar: confident(0.87, 0.47),
            rightShoulder: confident(0.52, 0.78),
            faceYawDegrees: 74
        )
        let analyzed = PostureAnalyzer().analyze(pose, baseline: nil, sensitivity: .medium)
        try expectEqual(analyzed.assessment, .bad, "forward profile should fail absolute threshold")
        try expect(analyzed.signal?.angleDegrees ?? 90 < 55, "forward angle")
    }

    TestRegistry.test("front pose without baseline can classify clear upright posture") {
        let pose = PoseLandmarks(
            leftEar: confident(0.35, 0.3),
            rightEar: confident(0.65, 0.3),
            leftShoulder: confident(0.3, 0.7),
            rightShoulder: confident(0.7, 0.7),
            faceYawDegrees: 0
        )
        let analyzed = PostureAnalyzer().analyze(pose, baseline: nil, sensitivity: .medium)
        try expectEqual(analyzed.assessment, .good, "clear upright front posture should pass absolute fallback")
        try expectEqual(analyzed.signal?.kind, .front2D, "front signal should still be available for calibration")
    }

    TestRegistry.test("front pose without baseline withholds ambiguous posture") {
        let pose = PoseLandmarks(
            leftEar: confident(0.35, 0.4),
            rightEar: confident(0.65, 0.4),
            leftShoulder: confident(0.3, 0.7),
            rightShoulder: confident(0.7, 0.7),
            faceYawDegrees: 0
        )
        let analyzed = PostureAnalyzer().analyze(pose, baseline: nil, sensitivity: .medium)
        try expectEqual(analyzed.assessment, .noEval, "ambiguous front posture should still require baseline")
    }

    TestRegistry.test("front pose uses shoulder-width normalized baseline for relative bad judgment") {
        let baseline = Baseline(profileAngle: nil, frontHeadDropRatio: 1.0, threeQuarterAngle: nil)
        let pose = PoseLandmarks(
            leftEar: confident(0.35, 0.44),
            rightEar: confident(0.65, 0.44),
            leftShoulder: confident(0.3, 0.7),
            rightShoulder: confident(0.7, 0.7),
            faceYawDegrees: 0
        )
        let analyzed = PostureAnalyzer().analyze(pose, baseline: baseline, sensitivity: .medium)
        try expectEqual(analyzed.assessment, .bad, "front relative drop should be bad")
    }

    TestRegistry.test("front pose uses shoulder-width normalized baseline for relative good judgment") {
        let baseline = Baseline(profileAngle: nil, frontHeadDropRatio: 1.0, threeQuarterAngle: nil)
        let pose = PoseLandmarks(
            leftEar: confident(0.35, 0.30),
            rightEar: confident(0.65, 0.30),
            leftShoulder: confident(0.3, 0.7),
            rightShoulder: confident(0.7, 0.7),
            faceYawDegrees: 0
        )
        let analyzed = PostureAnalyzer().analyze(pose, baseline: baseline, sensitivity: .medium)
        try expectEqual(analyzed.assessment, .good, "matching normalized front ratio should be good")
    }

    TestRegistry.test("head-only rotation guard with center camera returns no-eval") {
        let pose = PoseLandmarks(
            rightEar: confident(0.57, 0.28),
            leftShoulder: confident(0.28, 0.72),
            rightShoulder: confident(0.72, 0.72),
            faceYawDegrees: 75
        )
        let analyzed = PostureAnalyzer().analyze(pose, baseline: nil, sensitivity: .medium)
        try expectEqual(analyzed.assessment, .noEval, "head-only rotation should be withheld")
    }

    TestRegistry.test("head-only rotation guard falls back to 3D on Apple Silicon") {
        let pose = PoseLandmarks(
            rightEar: confident(0.57, 0.28),
            leftShoulder: confident(0.28, 0.72),
            rightShoulder: confident(0.72, 0.72),
            faceYawDegrees: 75,
            pose3D: Pose3D(
                leftShoulder: p3(-0.4, 1.2, 0),
                rightShoulder: p3(0.4, 1.2, 0),
                spine: p3(0, 0, 0),
                centerHead: p3(0, 2.2, 0.15)
            )
        )
        let analyzed = PostureAnalyzer(systemInfo: SystemInfo(isAppleSilicon: true)).analyze(pose, baseline: nil, sensitivity: .medium)
        try expectEqual(analyzed.assessment, .good, "3D should evaluate when 2D profile is head-only rotation")
        try expectEqual(analyzed.signal?.kind, .body3D, "3D fallback signal kind")
    }

    TestRegistry.test("side camera placement allows stable profile judgment") {
        let pose = PoseLandmarks(
            rightEar: confident(0.57, 0.28),
            leftShoulder: confident(0.28, 0.72),
            rightShoulder: confident(0.56, 0.76),
            faceYawDegrees: 75
        )
        let analyzed = PostureAnalyzer().analyze(pose, baseline: nil, sensitivity: .medium)
        try expectEqual(analyzed.assessment, .good, "side camera should allow profile")
    }

    TestRegistry.test("body-coordinate 3D sagittal angle ignores yaw rotation") {
        let upright = Pose3D(
            leftShoulder: p3(-0.4, 1.2, 0),
            rightShoulder: p3(0.4, 1.2, 0),
            spine: p3(0, 0, 0),
            centerHead: p3(0, 2.2, 0.25)
        )
        let rotated = upright.rotatedAroundY(degrees: 55)
        let a = Geometry.bodySagittalAngleDegrees(from: upright)
        let b = Geometry.bodySagittalAngleDegrees(from: rotated)
        try expectApprox(a ?? 0, b ?? -1, tolerance: 0.01, "3D body angle should be yaw invariant")
    }

    TestRegistry.test("3D sagittal angle falls back when spine is missing") {
        let pose = Pose3D(
            leftShoulder: p3(-0.4, 1.2, 0),
            rightShoulder: p3(0.4, 1.2, 0),
            centerHead: p3(0, 2.2, 0.15)
        )
        try expect(Geometry.bodySagittalAngleDegrees(from: pose) != nil, "world up should replace missing spine")
    }

    TestRegistry.test("3D sagittal angle falls back to top head") {
        let pose = Pose3D(
            leftShoulder: p3(-0.4, 1.2, 0),
            rightShoulder: p3(0.4, 1.2, 0),
            spine: p3(0, 0, 0),
            topHead: p3(0, 2.3, 0.15)
        )
        try expect(Geometry.bodySagittalAngleDegrees(from: pose) != nil, "top head should replace missing center head")
    }

    TestRegistry.test("3D path is used when 2D landmarks are absent") {
        let pose = PoseLandmarks(
            pose3D: Pose3D(
                leftShoulder: p3(-0.4, 1.2, 0),
                rightShoulder: p3(0.4, 1.2, 0),
                spine: p3(0, 0, 0),
                centerHead: p3(0, 2.2, 0.15)
            )
        )
        let analyzed = PostureAnalyzer(systemInfo: SystemInfo(isAppleSilicon: true)).analyze(pose, baseline: nil, sensitivity: .medium)
        try expectEqual(analyzed.assessment, .good, "3D should evaluate without 2D")
        try expectEqual(analyzed.signal?.kind, .body3D, "3D signal kind")
    }

    TestRegistry.test("Intel path does not require 3D") {
        let pose = PoseLandmarks(
            pose3D: Pose3D(
                leftShoulder: p3(-0.4, 1.2, 0),
                rightShoulder: p3(0.4, 1.2, 0),
                spine: p3(0, 0, 0),
                centerHead: p3(0, 2.2, 0.15)
            )
        )
        let analyzed = PostureAnalyzer(systemInfo: SystemInfo(isAppleSilicon: false)).analyze(pose, baseline: nil, sensitivity: .medium)
        try expectEqual(analyzed.assessment, .noEval, "Intel should ignore 3D-only frames")
    }

    TestRegistry.test("calibrator accepts upright profile baseline") {
        let frame = AnalyzedFrame(assessment: .good, signal: PostureSignal(kind: .profile2D, angleDegrees: 75, confidence: 0.9), viewpoint: ViewpointResult(band: .profileRight, confidence: 0.9, nearSide: .right))
        let result = Calibrator().capture(from: [frame])
        try expectEqual(result, .accepted(Baseline(profileAngle: 75, frontHeadDropRatio: nil, threeQuarterAngle: nil)), "accepted profile baseline")
    }

    TestRegistry.test("calibrator accepts normalized front baseline") {
        let frame = AnalyzedFrame(assessment: .noEval, signal: PostureSignal(kind: .front2D, angleDegrees: 90, confidence: 0.9), viewpoint: ViewpointResult(band: .front, confidence: 0.9))
        let result = Calibrator().capture(from: [frame])
        try expectEqual(result, .accepted(Baseline(profileAngle: nil, frontHeadDropRatio: 1.0, threeQuarterAngle: nil)), "accepted front baseline")
    }

    TestRegistry.test("calibrator uses percentile instead of noisy maximum") {
        let frames = [60.0, 60.0, 60.0, 60.0, 90.0].map {
            AnalyzedFrame(assessment: .good, signal: PostureSignal(kind: .profile2D, angleDegrees: $0, confidence: 0.9), viewpoint: ViewpointResult(band: .profileRight, confidence: 0.9, nearSide: .right))
        }
        let result = Calibrator().capture(from: frames)
        try expectEqual(result, .accepted(Baseline(profileAngle: 60, frontHeadDropRatio: nil, threeQuarterAngle: nil)), "single noisy upright frame should not define baseline")
    }

    TestRegistry.test("calibrator stores multiple channel baselines") {
        let frames = [
            AnalyzedFrame(assessment: .good, signal: PostureSignal(kind: .profile2D, angleDegrees: 75, confidence: 0.9), viewpoint: ViewpointResult(band: .profileRight, confidence: 0.9, nearSide: .right)),
            AnalyzedFrame(assessment: .noEval, signal: PostureSignal(kind: .front2D, angleDegrees: 90, confidence: 0.9), viewpoint: ViewpointResult(band: .front, confidence: 0.9)),
            AnalyzedFrame(assessment: .good, signal: PostureSignal(kind: .threeQuarter2D, angleDegrees: 68, confidence: 0.9), viewpoint: ViewpointResult(band: .threeQuarterRight, confidence: 0.9, nearSide: .right))
        ]
        let result = Calibrator().capture(from: frames)
        try expectEqual(result, .accepted(Baseline(profileAngle: 75, frontHeadDropRatio: 1.0, threeQuarterAngle: 68)), "baseline should preserve all reliable channels")
    }

    TestRegistry.test("calibrator stores face proxy baseline at tracking confidence") {
        let frame = AnalyzedFrame(assessment: .noEval, signal: PostureSignal(kind: .frontFace, angleDegrees: 0.56, confidence: 0.4), viewpoint: ViewpointResult(band: .front, confidence: 0.45))
        let result = Calibrator().capture(from: [frame])
        try expectEqual(result, .accepted(Baseline(profileAngle: nil, frontHeadDropRatio: nil, threeQuarterAngle: nil, frontFaceBottomY: 0.56)), "face proxy baseline should use tracking confidence")
    }

    TestRegistry.test("calibrator rejects slouched profile baseline") {
        let frame = AnalyzedFrame(assessment: .bad, signal: PostureSignal(kind: .profile2D, angleDegrees: 42, confidence: 0.9), viewpoint: ViewpointResult(band: .profileRight, confidence: 0.9, nearSide: .right))
        let result = Calibrator().capture(from: [frame])
        try expectEqual(result, .rejected(.alreadySlouched), "reject slouched baseline")
    }

    TestRegistry.test("calibrator accepts low-confidence side baseline from webcam shoulders") {
        // 측면/3-4 배치에서 반대측 어깨가 웹캠 저신뢰(실측 0.36)라 신호 confidence가 0.5 미만이어도
        // 보정이 돼야 한다(측면 배치에서 보정이 항상 "자세 신호 부족"으로 실패하던 회귀 방지).
        let frames = [68.0, 70.0, 72.0].map {
            AnalyzedFrame(assessment: .good, signal: PostureSignal(kind: .threeQuarter2D, angleDegrees: $0, confidence: 0.36), viewpoint: ViewpointResult(band: .threeQuarterRight, confidence: 0.66, nearSide: .right))
        }
        guard case .accepted(let baseline) = Calibrator().capture(from: frames) else {
            throw TestFailure(message: "low-confidence side baseline should be accepted")
        }
        try expect(baseline.threeQuarterAngle != nil, "three-quarter baseline should be captured from low-confidence webcam shoulders")
    }

    TestRegistry.test("calibrator still rejects low-confidence front body signal") {
        // 정면 2D(front2D)는 어깨가 양쪽 다 보이는 시점이라 저신뢰 완화 대상이 아니다 — 기존 0.5 기준 유지.
        let frame = AnalyzedFrame(assessment: .good, signal: PostureSignal(kind: .front2D, angleDegrees: 90, confidence: 0.36), viewpoint: ViewpointResult(band: .front, confidence: 0.9))
        let result = Calibrator().capture(from: [frame])
        try expectEqual(result, .rejected(.noReliableFrames), "front2D below landmark confidence should not calibrate")
    }

    TestRegistry.test("one euro filter smooths a sudden jump") {
        var filter = OneEuroFilter(alpha: 0.5)
        let first = filter.filter(10)
        let second = filter.filter(90)
        try expectApprox(first, 10, tolerance: 0.001, "first filter value")
        try expect(second > 10 && second < 90, "jump should be smoothed")
    }

    TestRegistry.test("one euro filter adapts to fast movement") {
        var staticFilter = OneEuroFilter(minCutoff: 0.1, beta: 0, dCutoff: 1)
        _ = staticFilter.filter(0, timestamp: 0)
        let staticOutput = staticFilter.filter(100, timestamp: 0.016)

        var adaptiveFilter = OneEuroFilter(minCutoff: 0.1, beta: 1.0, dCutoff: 1)
        _ = adaptiveFilter.filter(0, timestamp: 0)
        let adaptiveOutput = adaptiveFilter.filter(100, timestamp: 0.016)

        try expect(adaptiveOutput > staticOutput, "beta should reduce lag for fast movement")
        try expect(staticOutput > 0 && adaptiveOutput < 100, "both filters should still smooth")
    }

    // MARK: - 분석 방식 실행 검증

    TestRegistry.test("factory builds every algorithm id") {
        for id in PostureAlgorithmID.allCases {
            try expectEqual(PostureAlgorithmFactory.make(id).id, id, "factory id roundtrip for \(id.rawValue)")
        }
    }

    TestRegistry.test("user selectable analysis methods are ML only") {
        try expectEqual(PostureAlgorithmID.userSelectableMLMethods, [.mlAuto, .coreMLRelativeDepth, .depthDelta, .bodyFrame3D], "menu should expose only ML methods")
        try expect(!PostureAlgorithmID.userSelectableMLMethods.contains(.profileGeometry), "geometry should stay internal")
        try expect(!PostureAlgorithmID.userSelectableMLMethods.contains(.frontProxy), "2D proxy should stay internal")
        try expect(!PostureAlgorithmID.userSelectableMLMethods.contains(.fusion), "legacy fusion should stay internal")
    }

    TestRegistry.test("monotonic profile angle clamps below-shoulder head to zero") {
        let upright = Geometry.monotonicProfileAngle(head: confident(0.4, 0.2), shoulder: confident(0.4, 0.8))
        let belowShoulder = Geometry.monotonicProfileAngle(head: confident(0.45, 0.9), shoulder: confident(0.4, 0.8))
        try expectApprox(upright, 90, tolerance: 0.01, "upright vertical")
        try expect(belowShoulder < 5, "head below shoulder should not re-increase angle")
    }

    TestRegistry.test("profile geometry algorithm emits profile signal") {
        let pose = PoseLandmarks(rightEar: confident(0.56, 0.28), rightShoulder: confident(0.54, 0.78), faceYawDegrees: 72)
        let viewpoint = ViewpointClassifier().classify(pose)
        let context = PostureAnalysisContext(baseline: nil, sensitivity: .medium, viewpoint: viewpoint, systemInfo: SystemInfo(isAppleSilicon: true))
        let frame = ProfileGeometryAlgorithm().analyze(pose, context: context)
        try expectEqual(frame.signal?.kind, .profile2D, "profile signal kind")
        try expect((frame.signal?.angleDegrees ?? 0) > 65, "upright profile angle high")
    }

    TestRegistry.test("front proxy emits front signal and classifies clear upright without baseline") {
        let pose = PoseLandmarks(leftEar: confident(0.35, 0.3), rightEar: confident(0.65, 0.3), leftShoulder: confident(0.3, 0.7), rightShoulder: confident(0.7, 0.7), faceYawDegrees: 0)
        let viewpoint = ViewpointClassifier().classify(pose)
        let context = PostureAnalysisContext(baseline: nil, sensitivity: .medium, viewpoint: viewpoint, systemInfo: SystemInfo(isAppleSilicon: true))
        let frame = FrontProxyAlgorithm().analyze(pose, context: context)
        try expectEqual(frame.signal?.kind, .front2D, "front signal kind")
        try expectEqual(frame.assessment, .good, "clear upright front posture should pass absolute fallback")
    }

    TestRegistry.test("front proxy withholds ambiguous posture without baseline") {
        let pose = PoseLandmarks(leftEar: confident(0.35, 0.4), rightEar: confident(0.65, 0.4), leftShoulder: confident(0.3, 0.7), rightShoulder: confident(0.7, 0.7), faceYawDegrees: 0)
        let viewpoint = ViewpointClassifier().classify(pose)
        let context = PostureAnalysisContext(baseline: nil, sensitivity: .medium, viewpoint: viewpoint, systemInfo: SystemInfo(isAppleSilicon: true))
        let frame = FrontProxyAlgorithm().analyze(pose, context: context)
        try expectEqual(frame.signal?.kind, .front2D, "front signal kind")
        try expectEqual(frame.assessment, .noEval, "ambiguous front posture should still require baseline")
    }

    TestRegistry.test("fusion emits front fallback signal when face landmarks are sparse") {
        let pose = PoseLandmarks(
            nose: confident(0.5, 0.3),
            leftShoulder: confident(0.32, 0.72),
            rightShoulder: confident(0.68, 0.72),
            faceYawDegrees: nil
        )
        let viewpoint = ViewpointClassifier().classify(pose)
        let context = PostureAnalysisContext(baseline: nil, sensitivity: .medium, viewpoint: viewpoint, systemInfo: SystemInfo(isAppleSilicon: true))
        let frame = FusionAlgorithm().analyze(pose, context: context)
        try expectEqual(frame.signal?.kind, .front2D, "fusion should expose sparse front signal")
    }

    TestRegistry.test("fusion keeps sane 3D when 2D shoulders are low confidence") {
        let pose = PoseLandmarks(
            nose: lowConfidence(0.5, 0.3),
            leftShoulder: lowConfidence(0.32, 0.72),
            rightShoulder: lowConfidence(0.68, 0.72),
            pose3D: Pose3D(
                leftShoulder: p3(-0.4, 1.2, 0),
                rightShoulder: p3(0.4, 1.2, 0),
                spine: p3(0, 0, 0),
                centerHead: p3(0, 2.2, 0.15)
            )
        )
        let viewpoint = ViewpointClassifier().classify(pose)
        let baseline = Baseline(profileAngle: nil, frontHeadDropRatio: nil, threeQuarterAngle: nil, bodyFrameAngle: 72)
        let context = PostureAnalysisContext(baseline: baseline, sensitivity: .medium, viewpoint: viewpoint, systemInfo: SystemInfo(isAppleSilicon: true))
        let frame = FusionAlgorithm().analyze(pose, context: context)
        try expectEqual(frame.signal?.kind, .body3D, "low 2D confidence should not discard sane 3D")
        try expect(frame.assessment != .noEval, "sane 3D should produce a posture assessment")
    }

    TestRegistry.test("body-frame 3D algorithm emits 3D signal on apple silicon") {
        let pose = PoseLandmarks(pose3D: Pose3D(leftShoulder: p3(-0.4, 1.2, 0), rightShoulder: p3(0.4, 1.2, 0), spine: p3(0, 0, 0), centerHead: p3(0, 2.2, 0.15)))
        let context = PostureAnalysisContext(baseline: nil, sensitivity: .medium, viewpoint: ViewpointResult(band: .front, confidence: 0.7), systemInfo: SystemInfo(isAppleSilicon: true))
        let frame = BodyFrame3DAlgorithm().analyze(pose, context: context)
        try expectEqual(frame.signal?.kind, .body3D, "3D body signal kind")
        try expectEqual(frame.assessment, .noEval, "3D body signal should need a calibrated baseline")
        try expectEqual(frame.reason, "3D축 baseline 필요(보정)", "missing 3D baseline reason")
    }

    TestRegistry.test("body-frame 3D algorithm withholds off apple silicon") {
        let pose = PoseLandmarks(pose3D: Pose3D(leftShoulder: p3(-0.4, 1.2, 0), rightShoulder: p3(0.4, 1.2, 0), spine: p3(0, 0, 0), centerHead: p3(0, 2.2, 0.15)))
        let context = PostureAnalysisContext(baseline: nil, sensitivity: .medium, viewpoint: ViewpointResult(band: .front, confidence: 0.7), systemInfo: SystemInfo(isAppleSilicon: false))
        let frame = BodyFrame3DAlgorithm().analyze(pose, context: context)
        try expectEqual(frame.assessment, .noEval, "no 3D off apple silicon")
        try expect(frame.signal == nil, "no signal off apple silicon")
    }

    TestRegistry.test("depth delta algorithm emits depth signal on apple silicon") {
        let pose = PoseLandmarks(pose3D: Pose3D(leftShoulder: p3(-0.4, 1.2, 0), rightShoulder: p3(0.4, 1.2, 0), spine: p3(0, 0, 0), centerHead: p3(0, 2.2, 0.2)))
        let context = PostureAnalysisContext(baseline: nil, sensitivity: .medium, viewpoint: ViewpointResult(band: .front, confidence: 0.7), systemInfo: SystemInfo(isAppleSilicon: true))
        let frame = DepthDeltaAlgorithm().analyze(pose, context: context)
        try expectEqual(frame.signal?.kind, .depth3D, "depth signal kind")
    }

    TestRegistry.test("core ml relative depth algorithm needs depth feature") {
        let pose = PoseLandmarks(faceYawDegrees: 0)
        let context = PostureAnalysisContext(baseline: nil, sensitivity: .medium, viewpoint: ViewpointResult(band: .front, confidence: 0.7), systemInfo: SystemInfo(isAppleSilicon: true))
        let frame = CoreMLRelativeDepthAlgorithm().analyze(pose, context: context)
        try expectEqual(frame.assessment, .noEval, "missing Core ML feature should not judge")
        try expect(frame.signal == nil, "missing Core ML feature should not emit signal")
    }

    TestRegistry.test("core ml relative depth algorithm uses baseline for relative bad judgment") {
        let pose = PoseLandmarks(
            faceYawDegrees: 0,
            relativeDepth: RelativeDepthSummary(headCloserDelta: 0.24, confidence: 0.5)
        )
        let baseline = Baseline(profileAngle: nil, frontHeadDropRatio: nil, threeQuarterAngle: nil, relativeDepthDelta: 0.10)
        let context = PostureAnalysisContext(baseline: baseline, sensitivity: .medium, viewpoint: ViewpointResult(band: .front, confidence: 0.7), systemInfo: SystemInfo(isAppleSilicon: true))
        let frame = CoreMLRelativeDepthAlgorithm().analyze(pose, context: context)
        try expectEqual(frame.signal?.kind, .relativeDepth, "relative depth signal kind")
        try expectEqual(frame.assessment, .bad, "relative depth increase over baseline should be bad")
    }

    TestRegistry.test("core ml relative depth algorithm uses baseline for relative good judgment") {
        let pose = PoseLandmarks(
            faceYawDegrees: 0,
            relativeDepth: RelativeDepthSummary(headCloserDelta: 0.14, confidence: 0.5)
        )
        let baseline = Baseline(profileAngle: nil, frontHeadDropRatio: nil, threeQuarterAngle: nil, relativeDepthDelta: 0.10)
        let context = PostureAnalysisContext(baseline: baseline, sensitivity: .medium, viewpoint: ViewpointResult(band: .front, confidence: 0.7), systemInfo: SystemInfo(isAppleSilicon: true))
        let frame = CoreMLRelativeDepthAlgorithm().analyze(pose, context: context)
        try expectEqual(frame.assessment, .good, "small relative depth change should stay good")
    }

    TestRegistry.test("core ml relative depth works on non-front calibrated view") {
        let pose = PoseLandmarks(
            relativeDepth: RelativeDepthSummary(headCloserDelta: 0.12, confidence: 0.5)
        )
        let baseline = Baseline(profileAngle: nil, frontHeadDropRatio: nil, threeQuarterAngle: nil, relativeDepthDelta: 0.10)
        let context = PostureAnalysisContext(baseline: baseline, sensitivity: .medium, viewpoint: ViewpointResult(band: .unknown, confidence: 0), systemInfo: SystemInfo(isAppleSilicon: true))
        let frame = CoreMLRelativeDepthAlgorithm().analyze(pose, context: context)
        try expectEqual(frame.signal?.kind, .relativeDepth, "relative depth should not require front viewpoint")
        try expectEqual(frame.assessment, .good, "baseline-relative Core ML depth should evaluate off front view")
    }

    TestRegistry.test("core ml depth provider does not load model without anchors") {
        let provider = CoreMLRelativeDepthProvider(modelName: "MissingModelForNoAnchorTest")
        let result = provider.estimate(cgImage: try tinyTestImage(), landmarks: PoseLandmarks(faceYawDegrees: 0))
        let loadFailed = Mirror(reflecting: provider).children.first { $0.label == "loadFailed" }?.value as? Bool

        try expect(result == nil, "provider should not estimate without head and shoulder anchors")
        try expectEqual(loadFailed, false, "provider should not attempt model load when depth anchors are unavailable")
    }

    TestRegistry.test("ML auto selects assessed core ml depth when available") {
        let pose = PoseLandmarks(
            faceYawDegrees: 0,
            pose3D: Pose3D(leftShoulder: p3(-0.4, 1.2, 0), rightShoulder: p3(0.4, 1.2, 0), spine: p3(0, 0, 0), centerHead: p3(0, 2.2, 0.05)),
            relativeDepth: RelativeDepthSummary(headCloserDelta: 0.24, confidence: 0.5)
        )
        let baseline = Baseline(profileAngle: nil, frontHeadDropRatio: nil, threeQuarterAngle: nil, depthDeltaNorm: 0.10, relativeDepthDelta: 0.10)
        let context = PostureAnalysisContext(baseline: baseline, sensitivity: .medium, viewpoint: ViewpointResult(band: .front, confidence: 0.7), systemInfo: SystemInfo(isAppleSilicon: true))
        let frame = MLAutoAlgorithm().analyze(pose, context: context)
        try expectEqual(frame.signal?.kind, .relativeDepth, "ML auto should prefer Core ML depth on front view")
        try expectEqual(frame.assessment, .bad, "Core ML relative depth should drive the assessment")
    }

    TestRegistry.test("ML auto falls back to Apple Vision 3D depth") {
        let pose = PoseLandmarks(
            pose3D: Pose3D(leftShoulder: p3(-0.4, 1.2, 0), rightShoulder: p3(0.4, 1.2, 0), spine: p3(0, 0, 0), centerHead: p3(0, 2.2, 0.2))
        )
        let context = PostureAnalysisContext(baseline: Baseline(profileAngle: nil, frontHeadDropRatio: nil, threeQuarterAngle: nil, depthDeltaNorm: 0.01), sensitivity: .medium, viewpoint: ViewpointResult(band: .profileRight, confidence: 0.7, nearSide: .right), systemInfo: SystemInfo(isAppleSilicon: true))
        let frame = MLAutoAlgorithm().analyze(pose, context: context)
        try expectEqual(frame.signal?.kind, .depth3D, "ML auto should use Vision 3D depth when Core ML front depth is unavailable")
    }

    TestRegistry.test("3D quality gating rejects no-proxy implausible geometry") {
        let pose = PoseLandmarks(pose3D: Pose3D(leftShoulder: p3(-0.02, 1.2, 0), rightShoulder: p3(0.02, 1.2, 0), spine: p3(0, 0, 0), centerHead: p3(0, 2.2, 0.15)))
        let context = PostureAnalysisContext(baseline: nil, sensitivity: .medium, viewpoint: ViewpointResult(band: .front, confidence: 0.7), systemInfo: SystemInfo(isAppleSilicon: true))
        let frame = BodyFrame3DAlgorithm().analyze(pose, context: context)
        try expectEqual(frame.assessment, .noEval, "implausible 3D geometry without 2D proxy should gate to noEval")
        try expect(frame.signal == nil, "no signal when gated")
    }

    TestRegistry.test("3D signal never collapses to zero confidence from an occluded proxy") {
        let pose = PoseLandmarks(
            leftEar: Point2D(x: 0.4, y: 0.3, confidence: 0.0),
            pose3D: Pose3D(leftShoulder: p3(-0.4, 1.2, 0), rightShoulder: p3(0.4, 1.2, 0), spine: p3(0, 0, 0), centerHead: p3(0, 2.2, 0.15))
        )
        let context = PostureAnalysisContext(baseline: nil, sensitivity: .medium, viewpoint: ViewpointResult(band: .front, confidence: 0.7), systemInfo: SystemInfo(isAppleSilicon: true))
        let frame = BodyFrame3DAlgorithm().analyze(pose, context: context)
        try expect(frame.signal != nil, "3D should still evaluate with a sane fallback quality")
        try expect((frame.signal?.confidence ?? 0) >= Tuning.minimumTrackingConfidence, "occluded landmark must not drive 3D confidence to zero")
    }

    TestRegistry.test("3D quality ignores weak 2D proxy when 3D geometry is plausible") {
        let pose = PoseLandmarks(
            nose: lowConfidence(0.5, 0.3),
            leftShoulder: lowConfidence(0.35, 0.72),
            rightShoulder: lowConfidence(0.65, 0.72),
            pose3D: Pose3D(leftShoulder: p3(-0.4, 1.2, 0), rightShoulder: p3(0.4, 1.2, 0), spine: p3(0, 0, 0), centerHead: p3(0, 2.2, 0.15))
        )
        let context = PostureAnalysisContext(baseline: nil, sensitivity: .medium, viewpoint: ViewpointResult(band: .front, confidence: 0.7), systemInfo: SystemInfo(isAppleSilicon: true))
        let frame = BodyFrame3DAlgorithm().analyze(pose, context: context)
        try expect(frame.signal != nil, "plausible 3D geometry should still produce a signal")
        try expect((frame.signal?.confidence ?? 0) >= 0.6, "weak 2D proxy should not drag plausible 3D confidence below usable ML confidence")
    }

    TestRegistry.test("upright gate downgrades good to bad when head is clearly tilted") {
        let pose = PoseLandmarks(
            leftEye: confident(0.55, 0.30),
            rightEye: confident(0.45, 0.45),
            rightEar: confident(0.50, 0.32),
            rightShoulder: confident(0.52, 0.78),
            faceYawDegrees: 40
        )
        let viewpoint = ViewpointClassifier().classify(pose)
        let context = PostureAnalysisContext(baseline: nil, sensitivity: .medium, viewpoint: viewpoint, systemInfo: SystemInfo(isAppleSilicon: true))
        let frame = ProfileGeometryAlgorithm().analyze(pose, context: context)
        try expectEqual(frame.assessment, .bad, "clearly tilted head should not be good")
    }

    TestRegistry.test("upright gate keeps good when eyes are level") {
        let pose = PoseLandmarks(
            leftEye: confident(0.55, 0.30),
            rightEye: confident(0.45, 0.30),
            rightEar: confident(0.50, 0.32),
            rightShoulder: confident(0.52, 0.78),
            faceYawDegrees: 40
        )
        let viewpoint = ViewpointClassifier().classify(pose)
        let context = PostureAnalysisContext(baseline: nil, sensitivity: .medium, viewpoint: viewpoint, systemInfo: SystemInfo(isAppleSilicon: true))
        let frame = ProfileGeometryAlgorithm().analyze(pose, context: context)
        try expectEqual(frame.assessment, .good, "level head with upright angle should remain good")
    }

    TestRegistry.test("3D signed angle treats backward lean differently from forward head") {
        let forward = Pose3D(leftShoulder: p3(-0.2, 1.2, 0), rightShoulder: p3(0.2, 1.2, 0), spine: p3(0, 0, 0), centerHead: p3(0, 2.2, 0.3))
        let backward = Pose3D(leftShoulder: p3(-0.2, 1.2, 0), rightShoulder: p3(0.2, 1.2, 0), spine: p3(0, 0, 0), centerHead: p3(0, 2.2, -0.3))
        let forwardAngle = Geometry.bodySagittalAngleDegrees(from: forward) ?? -999
        let backwardAngle = Geometry.bodySagittalAngleDegrees(from: backward) ?? -999
        try expect(backwardAngle > forwardAngle, "signed angle: backward lean should not score like forward head")
    }

    TestRegistry.test("fusion selects profile on profile view") {
        let pose = PoseLandmarks(rightEar: confident(0.56, 0.28), rightShoulder: confident(0.54, 0.78), faceYawDegrees: 72)
        let viewpoint = ViewpointClassifier().classify(pose)
        let context = PostureAnalysisContext(baseline: nil, sensitivity: .medium, viewpoint: viewpoint, systemInfo: SystemInfo(isAppleSilicon: true))
        let frame = FusionAlgorithm().analyze(pose, context: context)
        try expectEqual(frame.signal?.kind, .profile2D, "fusion profile selection")
    }

    TestRegistry.test("fusion falls back to 3D on front view with 3D pose") {
        let pose = PoseLandmarks(
            leftEar: confident(0.35, 0.3),
            rightEar: confident(0.65, 0.3),
            leftShoulder: confident(0.3, 0.7),
            rightShoulder: confident(0.7, 0.7),
            faceYawDegrees: 0,
            pose3D: Pose3D(leftShoulder: p3(-0.4, 1.2, 0), rightShoulder: p3(0.4, 1.2, 0), spine: p3(0, 0, 0), centerHead: p3(0, 2.2, 0.15))
        )
        let viewpoint = ViewpointClassifier().classify(pose)
        let context = PostureAnalysisContext(baseline: nil, sensitivity: .medium, viewpoint: viewpoint, systemInfo: SystemInfo(isAppleSilicon: true))
        let frame = FusionAlgorithm().analyze(pose, context: context)
        try expectEqual(frame.signal?.kind, .body3D, "fusion 3D fallback on front")
    }

    TestRegistry.test("fusion withholds face position proxy without baseline") {
        // 거북목 클로즈업 재현: body 관절 전부 없음, 정면 응시, 얼굴 박스가 화면 아래(전방머리/숙임).
        // 얼굴 위치는 카메라 높이/각도에 민감하므로 baseline 없이 bad/good 판정하지 않는다.
        let pose = PoseLandmarks(
            faceYawDegrees: 0,
            faceRollDegrees: 0,
            faceBoundingBox: FaceBox(x: 0.37, y: 0.06, width: 0.27, height: 0.47)
        )
        let context = PostureAnalysisContext(baseline: nil, sensitivity: .medium, viewpoint: ViewpointClassifier().classify(pose), systemInfo: SystemInfo(isAppleSilicon: true))
        let frame = FusionAlgorithm().analyze(pose, context: context)
        try expectEqual(frame.assessment, .noEval, "face position proxy needs baseline because camera height changes")
        try expectEqual(frame.signal?.kind, .frontFace, "face proxy signal kind")
    }

    TestRegistry.test("fusion face position proxy uses baseline for relative bad judgment") {
        let pose = PoseLandmarks(
            faceYawDegrees: 0,
            faceRollDegrees: 0,
            faceBoundingBox: FaceBox(x: 0.37, y: 0.30, width: 0.27, height: 0.47)
        )
        let baseline = Baseline(profileAngle: nil, frontHeadDropRatio: nil, threeQuarterAngle: nil, frontFaceBottomY: 0.56)
        let context = PostureAnalysisContext(baseline: baseline, sensitivity: .medium, viewpoint: ViewpointClassifier().classify(pose), systemInfo: SystemInfo(isAppleSilicon: true))
        let frame = FusionAlgorithm().analyze(pose, context: context)
        try expectEqual(frame.assessment, .bad, "face position should be bad only relative to a baseline")
    }

    TestRegistry.test("fusion face position proxy uses baseline for relative good judgment") {
        let pose = PoseLandmarks(
            faceYawDegrees: 0,
            faceRollDegrees: 0,
            faceBoundingBox: FaceBox(x: 0.38, y: 0.50, width: 0.24, height: 0.42)
        )
        let baseline = Baseline(profileAngle: nil, frontHeadDropRatio: nil, threeQuarterAngle: nil, frontFaceBottomY: 0.56)
        let context = PostureAnalysisContext(baseline: baseline, sensitivity: .medium, viewpoint: ViewpointClassifier().classify(pose), systemInfo: SystemInfo(isAppleSilicon: true))
        let frame = FusionAlgorithm().analyze(pose, context: context)
        try expectEqual(frame.assessment, .good, "face position should stay good when close to baseline")
    }

    TestRegistry.test("face proxy detects tilt via face roll when eyes missing") {
        // 박스 y는 정상(전방머리 아님)이지만 머리가 기울었으면 faceRoll 폴백으로 bad.
        let pose = PoseLandmarks(
            faceYawDegrees: 0,
            faceRollDegrees: 30,
            faceBoundingBox: FaceBox(x: 0.38, y: 0.56, width: 0.20, height: 0.34)
        )
        let context = PostureAnalysisContext(baseline: nil, sensitivity: .medium, viewpoint: ViewpointClassifier().classify(pose), systemInfo: SystemInfo(isAppleSilicon: true))
        let frame = FusionAlgorithm().analyze(pose, context: context)
        try expectEqual(frame.assessment, .bad, "tilted head should be bad via face roll fallback")
    }

    TestRegistry.test("face proxy is skipped when head is turned away") {
        // 고개 돌림(yaw 큼)은 자세 판정 부적합 — 얼굴 박스 신호를 쓰지 않고 noEval.
        let pose = PoseLandmarks(
            faceYawDegrees: -45,
            faceRollDegrees: 0,
            faceBoundingBox: FaceBox(x: 0.3, y: 0.1, width: 0.18, height: 0.32)
        )
        let context = PostureAnalysisContext(baseline: nil, sensitivity: .medium, viewpoint: ViewpointClassifier().classify(pose), systemInfo: SystemInfo(isAppleSilicon: true))
        let frame = FusionAlgorithm().analyze(pose, context: context)
        try expectEqual(frame.assessment, .noEval, "turned head should not use face proxy")
    }

    TestRegistry.test("calibration captures face baseline even when body signals dominate") {
        // body 신호(threeQuarter)가 주도해도 모든 프레임의 faceBottomY로 frontFace baseline을 함께 확보한다(개인화 전제).
        let frames = (0..<5).map { i in
            AnalyzedFrame(
                assessment: .good,
                signal: PostureSignal(kind: .threeQuarter2D, angleDegrees: 75, confidence: 0.8),
                faceBottomY: 0.50 + Double(i) * 0.02
            )
        }
        guard case .accepted(let baseline) = Calibrator().capture(from: frames) else {
            throw TestFailure(message: "calibration should accept")
        }
        try expect(baseline.threeQuarterAngle != nil, "body baseline captured")
        try expect(baseline.frontFaceBottomY != nil, "face position baseline captured alongside body signal")
        try expect((baseline.frontFaceBottomY ?? 1) < 0.55, "face baseline uses conservative lower percentile")
    }

    TestRegistry.test("calibration without any face position leaves front face baseline empty") {
        let frames = (0..<5).map { _ in
            AnalyzedFrame(
                assessment: .good,
                signal: PostureSignal(kind: .threeQuarter2D, angleDegrees: 75, confidence: 0.8)
            )
        }
        guard case .accepted(let baseline) = Calibrator().capture(from: frames) else {
            throw TestFailure(message: "calibration should accept body-only frames")
        }
        try expect(baseline.frontFaceBottomY == nil, "no face position means no face baseline")
    }

    TestRegistry.test("calibration captures core ml relative depth baseline") {
        let frames = [0.10, 0.12, 0.14].map {
            AnalyzedFrame(
                assessment: .noEval,
                signal: PostureSignal(kind: .relativeDepth, angleDegrees: $0, confidence: 0.5),
                viewpoint: ViewpointResult(band: .front, confidence: 0.7)
            )
        }
        guard case .accepted(let baseline) = Calibrator().capture(from: frames) else {
            throw TestFailure(message: "relative depth calibration should accept")
        }
        try expectApprox(baseline.relativeDepthDelta ?? -1, 0.13, tolerance: 0.001, "relative depth baseline uses 75th percentile")
    }

    TestRegistry.test("ML auto calibration rejects face-only baseline") {
        let frames = [
            AnalyzedFrame(assessment: .noEval, viewpoint: ViewpointResult(band: .front, confidence: 0.45), faceBottomY: 0.56)
        ]
        let result = Calibrator().capture(from: frames, requiredAlgorithm: .mlAuto)
        try expectEqual(result, .rejected(.noReliableFrames), "ML auto should require a Core ML or Vision 3D baseline")
    }

    TestRegistry.test("calibration captures Vision 3D ML baselines") {
        let frames = [
            AnalyzedFrame(assessment: .good, signal: PostureSignal(kind: .body3D, angleDegrees: 72, confidence: 0.9), viewpoint: ViewpointResult(band: .front, confidence: 0.7)),
            AnalyzedFrame(assessment: .good, signal: PostureSignal(kind: .depth3D, angleDegrees: 0.10, confidence: 0.9), viewpoint: ViewpointResult(band: .front, confidence: 0.7)),
            AnalyzedFrame(assessment: .good, signal: PostureSignal(kind: .depth3D, angleDegrees: 0.14, confidence: 0.9), viewpoint: ViewpointResult(band: .front, confidence: 0.7))
        ]
        guard case .accepted(let baseline) = Calibrator().capture(from: frames) else {
            throw TestFailure(message: "Vision 3D calibration should accept")
        }
        try expectApprox(baseline.bodyFrameAngle ?? -1, 72, tolerance: 0.001, "body 3D baseline should be captured")
        try expectApprox(baseline.depthDeltaNorm ?? -1, 0.13, tolerance: 0.001, "depth 3D baseline should use 75th percentile")
    }
}
