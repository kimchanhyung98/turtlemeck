import CoreGraphics
import Foundation
import TurtleCore

func registerWorkflowTests() {
    TestRegistry.test("relative depth feature is affine invariant") {
        let landmarks = validLandmarks()
        let original = depthMap { x, y in Double(y) + Double(x) * 0.2 }
        let transformed = RelativeDepthMap(
            width: original.width,
            height: original.height,
            values: original.values.map { $0 * 3 + 7 },
            direction: original.direction
        )
        let lhs = PostureFrameAnalyzer().analyze(landmarks: landmarks, depthMap: original)
        let rhs = PostureFrameAnalyzer().analyze(landmarks: landmarks, depthMap: transformed)
        try expect(lhs.isValid && rhs.isValid, "both affine forms must be valid")
        try expectApprox(try unwrap(lhs.feature, "missing first feature"), try unwrap(rhs.feature, "missing second feature"), "feature must be affine invariant")
    }

    TestRegistry.test("depth near-far direction is explicit") {
        let map = depthMap(direction: .largerIsNear) { x, y in Double(y) + Double(x) * 0.2 }
        let reversed = RelativeDepthMap(width: map.width, height: map.height, values: map.values, direction: .smallerIsNear)
        let first = PostureFrameAnalyzer().analyze(landmarks: validLandmarks(), depthMap: map)
        let second = PostureFrameAnalyzer().analyze(landmarks: validLandmarks(), depthMap: reversed)
        let reversedFeature = try unwrap(second.feature, "missing second direction")
        try expectApprox(try unwrap(first.feature, "missing first direction"), -reversedFeature, "direction must flip feature sign")
    }

    TestRegistry.test("frame quality rejects missing landmarks and flat depth") {
        var missing = validLandmarks()
        missing.rightShoulder = nil
        let analyzer = PostureFrameAnalyzer()
        try expectEqual(analyzer.analyze(landmarks: missing, depthMap: depthMap { x, y in Double(x + y) }).exclusionReason, .missingShoulder, "missing shoulder")
        let flat = RelativeDepthMap(width: 100, height: 100, values: Array(repeating: 1, count: 10_000), direction: .largerIsNear)
        try expectEqual(analyzer.analyze(landmarks: validLandmarks(), depthMap: flat).exclusionReason, .insufficientDepthRange, "flat depth must be no-eval")
    }

    TestRegistry.test("visible lower torso remains usable near frame boundary") {
        var landmarks = validLandmarks(shoulderWidth: 0.37)
        landmarks.nose?.y = 0.45
        landmarks.leftEye?.y = 0.42
        landmarks.rightEye?.y = 0.42
        landmarks.leftEar?.y = 0.5
        landmarks.rightEar?.y = 0.5
        landmarks.leftShoulder?.y = 0.85
        landmarks.rightShoulder?.y = 0.85
        let result = PostureFrameAnalyzer().analyze(
            landmarks: landmarks,
            depthMap: depthMap { x, y in Double(y) + Double(x) * 0.2 }
        )
        try expect(result.isValid, "visible portion of slightly clipped torso ROI should be analyzed: \(String(describing: result.exclusionReason))")
        try expect(result.quality.roiBoundaryContactRatio > 0.3, "observed close-camera clipping must remain visible in quality diagnostics")
        try expectEqual(result.rois?.torso.maxY, 1, "torso ROI must use only visible pixels")
    }

    TestRegistry.test("slouched close-camera torso remains evaluable for confirmation") {
        var landmarks = validLandmarks(shoulderWidth: 0.35)
        landmarks.nose?.y = 0.5
        landmarks.leftEye?.y = 0.47
        landmarks.rightEye?.y = 0.47
        landmarks.leftEar?.y = 0.5
        landmarks.rightEar?.y = 0.5
        landmarks.leftShoulder?.y = 0.88
        landmarks.rightShoulder?.y = 0.88
        let result = PostureFrameAnalyzer().analyze(
            landmarks: landmarks,
            depthMap: depthMap { x, y in Double(y) + Double(x) * 0.2 }
        )
        try expect(result.isValid, "observed 52% lower-boundary contact should retain visible torso pixels")
        try expect(result.quality.roiBoundaryContactRatio > 0.4, "fixture should cover a heavily clipped slouched frame")
    }

    TestRegistry.test("single head-anchor outlier does not move the head ROI") {
        var landmarks = validLandmarks()
        landmarks.leftEar = Point2D(x: 0.02, y: 0.65, confidence: 0.95)
        let result = PostureFrameAnalyzer().analyze(
            landmarks: landmarks,
            depthMap: depthMap { x, y in Double(y) + Double(x) * 0.2 }
        )
        let head = try unwrap(result.rois?.head, "head ROI missing")
        try expectApprox(head.x + head.width / 2, 0.5, accuracy: 0.001, "head ROI should use a robust anchor center")
    }

    TestRegistry.test("subject selector uses size then burst continuity") {
        var selector = UpperBodySubjectSelector()
        let large = validLandmarks(centerX: 0.35, shoulderWidth: 0.4)
        let small = validLandmarks(centerX: 0.75, shoulderWidth: 0.2)
        guard case .selected(let selected) = selector.select(from: [small, large]) else {
            throw testFailure("expected initial subject")
        }
        try expectEqual(selected.neck?.x, large.neck?.x, "largest unambiguous upper body")
        let moved = validLandmarks(centerX: 0.38, shoulderWidth: 0.36)
        let other = validLandmarks(centerX: 0.78, shoulderWidth: 0.44)
        guard case .selected(let tracked) = selector.select(from: [other, moved]) else {
            throw testFailure("expected tracked subject")
        }
        try expectEqual(tracked.neck?.x, moved.neck?.x, "continuity must beat new size")
        selector.reset()
        try expectEqual(selector.select(from: [moved, validLandmarks(centerX: 0.7, shoulderWidth: 0.34)]), .rejected(.ambiguousSubject), "similar subjects must be rejected")
    }

    TestRegistry.test("side-view shoulder confidence keeps usable landmarks only") {
        var selector = UpperBodySubjectSelector()
        var usable = validLandmarks()
        usable.leftShoulder?.confidence = 0.16
        guard case .selected = selector.select(from: [usable]) else {
            throw testFailure("measured side-view shoulder should remain usable")
        }

        selector.reset()
        var unreliable = validLandmarks()
        unreliable.leftShoulder?.confidence = 0.14
        try expectEqual(selector.select(from: [unreliable]), .rejected(.noSubject), "lower-confidence shoulder must remain no-eval")
    }

    TestRegistry.test("burst aggregates median and MAD before baseline comparison") {
        let frames = [0.1, 0.12, 0.11, 4.0, 0.09].enumerated().map { timedFrame(index: $0.offset + 1, feature: $0.element) }
        let baseline = Baseline(center: 0.1, dispersion: 0.02, burstCount: 3, captureConfiguration: testCaptureConfiguration)
        let verdict = BurstProcessor().process(frames, baseline: baseline, captureConfiguration: testCaptureConfiguration)
        try expectEqual(verdict.evidence, .normal, "median should resist one outlier")
        try expectApprox(try unwrap(verdict.summary.medianFeature, "median missing"), 0.11, "median")
        try expectApprox(try unwrap(verdict.summary.featureMAD, "MAD missing"), 0.01, "MAD")
        let worsened = (0..<5).map { timedFrame(index: $0 + 1, feature: 0.6 + Double($0) * 0.01) }
        try expectEqual(BurstProcessor().process(worsened, baseline: baseline, captureConfiguration: testCaptureConfiguration).evidence, .worsened, "worsened delta")
        try expectEqual(BurstProcessor().process(worsened, baseline: nil, captureConfiguration: testCaptureConfiguration).evidence, .noEval, "baseline is mandatory")
        let changed = CaptureConfiguration(cameraUniqueID: "other-camera", width: 640, height: 480, orientation: "up-unmirrored")
        let changedVerdict = BurstProcessor().process(worsened, baseline: baseline, captureConfiguration: changed)
        try expectEqual(changedVerdict.reason, "capture configuration changed", "configuration change reason")
        try expect(changedVerdict.requiresCalibration, "configuration change requires calibration")
    }

    TestRegistry.test("measured same-posture drift remains normal") {
        let baseline = Baseline(center: -1.752, dispersion: 0.069, burstCount: 3, captureConfiguration: testCaptureConfiguration)
        let samePosture = (0..<5).map { timedFrame(index: $0 + 1, feature: -1.565 + Double($0 - 2) * 0.01) }
        let verdict = BurstProcessor().process(samePosture, baseline: baseline, captureConfiguration: testCaptureConfiguration)
        try expectEqual(verdict.evidence, .normal, "observed post-calibration drift should stay in the normal band")

        let uncertain = (0..<5).map { timedFrame(index: $0 + 1, feature: -1.452 + Double($0 - 2) * 0.01) }
        try expectEqual(
            BurstProcessor().process(uncertain, baseline: baseline, captureConfiguration: testCaptureConfiguration).evidence,
            .insufficient,
            "values between normal and worsening margins should remain uncertain"
        )
    }

    TestRegistry.test("burst rejects insufficient coverage and instability") {
        let baseline = Baseline(center: 0, dispersion: 0.01, burstCount: 3, captureConfiguration: testCaptureConfiguration)
        try expectEqual(BurstProcessor().process([timedFrame(index: 1, feature: 0)], baseline: baseline, captureConfiguration: testCaptureConfiguration).evidence, .noEval, "one frame is insufficient")
        let twoVisible = [
            timedFrame(index: 1, feature: 0.7),
            timedFrame(index: 2, feature: nil),
            timedFrame(index: 3, feature: 0.72),
            timedFrame(index: 4, feature: nil),
            timedFrame(index: 5, feature: nil)
        ]
        try expectEqual(
            BurstProcessor().process(twoVisible, baseline: baseline, captureConfiguration: testCaptureConfiguration).evidence,
            .worsened,
            "two stable visible frames should keep the scheduled check evaluable"
        )
        let unstable = [0.0, 1.0, 2.0, 3.0, 4.0].enumerated().map { timedFrame(index: $0.offset + 1, feature: $0.element) }
        try expectEqual(BurstProcessor().process(unstable, baseline: baseline, captureConfiguration: testCaptureConfiguration).reason, "unstable burst", "high MAD")
    }

    TestRegistry.test("calibration accepts a reliable burst and rejects unreliable input") {
        let requiredBursts = Tuning.requiredCalibrationBursts
        let stable = (0..<requiredBursts).map { _ in
            burstSummary(center: 0.1, mad: 0.02)
        }
        guard case .accepted(let baseline) = Calibrator().capture(from: stable, captureConfiguration: testCaptureConfiguration, now: Date(timeIntervalSince1970: 10)) else {
            throw testFailure("stable calibration rejected")
        }
        try expectApprox(baseline.center, 0.1, "baseline center")
        try expectEqual(baseline.burstCount, requiredBursts, "baseline burst count")
        try expectEqual(
            Calibrator().capture(from: Array(stable.dropLast()), captureConfiguration: testCaptureConfiguration),
            .rejected(.noReliableBursts),
            "fewer than the configured burst count is insufficient"
        )
        try expectEqual(
            Calibrator().capture(from: [burstSummary(center: 0.1, mad: 1.0)], captureConfiguration: testCaptureConfiguration),
            .rejected(.noReliableBursts),
            "noisy burst must not produce a baseline"
        )
        try expect(Calibrator.isReliable(burstSummary(center: 0.1, mad: 0.02)), "stable burst counts toward calibration")
        try expect(!Calibrator.isReliable(burstSummary(center: 0.1, mad: 1.0)), "noisy burst must not count toward calibration")
    }

    TestRegistry.test("state machine requires bad and recovery persistence") {
        var machine = PostureStateMachine(requiredBadBursts: 2, requiredRecoveryBursts: 2, requiredNoEvalBursts: 3)
        try expectEqual(machine.apply(simpleVerdict(.normal)).state, .good, "normal evidence")
        try expectEqual(machine.apply(simpleVerdict(.worsened)).state, .good, "first bad stays good")
        let bad = machine.apply(simpleVerdict(.worsened))
        try expectEqual(bad.state, .bad, "second bad confirms")
        try expectEqual(bad.alert, .cautionStarted, "bad transition alerts")
        try expectEqual(machine.apply(simpleVerdict(.normal)).state, .bad, "first recovery stays bad")
        let recovered = machine.apply(simpleVerdict(.normal))
        try expectEqual(recovered.state, .good, "second recovery confirms")
        try expectEqual(recovered.alert, .recovered, "confirmed recovery emits stats event")
    }

    TestRegistry.test("state machine defaults follow tuning") {
        var machine = PostureStateMachine()
        _ = machine.apply(simpleVerdict(.normal))
        for attempt in 1...Tuning.requiredBadBursts {
            let transition = machine.apply(simpleVerdict(.worsened))
            try expectEqual(
                transition.state == .bad,
                attempt == Tuning.requiredBadBursts,
                "bad persistence attempt \(attempt)"
            )
        }
        for attempt in 1...Tuning.requiredRecoveryBursts {
            let transition = machine.apply(simpleVerdict(.normal))
            try expectEqual(
                transition.state == .good,
                attempt == Tuning.requiredRecoveryBursts,
                "recovery persistence attempt \(attempt)"
            )
        }
    }

    TestRegistry.test("no-eval and insufficient evidence never count as good") {
        var machine = PostureStateMachine(requiredNoEvalBursts: 3)
        _ = machine.apply(simpleVerdict(.normal))
        try expectEqual(machine.apply(simpleVerdict(.noEval)).state, .good, "single no-eval preserves state")
        try expectEqual(machine.apply(simpleVerdict(.insufficient)).state, .good, "hysteresis band preserves state")
        try expectEqual(machine.apply(simpleVerdict(.insufficient)).state, .noEval, "all unavailable evidence expires stale state")
    }

    TestRegistry.test("debug artifacts use timestamp session and unpadded frame names") {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent("turtlemeck-debug-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DebugCaptureStore(rootURL: root)
        let session = try unwrap(store.prepareRun(now: Date(timeIntervalSince1970: 0)), "debug session")
        let analysis = PostureFrameAnalyzer().analyze(
            landmarks: validLandmarks(),
            depthMap: depthMap { x, y in Double(y) + Double(x) * 0.2 }
        )
        try expect(analysis.isValid, "debug frame analysis")
        let frame = TimedFrame(time: 0, analysis: analysis, index: 1)
        store.writeFrame(session: session, index: 1, time: 0, inputImage: try testImage(), depthImage: try testImage(), analysis: frame.analysis)
        let diagnostic = PostureDiagnostic(
            assessment: .good,
            productState: .good,
            evidence: .normal,
            summary: burstSummary(center: try unwrap(analysis.feature, "debug feature"), mad: 0.01),
            frames: [frame],
            stageProcessingMilliseconds: ["feature": 1]
        )
        let path = store.writeSession(
            session: session,
            verdict: simpleVerdict(.normal),
            calibrationResult: nil,
            diagnostic: diagnostic,
            baseline: nil
        )
        let names = try Set(FileManager.default.contentsOfDirectory(atPath: path))
        try expect(names.isSuperset(of: ["capture-1.png", "overlay-1.png", "depth-1.png", "frame-1.json", "session.json"]), "required debug artifacts")
        try expect(!names.contains("frame-01.json"), "frame number must not be padded")
        let sessionData = try Data(contentsOf: URL(fileURLWithPath: path).appendingPathComponent("session.json"))
        let json = try unwrap(try JSONSerialization.jsonObject(with: sessionData) as? [String: Any], "session JSON object")
        let storedDiagnostic = try unwrap(json["diagnostic"] as? [String: Any], "stored diagnostic")
        try expectEqual(storedDiagnostic["productState"] as? String, "good", "session product state")
        let storedFrames = try unwrap(storedDiagnostic["frames"] as? [[String: Any]], "session frame diagnostics")
        try expectEqual(storedFrames.count, 1, "session frame count")
        let storedAnalysis = try unwrap(storedFrames.first?["analysis"] as? [String: Any], "stored frame analysis")
        try expect(storedAnalysis["depth"] is [String: Any], "session depth summary")
        try expect(storedAnalysis["quality"] is [String: Any], "session quality")
        try expectEqual((json["stageProcessingMilliseconds"] as? [String: Double])?["feature"], 1, "session stage timing")
    }
}

private func validLandmarks(centerX: Double = 0.5, shoulderWidth: Double = 0.4) -> PoseLandmarks {
    func point(_ x: Double, _ y: Double) -> Point2D { Point2D(x: x, y: y, confidence: 0.95) }
    return PoseLandmarks(
        nose: point(centerX, 0.24),
        leftEye: point(centerX - 0.03, 0.22),
        rightEye: point(centerX + 0.03, 0.22),
        leftEar: point(centerX - 0.07, 0.25),
        rightEar: point(centerX + 0.07, 0.25),
        neck: point(centerX, 0.46),
        leftShoulder: point(centerX - shoulderWidth / 2, 0.5),
        rightShoulder: point(centerX + shoulderWidth / 2, 0.5)
    )
}

private func depthMap(direction: DepthDirection = .largerIsNear, value: (Int, Int) -> Double) -> RelativeDepthMap {
    let width = 100
    let height = 100
    return RelativeDepthMap(
        width: width,
        height: height,
        values: (0..<height).flatMap { y in (0..<width).map { x in value(x, y) } },
        direction: direction
    )
}

private func timedFrame(index: Int, feature: Double?) -> TimedFrame {
    TimedFrame(time: Double(index) * 0.4, analysis: FrameAnalysis(landmarks: PoseLandmarks(), feature: feature), index: index)
}

private func burstSummary(center: Double, mad: Double) -> BurstSummary {
    BurstSummary(totalFrameCount: 5, validFrameCount: 5, medianFeature: center, featureMAD: mad, exclusionCounts: [:])
}

private func simpleVerdict(_ evidence: BurstEvidence) -> BurstVerdict {
    BurstVerdict(evidence: evidence, summary: burstSummary(center: 0, mad: 0))
}

private func testImage() throws -> CGImage {
    let provider = try unwrap(CGDataProvider(data: Data(repeating: 128, count: 100) as CFData), "image provider")
    return try unwrap(CGImage(
        width: 10,
        height: 10,
        bitsPerComponent: 8,
        bitsPerPixel: 8,
        bytesPerRow: 10,
        space: CGColorSpaceCreateDeviceGray(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    ), "test image")
}
