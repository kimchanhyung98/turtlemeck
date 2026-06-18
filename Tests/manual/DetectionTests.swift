import Foundation

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
        let analyzed = PostureAnalyzer().analyze(pose, baseline: nil, cameraPlacement: .center, sensitivity: .medium)
        try expectEqual(analyzed.assessment, .good, "upright profile should pass absolute threshold")
        try expect(analyzed.signal?.angleDegrees ?? 0 > 65, "upright angle")
    }

    TestRegistry.test("forward profile is bad without baseline") {
        let pose = PoseLandmarks(
            rightEar: confident(0.87, 0.47),
            rightShoulder: confident(0.52, 0.78),
            faceYawDegrees: 74
        )
        let analyzed = PostureAnalyzer().analyze(pose, baseline: nil, cameraPlacement: .center, sensitivity: .medium)
        try expectEqual(analyzed.assessment, .bad, "forward profile should fail absolute threshold")
        try expect(analyzed.signal?.angleDegrees ?? 90 < 55, "forward angle")
    }

    TestRegistry.test("front pose without baseline is no-eval") {
        let pose = PoseLandmarks(
            leftEar: confident(0.35, 0.3),
            rightEar: confident(0.65, 0.3),
            leftShoulder: confident(0.3, 0.7),
            rightShoulder: confident(0.7, 0.7),
            faceYawDegrees: 0
        )
        let analyzed = PostureAnalyzer().analyze(pose, baseline: nil, cameraPlacement: .center, sensitivity: .medium)
        try expectEqual(analyzed.assessment, .noEval, "front absolute judgment should be withheld")
        try expectEqual(analyzed.signal?.kind, .front2D, "front signal should still be available for calibration")
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
        let analyzed = PostureAnalyzer().analyze(pose, baseline: baseline, cameraPlacement: .center, sensitivity: .medium)
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
        let analyzed = PostureAnalyzer().analyze(pose, baseline: baseline, cameraPlacement: .center, sensitivity: .medium)
        try expectEqual(analyzed.assessment, .good, "matching normalized front ratio should be good")
    }

    TestRegistry.test("head-only rotation guard with center camera returns no-eval") {
        let pose = PoseLandmarks(
            rightEar: confident(0.57, 0.28),
            leftShoulder: confident(0.28, 0.72),
            rightShoulder: confident(0.72, 0.72),
            faceYawDegrees: 75
        )
        let analyzed = PostureAnalyzer().analyze(pose, baseline: nil, cameraPlacement: .center, sensitivity: .medium)
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
        let analyzed = PostureAnalyzer(systemInfo: SystemInfo(isAppleSilicon: true)).analyze(pose, baseline: nil, cameraPlacement: .center, sensitivity: .medium)
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
        let analyzed = PostureAnalyzer().analyze(pose, baseline: nil, cameraPlacement: .right, sensitivity: .medium)
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
        let analyzed = PostureAnalyzer(systemInfo: SystemInfo(isAppleSilicon: true)).analyze(pose, baseline: nil, cameraPlacement: .center, sensitivity: .medium)
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
        let analyzed = PostureAnalyzer(systemInfo: SystemInfo(isAppleSilicon: false)).analyze(pose, baseline: nil, cameraPlacement: .center, sensitivity: .medium)
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

    TestRegistry.test("calibrator rejects slouched profile baseline") {
        let frame = AnalyzedFrame(assessment: .bad, signal: PostureSignal(kind: .profile2D, angleDegrees: 42, confidence: 0.9), viewpoint: ViewpointResult(band: .profileRight, confidence: 0.9, nearSide: .right))
        let result = Calibrator().capture(from: [frame])
        try expectEqual(result, .rejected(.alreadySlouched), "reject slouched baseline")
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
}
