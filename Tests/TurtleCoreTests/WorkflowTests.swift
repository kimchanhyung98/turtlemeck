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

    TestRegistry.test("torso band stays fully visible at typical laptop framing") {
        // 실측 구도: 어깨 y≈0.85~0.88, 어깨폭 0.35~0.37 — 구 기하(어깨 아래 0.34sw)는 여기서 항상 하단을 벗어났다.
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
        try expect(result.isValid, "shoulder-line band must be evaluable at typical laptop framing: \(String(describing: result.exclusionReason))")
        try expectEqual(result.quality.roiBoundaryContactRatio, 0, "band must not touch the frame boundary")
        let torsoMaxY = try unwrap(result.rois?.torso.maxY, "torso ROI missing")
        try expect(torsoMaxY < 1, "band must stay fully inside the frame")
    }

    TestRegistry.test("close-camera framing keeps the torso band evaluable") {
        // 실측 최악 구도(근접 착석, 어깨 y≈0.93)에서도 밴드는 화면 안에 남아야 한다.
        var landmarks = validLandmarks(shoulderWidth: 0.4)
        landmarks.nose?.y = 0.5
        landmarks.leftEye?.y = 0.47
        landmarks.rightEye?.y = 0.47
        landmarks.leftEar?.y = 0.5
        landmarks.rightEar?.y = 0.5
        landmarks.leftShoulder?.y = 0.93
        landmarks.rightShoulder?.y = 0.93
        let result = PostureFrameAnalyzer().analyze(
            landmarks: landmarks,
            depthMap: depthMap { x, y in Double(y) + Double(x) * 0.2 }
        )
        try expect(result.isValid, "close-camera framing must stay evaluable: \(String(describing: result.exclusionReason))")
        try expectEqual(result.quality.roiBoundaryContactRatio, 0, "band must not touch the frame boundary even when seated close")
    }

    TestRegistry.test("occluded shoulders mark the frame as unassessable posture") {
        // 턱 괴기 실측: 팔이 어깨를 가리면 어깨 confidence가 0.14~0.31로 무너진다(정상 최소 0.51).
        var chinProp = validLandmarks()
        chinProp.leftShoulder?.confidence = 0.31
        let analyzer = PostureFrameAnalyzer()
        let map = depthMap { x, y in Double(y) + Double(x) * 0.2 }
        try expectEqual(analyzer.analyze(landmarks: chinProp, depthMap: map).exclusionReason, .missingShoulder, "occluded shoulder must exclude the frame as unassessable")

        var confident = validLandmarks()
        confident.leftShoulder?.confidence = 0.51
        confident.rightShoulder?.confidence = 0.51
        try expect(analyzer.analyze(landmarks: confident, depthMap: map).isValid, "measured normal-posture confidence must stay valid")
    }

    TestRegistry.test("head dropped toward shoulders marks the frame as unassessable posture") {
        var dropped = validLandmarks()
        dropped.nose?.y = 0.64
        dropped.leftEye?.y = 0.62
        dropped.rightEye?.y = 0.62
        dropped.leftEar?.y = 0.65
        dropped.rightEar?.y = 0.65
        let result = PostureFrameAnalyzer().analyze(
            landmarks: dropped,
            depthMap: depthMap { x, y in Double(y) + Double(x) * 0.2 }
        )
        try expectEqual(result.exclusionReason, .headDropped, "tilted or slumped head must be excluded as abnormal")
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
        try expectEqual(selector.select(from: [unreliable]), .rejected(.missingShoulder), "reliable head without shoulders is an unassessable subject, not an absent one")

        selector.reset()
        var headless = validLandmarks()
        headless.nose = nil
        headless.leftEye = nil
        headless.rightEye = nil
        headless.leftEar = nil
        headless.rightEar = nil
        headless.leftShoulder?.confidence = 0.1
        try expectEqual(selector.select(from: [headless]), .rejected(.noSubject), "no reliable head anchor means no subject")
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

    TestRegistry.test("baseline distance boundaries are symmetric") {
        let baseline = Baseline(center: 0, dispersion: 0.01, burstCount: 1, captureConfiguration: testCaptureConfiguration)
        let recovery = Tuning.recoveryMargin(baselineDispersion: baseline.dispersion)
        let worsening = Tuning.worseningMargin(baselineDispersion: baseline.dispersion)
        func evidence(at offset: Double) -> BurstEvidence {
            let frames = (1...5).map { timedFrame(index: $0, feature: offset) }
            return BurstProcessor().process(frames, baseline: baseline, captureConfiguration: testCaptureConfiguration).evidence
        }

        for direction in [-1.0, 1.0] {
            try expectEqual(evidence(at: direction * recovery), .normal, "the recovery boundary must be inclusive in both directions")
            try expectEqual(
                evidence(at: direction * ((recovery + worsening) / 2)),
                .insufficient,
                "the hysteresis band must be symmetric"
            )
            try expectEqual(evidence(at: direction * worsening), .worsened, "the worsening boundary must be inclusive in both directions")
        }
    }

    TestRegistry.test("invalid baselines fail closed and request recalibration") {
        func baseline(
            center: Double = 0,
            dispersion: Double = 0.01,
            burstCount: Int = 1,
            featureVersion: Int = Baseline.currentFeatureVersion
        ) -> Baseline {
            Baseline(
                center: center,
                dispersion: dispersion,
                burstCount: burstCount,
                captureConfiguration: testCaptureConfiguration,
                featureVersion: featureVersion
            )
        }
        let invalidCases = [
            ("non-finite center", baseline(center: .infinity)),
            ("NaN center", baseline(center: .nan)),
            ("non-finite dispersion", baseline(dispersion: .infinity)),
            ("out-of-range dispersion", baseline(dispersion: .greatestFiniteMagnitude)),
            ("negative dispersion", baseline(dispersion: -0.01)),
            ("empty calibration", baseline(burstCount: 0)),
            ("stale feature version", baseline(featureVersion: Baseline.currentFeatureVersion - 1))
        ]
        let frames = (1...5).map { timedFrame(index: $0, feature: 0) }

        for (name, invalidBaseline) in invalidCases {
            let verdict = BurstProcessor().process(
                frames,
                baseline: invalidBaseline,
                captureConfiguration: testCaptureConfiguration
            )
            try expectEqual(verdict.evidence, .noEval, "\(name) must not produce posture evidence")
            try expectEqual(verdict.reason, "baseline invalid", "\(name) reason")
            try expect(verdict.requiresCalibration, "\(name) must request recalibration")
        }
    }

    TestRegistry.test("posture judgment follows an abnormal user baseline in either direction") {
        let reference = (0..<Tuning.requiredCalibrationBursts).map { _ in
            BurstSummary(
                totalFrameCount: 5,
                validFrameCount: 5,
                medianFeature: 0.47,
                featureMAD: 0.04,
                exclusionCounts: [:],
                medianShoulderMidY: 0.84,
                medianShoulderWidth: 0.4
            )
        }
        guard case .accepted(let abnormalBaseline) = Calibrator().capture(from: reference, captureConfiguration: testCaptureConfiguration) else {
            throw testFailure("stable user reference must be accepted without an objective-posture override")
        }
        func anchoredBurst(feature: Double) -> [TimedFrame] {
            (1...5).map { anchoredFrame(index: $0, feature: feature, shoulderMidY: 0.84, shoulderWidth: 0.4) }
        }

        let sameAbnormalPosture = BurstProcessor().process(
            anchoredBurst(feature: 0.47),
            baseline: abnormalBaseline,
            captureConfiguration: testCaptureConfiguration
        )
        try expectEqual(sameAbnormalPosture.evidence, .normal, "the user reference itself must be normal evidence")
        try expectEqual(sameAbnormalPosture.assessment, .good, "the user reference itself must be a good product assessment")

        let fartherPositive = BurstProcessor().process(
            anchoredBurst(feature: 0.84),
            baseline: abnormalBaseline,
            captureConfiguration: testCaptureConfiguration
        )
        try expectEqual(fartherPositive.evidence, .worsened, "a large positive deviation must be abnormal too")

        let objectivelyNormal = anchoredBurst(feature: -1.21)
        let verdict = BurstProcessor().process(objectivelyNormal, baseline: abnormalBaseline, captureConfiguration: testCaptureConfiguration)
        try expectEqual(
            verdict.evidence,
            .worsened,
            "a large deviation from the user baseline must be abnormal even when feature decreases"
        )
        try expectEqual(verdict.assessment, .bad, "an objectively normal posture can be bad relative to the user reference")
        try expectApprox(try unwrap(verdict.baselineDelta, "signed baseline delta"), -1.68, "diagnostics preserve deviation direction")

        let changedConfiguration = CaptureConfiguration(cameraUniqueID: "other-camera", width: 640, height: 480, orientation: "up-unmirrored")
        let missingConfiguration = BurstProcessor().process(
            anchoredBurst(feature: 0.47),
            baseline: abnormalBaseline,
            captureConfiguration: nil
        )
        try expectEqual(missingConfiguration.evidence, .noEval, "missing capture metadata must fail closed")
        try expectEqual(missingConfiguration.reason, "capture configuration unavailable", "missing configuration reason")

        let configurationFailureCases: [(String, [TimedFrame])] = [
            ("absent subject", (1...5).map { excludedFrame(index: $0, reason: .noSubject, landmarks: PoseLandmarks()) }),
            ("model failure", (1...5).map { excludedFrame(index: $0, reason: .modelFailure, landmarks: validLandmarks()) }),
            ("unassessable posture", (1...5).map { excludedFrame(index: $0, reason: .missingShoulder, landmarks: validLandmarks()) })
        ]
        for (name, frames) in configurationFailureCases {
            let verdict = BurstProcessor().process(
                frames,
                baseline: abnormalBaseline,
                captureConfiguration: changedConfiguration
            )
            try expectEqual(verdict.evidence, .noEval, "\(name) must not hide a stale capture configuration")
            try expectEqual(verdict.reason, "capture configuration changed", "\(name) configuration reason")
            try expect(verdict.requiresCalibration, "\(name) must preserve the recalibration request")
        }

        let movedFraming = (1...5).map {
            anchoredFrame(index: $0, feature: 0.47, shoulderMidY: 0.77, shoulderWidth: 0.4)
        }
        let framingError = BurstProcessor().process(
            movedFraming,
            baseline: abnormalBaseline,
            captureConfiguration: testCaptureConfiguration
        )
        try expectEqual(framingError.evidence, .noEval, "an abnormal baseline must not bypass framing validation")
        try expect(framingError.requiresCalibration, "framing drift must still request recalibration")
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

    TestRegistry.test("excluded frames never contribute stale features") {
        let baseline = Baseline(center: 0, dispersion: 0.01, burstCount: 1, captureConfiguration: testCaptureConfiguration)
        let staleFeature = TimedFrame(
            time: 0.8,
            analysis: FrameAnalysis(
                landmarks: validLandmarks(),
                feature: 0,
                exclusionReason: .modelFailure
            ),
            index: 2
        )
        let frames = [
            timedFrame(index: 1, feature: 0),
            staleFeature,
            excludedFrame(index: 3, reason: .noSubject, landmarks: PoseLandmarks()),
            excludedFrame(index: 4, reason: .noSubject, landmarks: PoseLandmarks()),
            excludedFrame(index: 5, reason: .noSubject, landmarks: PoseLandmarks())
        ]
        let verdict = BurstProcessor().process(frames, baseline: baseline, captureConfiguration: testCaptureConfiguration)
        try expectEqual(verdict.summary.validFrameCount, 1, "a feature attached to an excluded frame must stay invalid")
        try expectEqual(verdict.evidence, .noEval, "stale feature data must not mask insufficient coverage")
    }

    TestRegistry.test("head detected but unassessable posture is abnormal, absent subject stays no-eval") {
        let baseline = Baseline(center: 0, dispersion: 0.01, burstCount: 1, captureConfiguration: testCaptureConfiguration)
        let chinProp = (1...5).map { excludedFrame(index: $0, reason: .missingShoulder, landmarks: validLandmarks()) }
        let chinPropVerdict = BurstProcessor().process(chinProp, baseline: baseline, captureConfiguration: testCaptureConfiguration)
        try expectEqual(chinPropVerdict.evidence, .worsened, "chin-prop burst must count as abnormal posture")
        try expectEqual(chinPropVerdict.reason, "posture unassessable", "abnormal reason")

        // 기준 자세가 없어도 '정상 판정 불가'는 비정상 증거다(baseline 비교가 필요 없는 판정).
        let withoutBaseline = BurstProcessor().process(chinProp, baseline: nil, captureConfiguration: testCaptureConfiguration)
        try expectEqual(withoutBaseline.evidence, .worsened, "unassessable posture does not need a baseline")

        let emptyRoom = (1...5).map { excludedFrame(index: $0, reason: .noSubject, landmarks: PoseLandmarks()) }
        try expectEqual(
            BurstProcessor().process(emptyRoom, baseline: baseline, captureConfiguration: testCaptureConfiguration).evidence,
            .noEval,
            "absent subject must stay no-eval"
        )

        // 유효 프레임이 더 많으면 feature 경로가 우선한다.
        let mixed = [
            excludedFrame(index: 1, reason: .missingShoulder, landmarks: validLandmarks()),
            timedFrame(index: 2, feature: 0.01),
            timedFrame(index: 3, feature: 0.02),
            timedFrame(index: 4, feature: 0.0),
            excludedFrame(index: 5, reason: .missingShoulder, landmarks: validLandmarks())
        ]
        try expectEqual(
            BurstProcessor().process(mixed, baseline: baseline, captureConfiguration: testCaptureConfiguration).evidence,
            .normal,
            "majority of valid frames keeps the feature path"
        )
    }

    TestRegistry.test("abnormal escalation requires a majority of the captured frames") {
        let baseline = Baseline(center: 0, dispersion: 0.01, burstCount: 1, captureConfiguration: testCaptureConfiguration)
        // 사람 부재 프레임이 다수인 버스트는 소수의 평가 불가 프레임만으로 비정상이 되지 않는다.
        let mostlyAbsent = [
            excludedFrame(index: 1, reason: .missingShoulder, landmarks: validLandmarks()),
            excludedFrame(index: 2, reason: .missingShoulder, landmarks: validLandmarks()),
            excludedFrame(index: 3, reason: .noSubject, landmarks: PoseLandmarks()),
            excludedFrame(index: 4, reason: .noSubject, landmarks: PoseLandmarks()),
            excludedFrame(index: 5, reason: .noSubject, landmarks: PoseLandmarks())
        ]
        try expectEqual(
            BurstProcessor().process(mostlyAbsent, baseline: baseline, captureConfiguration: testCaptureConfiguration).evidence,
            .noEval,
            "minority unassessable frames must not escalate when the subject is mostly absent"
        )

        let majorityUnassessable = [
            excludedFrame(index: 1, reason: .headDropped, landmarks: validLandmarks()),
            excludedFrame(index: 2, reason: .headDropped, landmarks: validLandmarks()),
            excludedFrame(index: 3, reason: .headDropped, landmarks: validLandmarks()),
            timedFrame(index: 4, feature: 0.0),
            timedFrame(index: 5, feature: 0.01)
        ]
        try expectEqual(
            BurstProcessor().process(majorityUnassessable, baseline: baseline, captureConfiguration: testCaptureConfiguration).evidence,
            .worsened,
            "unassessable majority must beat a valid minority"
        )
    }

    TestRegistry.test("only posture-caused exclusions count as abnormal evidence") {
        let abnormal: [FrameExclusionReason] = [.missingShoulder, .croppedUpperBody, .excessiveRotation, .headDropped]
        let technical: [FrameExclusionReason] = [
            .unstableCapture, .noSubject, .ambiguousSubject, .missingHeadAnchor, .modelFailure,
            .invalidROIGeometry, .insufficientDepthPixels, .insufficientDepthRange
        ]
        for reason in abnormal {
            try expect(reason.isSubjectUnassessable, "\(reason.rawValue) must be abnormal evidence")
        }
        for reason in technical {
            try expect(!reason.isSubjectUnassessable, "\(reason.rawValue) must stay no-eval (not posture-caused)")
        }

        let baselines = [
            ("normal", Baseline(center: -1.21, dispersion: 0.04, burstCount: 1, captureConfiguration: testCaptureConfiguration)),
            ("abnormal", Baseline(center: 0.47, dispersion: 0.04, burstCount: 1, captureConfiguration: testCaptureConfiguration))
        ]
        for (baselineName, baseline) in baselines {
            for reason in abnormal {
                let frames = (1...5).map { excludedFrame(index: $0, reason: reason, landmarks: validLandmarks()) }
                try expectEqual(
                    BurstProcessor().process(frames, baseline: baseline, captureConfiguration: testCaptureConfiguration).evidence,
                    .worsened,
                    "\(baselineName) baseline: \(reason.rawValue) must be abnormal"
                )
            }
            for reason in technical {
                let hasNoReliableHead = reason == .noSubject || reason == .ambiguousSubject || reason == .missingHeadAnchor
                let landmarks = hasNoReliableHead ? PoseLandmarks() : validLandmarks()
                let frames = (1...5).map { excludedFrame(index: $0, reason: reason, landmarks: landmarks) }
                try expectEqual(
                    BurstProcessor().process(frames, baseline: baseline, captureConfiguration: testCaptureConfiguration).evidence,
                    .noEval,
                    "\(baselineName) baseline: \(reason.rawValue) must stay no-eval"
                )
            }
        }
    }

    TestRegistry.test("analyzer gate boundaries follow tuning values") {
        let analyzer = PostureFrameAnalyzer()
        let map = depthMap { x, y in Double(y) + Double(x) * 0.2 }
        var atThreshold = validLandmarks()
        atThreshold.leftShoulder?.confidence = Tuning.minimumAssessableShoulderConfidence
        atThreshold.rightShoulder?.confidence = Tuning.minimumAssessableShoulderConfidence
        try expect(analyzer.analyze(landmarks: atThreshold, depthMap: map).isValid, "shoulder confidence at the threshold must pass")

        var nearGapLimit = validLandmarks()
        // anchor 중앙값 gap ≈ 0.92 (> 0.90) — 임계 바로 위는 통과해야 한다.
        for keyPath in [\PoseLandmarks.nose, \PoseLandmarks.leftEye, \PoseLandmarks.rightEye, \PoseLandmarks.leftEar, \PoseLandmarks.rightEar] {
            nearGapLimit[keyPath: keyPath]?.y = 0.472
        }
        try expect(analyzer.analyze(landmarks: nearGapLimit, depthMap: map).isValid, "gap just above the limit must pass")

        var belowGapLimit = nearGapLimit
        // anchor 중앙값 gap ≈ 0.88 (< 0.90) — 임계 바로 아래는 headDropped다.
        for keyPath in [\PoseLandmarks.nose, \PoseLandmarks.leftEye, \PoseLandmarks.rightEye, \PoseLandmarks.leftEar, \PoseLandmarks.rightEar] {
            belowGapLimit[keyPath: keyPath]?.y = 0.488
        }
        try expectEqual(analyzer.analyze(landmarks: belowGapLimit, depthMap: map).exclusionReason, .headDropped, "gap just below the limit must be excluded")
    }

    TestRegistry.test("distant background person is not a subject") {
        var selector = UpperBodySubjectSelector()
        func tinyPerson() -> PoseLandmarks {
            func point(_ x: Double, _ y: Double) -> Point2D { Point2D(x: x, y: y, confidence: 0.9) }
            return PoseLandmarks(
                nose: point(0.8, 0.40),
                leftEye: point(0.79, 0.39),
                rightEye: point(0.81, 0.39),
                leftShoulder: point(0.77, 0.46),
                rightShoulder: point(0.83, 0.46)
            )
        }
        try expectEqual(selector.select(from: [tinyPerson()]), .rejected(.noSubject), "far person below subject scale must stay no-subject")
    }

    TestRegistry.test("framing change since calibration requires recalibration instead of judgment") {
        // 사용자 구도(리드 각도·착석 거리)가 바뀌면 판정은 무의미하다 — 당연히 재보정으로 안내한다.
        let baseline = Baseline(
            center: 0,
            dispersion: 0.02,
            burstCount: 1,
            captureConfiguration: testCaptureConfiguration,
            shoulderMidY: 0.88,
            shoulderWidth: 0.37
        )
        func burst(midY: Double, width: Double) -> [TimedFrame] {
            (1...5).map { anchoredFrame(index: $0, feature: 0.01, shoulderMidY: midY, shoulderWidth: width) }
        }
        let sameFraming = BurstProcessor().process(burst(midY: 0.885, width: 0.372), baseline: baseline, captureConfiguration: testCaptureConfiguration)
        try expectEqual(sameFraming.evidence, .normal, "same framing keeps the baseline comparison")

        let movedCamera = BurstProcessor().process(burst(midY: 0.81, width: 0.37), baseline: baseline, captureConfiguration: testCaptureConfiguration)
        try expectEqual(movedCamera.reason, "framing changed", "shoulder position shift means the framing changed")
        try expectEqual(movedCamera.evidence, .noEval, "changed framing must not be judged against the stale baseline")
        try expect(movedCamera.requiresCalibration, "framing change must guide recalibration")

        let movedSeat = BurstProcessor().process(burst(midY: 0.88, width: 0.32), baseline: baseline, captureConfiguration: testCaptureConfiguration)
        try expectEqual(movedSeat.reason, "framing changed", "shoulder width shift beyond tolerance means the seat or lid moved")

        // 구도 anchor가 없는 baseline(보정 표본에 landmark 정보가 없던 경우)은 기존 비교를 유지한다.
        let anchorless = Baseline(center: 0, dispersion: 0.02, burstCount: 1, captureConfiguration: testCaptureConfiguration)
        try expectEqual(
            BurstProcessor().process(burst(midY: 0.81, width: 0.32), baseline: anchorless, captureConfiguration: testCaptureConfiguration).evidence,
            .normal,
            "anchorless baseline skips the framing gate"
        )
    }

    TestRegistry.test("calibration stores the framing anchor with the baseline") {
        let summaries = (0..<Tuning.requiredCalibrationBursts).map { _ in
            BurstSummary(
                totalFrameCount: 5,
                validFrameCount: 5,
                medianFeature: -0.3,
                featureMAD: 0.02,
                exclusionCounts: [:],
                medianShoulderMidY: 0.88,
                medianShoulderWidth: 0.37
            )
        }
        guard case .accepted(let baseline) = Calibrator().capture(from: summaries, captureConfiguration: testCaptureConfiguration) else {
            throw testFailure("anchored calibration rejected")
        }
        try expectEqual(baseline.shoulderMidY, 0.88, "baseline must keep the calibration shoulder midY")
        try expectEqual(baseline.shoulderWidth, 0.37, "baseline must keep the calibration shoulder width")
    }

    TestRegistry.test("calibration distinguishes unassessable posture from weak signal") {
        let chinPropSummary = BurstSummary(
            totalFrameCount: 5,
            validFrameCount: 0,
            medianFeature: nil,
            featureMAD: nil,
            exclusionCounts: [.missingShoulder: 3, .headDropped: 2]
        )
        try expectEqual(
            Calibrator().capture(from: [chinPropSummary], captureConfiguration: testCaptureConfiguration),
            .rejected(.postureUnassessable),
            "posture-caused calibration failure must guide the user to fix posture"
        )
        let partiallyMeasurableChinProp = BurstSummary(
            totalFrameCount: 5,
            validFrameCount: 2,
            medianFeature: 0.1,
            featureMAD: 0.02,
            exclusionCounts: [.missingShoulder: 3]
        )
        try expectEqual(
            Calibrator().capture(from: [partiallyMeasurableChinProp], captureConfiguration: testCaptureConfiguration),
            .rejected(.postureUnassessable),
            "a measurable minority must not turn a mostly unassessable posture into a baseline"
        )
        let emptySummary = BurstSummary(
            totalFrameCount: 5,
            validFrameCount: 0,
            medianFeature: nil,
            featureMAD: nil,
            exclusionCounts: [.noSubject: 5]
        )
        try expectEqual(
            Calibrator().capture(from: [emptySummary], captureConfiguration: testCaptureConfiguration),
            .rejected(.noReliableBursts),
            "absent subject keeps the generic weak-signal reason"
        )
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

// 실측 비율 기반 fixture: (어깨midY − 신뢰 head anchor 중앙값 y)/어깨폭 ≈ 1.05 — 정상 실측(최소 0.945) 범위.
private func validLandmarks(centerX: Double = 0.5, shoulderWidth: Double = 0.4) -> PoseLandmarks {
    func point(_ x: Double, _ y: Double) -> Point2D { Point2D(x: x, y: y, confidence: 0.95) }
    return PoseLandmarks(
        nose: point(centerX, 0.42),
        leftEye: point(centerX - 0.03, 0.40),
        rightEye: point(centerX + 0.03, 0.40),
        leftEar: point(centerX - 0.07, 0.43),
        rightEar: point(centerX + 0.07, 0.43),
        neck: point(centerX, 0.62),
        leftShoulder: point(centerX - shoulderWidth / 2, 0.84),
        rightShoulder: point(centerX + shoulderWidth / 2, 0.84)
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

private func excludedFrame(index: Int, reason: FrameExclusionReason, landmarks: PoseLandmarks) -> TimedFrame {
    TimedFrame(time: Double(index) * 0.4, analysis: FrameAnalysis(landmarks: landmarks, exclusionReason: reason), index: index)
}

private func anchoredFrame(index: Int, feature: Double, shoulderMidY: Double, shoulderWidth: Double) -> TimedFrame {
    var landmarks = validLandmarks(shoulderWidth: shoulderWidth)
    landmarks.leftShoulder?.y = shoulderMidY
    landmarks.rightShoulder?.y = shoulderMidY
    return TimedFrame(time: Double(index) * 0.4, analysis: FrameAnalysis(landmarks: landmarks, feature: feature), index: index)
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
