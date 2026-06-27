import Foundation

func registerRoutingTests() {
    // MARK: ViewpointRouter — band → 자동 선택 방식

    TestRegistry.test("router keeps front on ML auto") {
        try expect(ViewpointRouter().route(.front) == .mlAuto, "front keeps ML auto so 3D can fall back when 2D anchors are unavailable")
    }

    TestRegistry.test("router maps profile to 2D profile geometry") {
        try expect(ViewpointRouter().route(.profileLeft) == .profileGeometry, "profileLeft routes to profileGeometry")
        try expect(ViewpointRouter().route(.profileRight) == .profileGeometry, "profileRight routes to profileGeometry")
    }

    TestRegistry.test("router maps three-quarter to 2D profile geometry") {
        try expect(ViewpointRouter().route(.threeQuarterLeft) == .profileGeometry, "threeQuarterLeft routes to profileGeometry")
        try expect(ViewpointRouter().route(.threeQuarterRight) == .profileGeometry, "threeQuarterRight routes to profileGeometry")
    }

    TestRegistry.test("router returns nil for unknown band") {
        try expect(ViewpointRouter().route(.unknown) == nil, "unknown routes to nil (hold previous)")
    }

    // MARK: ViewpointRouteSelector — 히스테리시스(K=2) + unknown 유지

    TestRegistry.test("selector starts at initial method") {
        let selector = ViewpointRouteSelector(initial: .coreMLRelativeDepth, hysteresis: 2)
        try expectEqual(selector.current, .coreMLRelativeDepth, "starts at initial")
    }

    TestRegistry.test("selector switches only after K consecutive new-viewpoint bursts") {
        var selector = ViewpointRouteSelector(initial: .coreMLRelativeDepth, hysteresis: 2)
        let afterFirst = selector.update(dominantBand: .profileRight)
        try expectEqual(afterFirst, .coreMLRelativeDepth, "first profile burst does not switch")
        let afterSecond = selector.update(dominantBand: .profileRight)
        try expectEqual(afterSecond, .profileGeometry, "second consecutive profile burst switches")
    }

    TestRegistry.test("selector ignores a single-burst flicker") {
        var selector = ViewpointRouteSelector(initial: .coreMLRelativeDepth, hysteresis: 2)
        _ = selector.update(dominantBand: .profileRight)   // pending 1
        let afterBack = selector.update(dominantBand: .front)  // back to current → reset
        try expectEqual(afterBack, .coreMLRelativeDepth, "flicker to profile then back stays")
        let afterProfileAgain = selector.update(dominantBand: .profileRight)
        try expectEqual(afterProfileAgain, .coreMLRelativeDepth, "streak restarted, no switch yet")
    }

    TestRegistry.test("selector holds current method on unknown band and breaks streak") {
        var selector = ViewpointRouteSelector(initial: .coreMLRelativeDepth, hysteresis: 2)
        try expectEqual(selector.update(dominantBand: .unknown), .coreMLRelativeDepth, "unknown holds current")
        _ = selector.update(dominantBand: .profileRight)   // pending 1
        _ = selector.update(dominantBand: .unknown)        // breaks streak
        let afterOneProfile = selector.update(dominantBand: .profileRight)
        try expectEqual(afterOneProfile, .coreMLRelativeDepth, "unknown breaks the streak, single profile no switch")
    }
}
