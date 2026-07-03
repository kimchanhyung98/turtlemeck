import Foundation

func registerStateTests() {
    TestRegistry.test("burst processor marks sustained bad frames bad") {
        let frames = stride(from: 0.0, through: 2.0, by: 0.4).map {
            TimedFrame(time: $0, frame: AnalyzedFrame(assessment: .bad))
        }
        let verdict = BurstProcessor(sustainSeconds: 1.6).process(frames)
        try expectEqual(verdict.assessment, .bad, "sustained bad burst")
    }

    TestRegistry.test("burst processor ignores short bad spikes") {
        let frames = [
            TimedFrame(time: 0.0, frame: AnalyzedFrame(assessment: .bad)),
            TimedFrame(time: 0.4, frame: AnalyzedFrame(assessment: .good)),
            TimedFrame(time: 0.8, frame: AnalyzedFrame(assessment: .bad))
        ]
        let verdict = BurstProcessor(sustainSeconds: 1.6).process(frames)
        try expectEqual(verdict.assessment, .good, "short spikes should not warn")
    }

    TestRegistry.test("burst processor returns no-eval when too few valid frames") {
        let frames = [TimedFrame(time: 0, frame: AnalyzedFrame(assessment: .noEval))]
        let verdict = BurstProcessor(minimumValidFrames: 2).process(frames)
        try expectEqual(verdict.assessment, .noEval, "insufficient valid frames")
    }

    TestRegistry.test("burst processor breaks sustained bad evidence on no-eval gaps") {
        let frames = [
            TimedFrame(time: 0.0, frame: AnalyzedFrame(assessment: .bad)),
            TimedFrame(time: 1.0, frame: AnalyzedFrame(assessment: .noEval)),
            TimedFrame(time: 2.0, frame: AnalyzedFrame(assessment: .bad))
        ]
        let verdict = BurstProcessor(sustainSeconds: 1.6, minimumValidFrames: 2).process(frames)
        try expectEqual(verdict.assessment, .good, "no-eval gap should break continuous bad evidence")
    }

    TestRegistry.test("burst processor preserves sparse high-confidence depth bad evidence") {
        let frames = [
            TimedFrame(time: 0.0, frame: AnalyzedFrame(assessment: .noEval)),
            TimedFrame(time: 0.4, frame: AnalyzedFrame(assessment: .bad, signal: PostureSignal(kind: .depth3D, angleDegrees: 0.12, confidence: 0.7))),
            TimedFrame(time: 0.8, frame: AnalyzedFrame(assessment: .noEval)),
            TimedFrame(time: 1.2, frame: AnalyzedFrame(assessment: .noEval))
        ]
        let verdict = BurstProcessor().process(frames)
        try expectEqual(verdict.assessment, .bad, "one high-confidence ML depth bad frame should count as sparse bad evidence")
    }

    TestRegistry.test("state machine requires two bad bursts before caution") {
        var machine = PostureStateMachine(requiredBadBursts: 2)
        let first = machine.apply(BurstVerdict(assessment: .bad))
        let second = machine.apply(BurstVerdict(assessment: .bad))
        try expectEqual(first.state, .good, "first bad burst should not switch")
        try expectEqual(second.state, .bad, "second bad burst switches")
        try expectEqual(second.alert, .cautionStarted, "alert starts once")
    }

    TestRegistry.test("state machine recovers after good burst") {
        var machine = PostureStateMachine(requiredBadBursts: 2)
        _ = machine.apply(BurstVerdict(assessment: .bad))
        _ = machine.apply(BurstVerdict(assessment: .bad))
        let recovered = machine.apply(BurstVerdict(assessment: .good))
        try expectEqual(recovered.state, .good, "good burst recovers")
        try expectEqual(recovered.alert, .recovered, "recovery event")
    }

    TestRegistry.test("state machine preserves bad streak across no-eval") {
        var machine = PostureStateMachine(requiredBadBursts: 2)
        _ = machine.apply(BurstVerdict(assessment: .bad))
        let noEval = machine.apply(BurstVerdict(assessment: .noEval))
        let second = machine.apply(BurstVerdict(assessment: .bad))
        try expectEqual(noEval.state, .noEval, "no-eval shown")
        try expectEqual(second.state, .bad, "bad streak preserved")
    }

    TestRegistry.test("state machine requests calibration after three no-eval bursts") {
        var machine = PostureStateMachine(requiredNoEvalBursts: 3)
        let first = machine.apply(BurstVerdict(assessment: .noEval))
        let second = machine.apply(BurstVerdict(assessment: .noEval))
        let third = machine.apply(BurstVerdict(assessment: .noEval))
        try expectEqual(first.state, .noEval, "first no-eval should not switch")
        try expectEqual(second.state, .noEval, "second no-eval should not switch")
        try expectEqual(third.state, .needsCalibration, "third no-eval should request calibration")
    }

    TestRegistry.test("state machine resets no-eval streak after good burst") {
        var machine = PostureStateMachine(requiredNoEvalBursts: 3)
        _ = machine.apply(BurstVerdict(assessment: .noEval))
        _ = machine.apply(BurstVerdict(assessment: .noEval))
        _ = machine.apply(BurstVerdict(assessment: .good))
        let firstAfterGood = machine.apply(BurstVerdict(assessment: .noEval))
        try expectEqual(firstAfterGood.state, .noEval, "good burst should reset no-eval streak")
    }

    TestRegistry.test("notification policy rate limits caution alerts") {
        var policy = NotificationPolicy(minimumInterval: 60)
        try expect(policy.shouldSend(alert: .cautionStarted, at: Date(timeIntervalSince1970: 100)), "first alert allowed")
        try expect(!policy.shouldSend(alert: .cautionStarted, at: Date(timeIntervalSince1970: 130)), "second alert rate-limited")
        try expect(policy.shouldSend(alert: .cautionStarted, at: Date(timeIntervalSince1970: 161)), "later alert allowed")
    }

    TestRegistry.test("notification policy does not send recovery banners") {
        var policy = NotificationPolicy(minimumInterval: 60)
        try expect(!policy.shouldSend(alert: .recovered, at: Date(timeIntervalSince1970: 100)), "recovery is status-only")
    }

    TestRegistry.test("notification policy suppresses alerts during snooze") {
        var policy = NotificationPolicy(minimumInterval: 60)
        policy.snooze(until: Date(timeIntervalSince1970: 200))
        try expect(!policy.shouldSend(alert: .cautionStarted, at: Date(timeIntervalSince1970: 120)), "snooze should suppress caution")
        try expect(policy.shouldSend(alert: .cautionStarted, at: Date(timeIntervalSince1970: 201)), "caution resumes after snooze")
    }

    TestRegistry.test("posture reminder messages rotate") {
        var messages = PostureReminderMessages()
        let first = messages.nextBody()
        let second = messages.nextBody()
        try expect(first != second, "consecutive reminders should vary")
        try expect(!first.isEmpty && !second.isEmpty, "reminder messages should be non-empty")
    }

    TestRegistry.test("posture pipeline smooths profile angle within a burst") {
        let pipeline = PosturePipeline(stableViewpointFrames: 1, signalFilterAlpha: 0.8)
        var profileSettings = Settings.defaults
        profileSettings.postureAlgorithm = .profileGeometry
        let upright = PoseLandmarks(
            rightEar: confident(0.56, 0.28),
            rightShoulder: confident(0.54, 0.78),
            faceYawDegrees: 72
        )
        let forward = PoseLandmarks(
            rightEar: confident(0.87, 0.47),
            rightShoulder: confident(0.52, 0.78),
            faceYawDegrees: 74
        )
        _ = pipeline.process(upright, settings: profileSettings, baseline: nil)
        let smoothed = pipeline.process(forward, settings: profileSettings, baseline: nil)
        try expectEqual(smoothed.assessment, .good, "first sudden bad frame should be smoothed")
        try expect((smoothed.signal?.angleDegrees ?? 0) > Tuning.mediumAbsoluteBadAngle, "smoothed angle should stay above bad threshold")
    }

    TestRegistry.test("posture pipeline reset clears signal smoothing") {
        let pipeline = PosturePipeline(stableViewpointFrames: 1, signalFilterAlpha: 0.8)
        var profileSettings = Settings.defaults
        profileSettings.postureAlgorithm = .profileGeometry
        let upright = PoseLandmarks(
            rightEar: confident(0.56, 0.28),
            rightShoulder: confident(0.54, 0.78),
            faceYawDegrees: 72
        )
        let forward = PoseLandmarks(
            rightEar: confident(0.87, 0.47),
            rightShoulder: confident(0.52, 0.78),
            faceYawDegrees: 74
        )
        _ = pipeline.process(upright, settings: profileSettings, baseline: nil)
        pipeline.reset()
        let unsmoothed = pipeline.process(forward, settings: profileSettings, baseline: nil)
        try expectEqual(unsmoothed.assessment, .bad, "new burst should not retain previous smoothing")
    }

    TestRegistry.test("posture pipeline resets smoothing when algorithm changes") {
        let pipeline = PosturePipeline(stableViewpointFrames: 1, signalFilterAlpha: 0.8)
        var initialSettings = Settings.defaults
        initialSettings.postureAlgorithm = .fusion
        var switchedSettings = Settings.defaults
        switchedSettings.postureAlgorithm = .profileGeometry
        let upright = PoseLandmarks(
            rightEar: confident(0.56, 0.28),
            rightShoulder: confident(0.54, 0.78),
            faceYawDegrees: 72
        )
        let forward = PoseLandmarks(
            rightEar: confident(0.87, 0.47),
            rightShoulder: confident(0.52, 0.78),
            faceYawDegrees: 74
        )
        _ = pipeline.process(upright, settings: initialSettings, baseline: nil)
        let switched = pipeline.process(forward, settings: switchedSettings, baseline: nil)
        try expectEqual(switched.assessment, .bad, "algorithm change should clear previous smoothing")
        try expectEqual(switched.signal?.kind, .profile2D, "profile geometry should emit profile signal kind")
    }

    TestRegistry.test("posture pipeline requires sustained viewpoint before flipping") {
        let pipeline = PosturePipeline(stableViewpointFrames: 3, signalFilterAlpha: 0)
        let rightProfile = PoseLandmarks(
            rightEar: confident(0.58, 0.28),
            rightShoulder: confident(0.62, 0.75),
            faceYawDegrees: 72
        )
        let leftProfile = PoseLandmarks(
            leftEar: confident(0.42, 0.28),
            leftShoulder: confident(0.38, 0.75),
            faceYawDegrees: -72
        )
        _ = pipeline.process(rightProfile, settings: .defaults, baseline: nil)
        let firstFlip = pipeline.process(leftProfile, settings: .defaults, baseline: nil)
        _ = pipeline.process(leftProfile, settings: .defaults, baseline: nil)
        let sustainedFlip = pipeline.process(leftProfile, settings: .defaults, baseline: nil)
        try expectEqual(firstFlip.viewpoint?.band, .profileRight, "single-frame flip should keep previous viewpoint")
        try expectEqual(sustainedFlip.viewpoint?.band, .profileLeft, "sustained flip should update viewpoint")
    }

    TestRegistry.test("camera burst timing throttles dense camera frames") {
        let denseTimes = stride(from: 0.0, through: CameraBurstTiming.collectionSeconds, by: 1.0 / 30.0)
        var sampled: [Double] = []
        for time in denseTimes where CameraBurstTiming.shouldSample(collectionTime: time, after: sampled.last) {
            sampled.append(time)
            if sampled.count == CameraBurstTiming.maximumAnalysisFrames {
                break
            }
        }

        try expectEqual(sampled.count, CameraBurstTiming.maximumAnalysisFrames, "dense camera should still fill the burst")
        let span = (sampled.last ?? 0) - (sampled.first ?? 0)
        try expect(span >= 1.8, "sampled frames should span the burst window instead of clustering")
    }

    TestRegistry.test("camera frame quality rejects black warmup frames") {
        let black = CameraFrameQuality.isUsableSampleGrid(width: 640, height: 480) { _, _ in 0 }
        let normal = CameraFrameQuality.isUsableSampleGrid(width: 640, height: 480) { x, _ in
            x > 320 ? 80 : 20
        }
        try expect(!black, "black camera warmup frame should be skipped")
        try expect(normal, "visible camera frame should be accepted")
    }

    TestRegistry.test("disclaimer states wellness and debug capture privacy") {
        try expect(Disclaimer.text.contains("의료기기가 아니며"), "medical disclaimer")
        try expect(Disclaimer.text.contains("영상은 전송·공유되지 않습니다"), "video transmission disclaimer")
        try expect(Disclaimer.text.contains("디버그 모드"), "debug capture storage disclaimer")
    }
}
