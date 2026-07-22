import AVFoundation
import Foundation
import TurtleCore

func registerProductTests() {
    TestRegistry.test("settings enforce minimum 15 second sessions and round-trip") {
        var settings = Settings.defaults
        settings.checkIntervalSeconds = 1
        settings.debugEnabled = true
        try expectEqual(settings.checkIntervalSeconds, 15, "minimum interval")
        let decoded = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))
        try expectEqual(decoded, settings, "settings round trip")
    }

    TestRegistry.test("legacy algorithms and baselines are not reused") {
        let json = """
        {"storedCheckIntervalSeconds":10,"postureAlgorithm":"bodyFrame3D","sensitivity":"medium","bannerNotificationsEnabled":false,"notificationSoundEnabled":false,"launchAtLogin":false,"baseline":{"profileAngle":70}}
        """
        let settings = try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
        try expectEqual(settings.checkIntervalSeconds, 15, "legacy interval clamp")
        try expectEqual(settings.baseline, nil, "incompatible baseline must require calibration")
    }

    TestRegistry.test("baselines from older feature definitions require recalibration") {
        // featureVersion 필드가 없던 구 torso ROI 기하의 baseline은 새 feature와 비교 불가하다.
        let legacy = """
        {"storedCheckIntervalSeconds":60,"bannerNotificationsEnabled":false,"notificationSoundEnabled":false,"launchAtLogin":false,"baseline":{"center":-0.9,"dispersion":0.05,"burstCount":1,"createdAt":0,"captureConfiguration":{"cameraUniqueID":"cam","width":640,"height":480,"orientation":"up-unmirrored"}}}
        """
        let decoded = try JSONDecoder().decode(Settings.self, from: Data(legacy.utf8))
        try expectEqual(decoded.baseline, nil, "version-less baseline must be dropped")

        var current = Settings.defaults
        current.baseline = Baseline(center: -0.3, dispersion: 0.02, burstCount: 1, captureConfiguration: testCaptureConfiguration)
        let roundTrip = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(current))
        try expectEqual(roundTrip.baseline, current.baseline, "current-version baseline must survive")
    }

    TestRegistry.test("camera burst contract is warmup plus at most five frames") {
        try expectEqual(CameraBurstTiming.collectionTime(elapsed: CameraBurstTiming.warmupSeconds - 0.01), nil, "warmup discarded")
        try expectApprox(try unwrap(CameraBurstTiming.collectionTime(elapsed: CameraBurstTiming.warmupSeconds + 0.2), "collection time"), 0.2, "collection starts after warmup")
        try expectEqual(CameraBurstTiming.maximumAnalysisFrames, 5, "maximum frame count")
        try expect(CameraBurstTiming.maximumAnalysisFrames >= Tuning.minimumValidFrames, "minimum valid frames must fit burst")
    }

    TestRegistry.test("next regular check is measured from the previous capture start") {
        let startedAt = Date(timeIntervalSince1970: 100)
        try expectEqual(
            CameraBurstTiming.remainingCheckDelay(
                configuredSeconds: 60,
                startedAt: startedAt,
                now: Date(timeIntervalSince1970: 105.2)
            ),
            55,
            "capture processing time must be subtracted from the configured interval"
        )
        try expectEqual(
            CameraBurstTiming.remainingCheckDelay(
                configuredSeconds: 60,
                startedAt: startedAt,
                now: Date(timeIntervalSince1970: 161)
            ),
            0,
            "an overdue regular check should run immediately"
        )
    }

    TestRegistry.test("camera quality rejects black exposure frames") {
        let black = CameraFrameQuality.isUsableSampleGrid(width: 640, height: 480) { _, _ in 0 }
        let visible = CameraFrameQuality.isUsableSampleGrid(width: 640, height: 480) { x, _ in x > 320 ? 80 : 20 }
        try expect(!black, "black warmup frame must be excluded")
        try expect(visible, "visible frame must pass exposure gate")
    }

    TestRegistry.test("camera authorization separates request start and block") {
        try expectEqual(CameraManager.authorizationAction(for: .authorized), .start, "authorized")
        try expectEqual(CameraManager.authorizationAction(for: .notDetermined), .requestAccess, "request")
        try expectEqual(CameraManager.authorizationAction(for: .denied), .blocked("camera permission denied"), "denied")
    }

    TestRegistry.test("camera burst with no delivered frames is unavailable") {
        try expectEqual(
            CameraManager.burstCompletionAction(receivedFrameCount: 0),
            .blocked("camera unavailable"),
            "zero delivered frames must report an unavailable camera"
        )
        try expectEqual(
            CameraManager.burstCompletionAction(receivedFrameCount: 1),
            .process,
            "a delivered frame must continue through posture processing"
        )
    }

    TestRegistry.test("notification policy only sends rate-limited bad transitions") {
        var policy = NotificationPolicy(minimumInterval: 60)
        try expect(policy.shouldSend(alert: .cautionStarted, at: Date(timeIntervalSince1970: 100)), "first caution")
        try expect(!policy.shouldSend(alert: .cautionStarted, at: Date(timeIntervalSince1970: 130)), "rate limit")
        try expect(!policy.shouldSend(alert: .recovered, at: Date(timeIntervalSince1970: 200)), "no recovery notification")
    }

    TestRegistry.test("baseline and local stats persist") {
        let baseline = Baseline(center: 0.2, dispersion: 0.03, burstCount: 3, createdAt: Date(timeIntervalSince1970: 1), captureConfiguration: testCaptureConfiguration)
        try expectEqual(try JSONDecoder().decode(Baseline.self, from: JSONEncoder().encode(baseline)), baseline, "baseline round trip")
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("turtlemeck-stats-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = StatsStore(fileURL: url)
        var stats = DailyPostureStats(day: "2026-07-20")
        stats.record(.cautionStarted)
        stats.recordDuration(state: .bad, seconds: 10)
        try store.save([stats])
        try expectEqual(try store.load(), [stats], "stats round trip")
    }

    TestRegistry.test("missing Core ML model fails closed") {
        let provider = CoreMLRelativeDepthProvider(modelName: "MissingModelForTest")
        try expect(!provider.prewarm(), "missing model must fail")
        try expect(provider.isModelLoadResolved, "failure state must be resolved")
    }

    TestRegistry.test("local AI output stays in matching timestamp directory") {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent("turtlemeck-local-\(UUID().uuidString)", isDirectory: true)
        let common = root.appendingPathComponent("20260720-230451", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: common, withIntermediateDirectories: true)
        try Data([1]).write(to: common.appendingPathComponent("capture-1.png"))
        try Data([2]).write(to: common.appendingPathComponent("depth-1.png"))
        try Data([3]).write(to: common.appendingPathComponent("capture-2.png"))
        try Data([4]).write(to: common.appendingPathComponent("depth-3.png"))

        let runner = LocalAIAnalysisRunner(environment: ["TURTLEMECK_LOCAL_AI_EXECUTABLE": "/bin/cat"])
        try expect(runner.isEnabled, "runner configuration")
        runner.run(commonSessionPath: common.path)
        let local = root.appendingPathComponent("20260720-230451-local", isDirectory: true)
        let request = try String(contentsOf: local.appendingPathComponent("request.md"), encoding: .utf8)
        let analysis = try String(contentsOf: local.appendingPathComponent("analysis.md"), encoding: .utf8)
        try expect(request.contains("relative inverse depth"), "request must describe relative depth")
        try expect(!request.contains("capture-2.png") && !request.contains("depth-3.png"), "only matching RGB-depth pairs are sent")
        try expectEqual(analysis, request, "configured CLI stdout becomes analysis")
    }
}
