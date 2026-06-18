import Foundation

func registerStorageTests() {
    TestRegistry.test("settings defaults match requirement") {
        let settings = Settings.defaults
        try expectEqual(settings.checkIntervalSeconds, 60, "default interval")
        try expectEqual(settings.sensitivity, .medium, "default sensitivity")
        try expectEqual(settings.cameraPlacement, .center, "default camera placement")
        try expect(!settings.bannerNotificationsEnabled, "banner notifications default off")
        try expect(!settings.launchAtLogin, "launch at login default off")
    }

    TestRegistry.test("settings clamp interval to 10 through 180 seconds") {
        var low = Settings.defaults
        low.checkIntervalSeconds = 1
        try expectEqual(low.checkIntervalSeconds, 10, "low clamp")
        var high = Settings.defaults
        high.checkIntervalSeconds = 400
        try expectEqual(high.checkIntervalSeconds, 180, "high clamp")
    }

    TestRegistry.test("sensitivity descriptions explain alert tradeoff") {
        try expect(Sensitivity.low.description.contains("알림 적음"), "low sensitivity should explain fewer alerts")
        try expect(Sensitivity.medium.description.contains("균형"), "medium sensitivity should explain balanced behavior")
        try expect(Sensitivity.high.description.contains("일찍"), "high sensitivity should explain early alerts")
    }

    TestRegistry.test("baseline codable round-trips") {
        let baseline = Baseline(profileAngle: 71.5, frontHeadDropRatio: 0.12, threeQuarterAngle: 64)
        let data = try JSONEncoder().encode(baseline)
        let decoded = try JSONDecoder().decode(Baseline.self, from: data)
        try expectEqual(decoded, baseline, "baseline json round trip")
    }

    TestRegistry.test("daily stats accumulate local numeric events only") {
        var stats = DailyPostureStats(day: "2026-06-18")
        stats.record(.cautionStarted)
        stats.record(.cautionStarted)
        stats.record(.recovered)
        stats.recordNotificationSent()
        stats.recordDuration(state: .good, seconds: 120)
        stats.recordDuration(state: .bad, seconds: 90)
        stats.recordDuration(state: .noEval, seconds: 30)
        try expectEqual(stats.cautionTransitions, 2, "caution count")
        try expectEqual(stats.recoveries, 1, "recovery count")
        try expectEqual(stats.notificationsSent, 1, "notification count")
        try expectEqual(stats.goodSeconds, 120, "good duration")
        try expectEqual(stats.badSeconds, 90, "bad duration")
    }

    TestRegistry.test("stats store writes and reads JSON") {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("turtlemeck-stats-\(UUID().uuidString).json")
        let store = StatsStore(fileURL: url)
        var stats = DailyPostureStats(day: "2026-06-18")
        stats.record(.cautionStarted)
        try store.save([stats])
        let loaded = try store.load()
        try expectEqual(loaded, [stats], "stats json round trip")
        try? FileManager.default.removeItem(at: url)
    }
}
