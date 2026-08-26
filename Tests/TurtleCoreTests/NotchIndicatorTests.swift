import AppKit
import CoreGraphics
import Foundation
@_spi(Testing) import TurtleCore

func registerNotchIndicatorTests() {
    // MARK: R3-POL — posture state → 배지 표시 정책
    // 사용자 결정(2026-08-25): 정상은 아무것도 표시하지 않고, 주의일 때만 노란 경고 아이콘을 애니메이션과 함께 표시한다.

    TestRegistry.test("R3-POL-001 bad shows the caution badge") {
        let appearance = try unwrap(
            NotchIndicatorAppearance.make(for: .bad, accessibility: .default),
            "bad must produce an appearance"
        )
        try expectEqual(appearance.kind, .caution, "kind")
        try expectEqual(appearance.kind.symbolName, "exclamationmark.triangle.fill", "symbol name")
    }

    TestRegistry.test("R3-POL-002 good shows nothing at all") {
        try expect(
            NotchIndicatorAppearance.make(for: .good, accessibility: .default) == nil,
            "정상 자세에서는 노치에 아이콘도 애니메이션도 추가하지 않는다"
        )
    }

    TestRegistry.test("R3-POL-003 calibrating hides the badge") {
        try expect(NotchIndicatorAppearance.make(for: .calibrating, accessibility: .default) == nil, "calibrating must be hidden")
    }

    TestRegistry.test("R3-POL-004 noEval hides the badge") {
        try expect(NotchIndicatorAppearance.make(for: .noEval, accessibility: .default) == nil, "noEval must be hidden")
    }

    TestRegistry.test("R3-POL-005 paused hides the badge") {
        try expect(NotchIndicatorAppearance.make(for: .paused, accessibility: .default) == nil, "paused must be hidden")
    }

    TestRegistry.test("R3-POL-006 blocked hides the badge") {
        try expect(NotchIndicatorAppearance.make(for: .blocked, accessibility: .default) == nil, "blocked must be hidden")
    }

    TestRegistry.test("R3-POL-007 needsCalibration hides the badge") {
        try expect(NotchIndicatorAppearance.make(for: .needsCalibration, accessibility: .default) == nil, "needsCalibration must be hidden")
    }

    TestRegistry.test("R3-POL-008 the caution badge animates in by default") {
        let appearance = try unwrap(NotchIndicatorAppearance.make(for: .bad, accessibility: .default), "bad appearance")
        try expect(appearance.usesEntranceAnimation, "검은 영역이 스르륵 나타나는 등장 애니메이션을 사용한다")
    }

    TestRegistry.test("R3-POL-009 reduce motion drops the entrance animation but keeps the badge") {
        let appearance = try unwrap(
            NotchIndicatorAppearance.make(for: .bad, accessibility: AccessibilityDisplayPreferences(reduceMotion: true)),
            "bad appearance under reduce motion"
        )
        try expectEqual(appearance.kind, .caution, "표시 자체는 유지한다")
        try expect(appearance.usesEntranceAnimation == false, "reduce motion에서는 애니메이션하지 않는다")
    }

    TestRegistry.test("R3-POL-010 contrast and color settings do not change the appearance") {
        for prefs in [
            AccessibilityDisplayPreferences(differentiateWithoutColor: true),
            AccessibilityDisplayPreferences(increaseContrast: true),
            AccessibilityDisplayPreferences(differentiateWithoutColor: true, increaseContrast: true),
        ] {
            try expectEqual(
                NotchIndicatorAppearance.make(for: .bad, accessibility: prefs),
                NotchIndicatorAppearance.make(for: .bad, accessibility: .default),
                "대비·색상 설정은 결과를 바꾸지 않는다"
            )
        }
    }

    TestRegistry.test("R3-POL-011 identical inputs produce identical appearances") {
        let first = NotchIndicatorAppearance.make(for: .bad, accessibility: .default)
        let second = NotchIndicatorAppearance.make(for: .bad, accessibility: .default)
        try expectEqual(first, second, "policy must be deterministic")
    }

    TestRegistry.test("R3-POL-012 the symbol name resolves to a real SF Symbol") {
        let name = NotchIndicatorAppearance.Kind.caution.symbolName
        try expect(
            NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil,
            "SF Symbol \(name) must exist on this macOS"
        )
    }

    // MARK: R6-TRN — 비동기 애니메이션 전환 세대

    TestRegistry.test("R6-TRN-001 rapid alternating states invalidate stale completions per overlay") {
        let firstObject = NSObject()
        let secondObject = NSObject()
        let firstOverlay = ObjectIdentifier(firstObject)
        let secondOverlay = ObjectIdentifier(secondObject)
        var generations = NotchIndicatorTransitionGenerations()

        let firstReveal = generations.begin(for: firstOverlay)
        let otherReveal = generations.begin(for: secondOverlay)
        let firstCollapse = generations.begin(for: firstOverlay)
        let secondReveal = generations.begin(for: firstOverlay)

        try expect(!generations.isCurrent(firstReveal, for: firstOverlay), "취소된 첫 reveal 완료는 무시한다")
        try expect(!generations.isCurrent(firstCollapse, for: firstOverlay), "취소된 collapse 완료는 무시한다")
        try expect(generations.isCurrent(secondReveal, for: firstOverlay), "가장 최근 reveal 완료만 허용한다")
        try expect(generations.isCurrent(otherReveal, for: secondOverlay), "다른 오버레이의 전환은 독립적이다")
    }

    TestRegistry.test("R5-GEO-001 the badge reaches back into the notch to hide the seam") {
        let screen = deviceNotchScreen()
        let right = try unwrap(screen.auxiliaryTopRightArea, "right area")
        let joined = try unwrap(NotchIndicatorLayout.badgeFrame(for: screen), "joined badge")
        let flush = try unwrap(NotchIndicatorLayout.badgeFrame(for: screen, notchOverlap: 0), "flush badge")
        try expect(joined.minX < right.minX, "겹침이 있으면 노치 안쪽에서 시작한다")
        try expectApprox(Double(flush.minX), Double(right.minX), "겹침이 0이면 보조 영역 시작점과 같다")
        try expectApprox(Double(joined.maxX), Double(flush.maxX), "겹침은 오른쪽 끝을 옮기지 않는다")
    }

    TestRegistry.test("R5-GEO-004 a real screen without a notch never produces a badge") {
        // 검증 기기에 연결된 비노치 화면(1920x1080)의 실측값이다.
        // macOS는 카메라 하우징이 없는 화면에 safeAreaInsets.top = 0과 nil 보조 영역을 보고한다.
        let plain = NotchScreenGeometry(
            frame: CGRect(x: -192, y: 1117, width: 1920, height: 1080),
            safeAreaTop: 0,
            auxiliaryTopLeftArea: nil,
            auxiliaryTopRightArea: nil
        )
        try expect(NotchIndicatorLayout.badgeFrame(for: plain) == nil, "노치 없는 화면에는 배지를 만들지 않는다")

        // 두 신호는 각각 단독으로도 표시를 막아야 한다.
        var onlyInsetMissing = deviceNotchScreen()
        onlyInsetMissing.safeAreaTop = 0
        try expect(NotchIndicatorLayout.badgeFrame(for: onlyInsetMissing) == nil, "safe area가 없으면 보조 영역이 있어도 숨긴다")

        var onlyAreasMissing = deviceNotchScreen()
        onlyAreasMissing.auxiliaryTopLeftArea = nil
        onlyAreasMissing.auxiliaryTopRightArea = nil
        try expect(NotchIndicatorLayout.badgeFrame(for: onlyAreasMissing) == nil, "보조 영역이 없으면 safe area가 있어도 숨긴다")
    }

    TestRegistry.test("R5-GEO-005 mixed displays only produce badges for notched screens") {
        let notched = deviceNotchScreen()
        let plain = NotchScreenGeometry(
            frame: CGRect(x: -192, y: 1117, width: 1920, height: 1080),
            safeAreaTop: 0,
            auxiliaryTopLeftArea: nil,
            auxiliaryTopRightArea: nil
        )
        let frames = [notched, plain].compactMap { NotchIndicatorLayout.badgeFrame(for: $0) }
        try expectEqual(frames.count, 1, "노치 화면 하나에만 배지가 생긴다")
        try expectApprox(Double(frames[0].maxX), 996, "배지는 노치 화면 위에 놓인다")
    }

    TestRegistry.test("R5-GEO-002 an overlap that would swallow the notch hides the badge") {
        let screen = standardNotchScreen()
        let left = try unwrap(screen.auxiliaryTopLeftArea, "left area")
        let right = try unwrap(screen.auxiliaryTopRightArea, "right area")
        let notchWidth = right.minX - left.maxX
        try expect(
            NotchIndicatorLayout.badgeFrame(for: screen, notchOverlap: notchWidth) == nil,
            "노치 폭 전체를 덮는 겹침은 허용하지 않는다"
        )
        try expect(
            NotchIndicatorLayout.badgeFrame(for: screen, notchOverlap: notchWidth + 1) == nil,
            "노치보다 넓은 겹침은 허용하지 않는다"
        )
    }

    TestRegistry.test("R5-GEO-003 non-finite or negative overlaps hide the badge") {
        for overlap in [CGFloat(-1), .nan, .infinity] {
            try expect(
                NotchIndicatorLayout.badgeFrame(for: standardNotchScreen(), notchOverlap: overlap) == nil,
                "overlap \(overlap) must hide"
            )
        }
    }

    // MARK: R4-PRV — 디버그 모드 상태 미리보기 (docs/debugging.md, docs/notch.md)

    TestRegistry.test("R4-PRV-001 preview is ignored when debug mode is off") {
        for state in PostureState.allCases {
            try expectEqual(
                NotchIndicatorPreview.effectiveState(actual: .noEval, preview: state, debugEnabled: false),
                .noEval,
                "운영 모드에서는 미리보기 값이 표시를 바꾸지 않는다"
            )
        }
    }

    TestRegistry.test("R4-PRV-002 no preview falls through to the real state") {
        for state in PostureState.allCases {
            try expectEqual(
                NotchIndicatorPreview.effectiveState(actual: state, preview: nil, debugEnabled: true),
                state,
                "미리보기를 고르지 않으면 실제 판정을 그대로 쓴다"
            )
        }
    }

    TestRegistry.test("R4-PRV-003 preview overrides the real state in debug mode") {
        try expectEqual(
            NotchIndicatorPreview.effectiveState(actual: .good, preview: .bad, debugEnabled: true),
            .bad,
            "디버그 모드에서는 미리보기가 우선한다"
        )
        try expectEqual(
            NotchIndicatorPreview.effectiveState(actual: .bad, preview: .good, debugEnabled: true),
            .good,
            "미리보기로 표시를 끌 수도 있어야 한다"
        )
    }

    TestRegistry.test("R4-PRV-004 every state pair resolves without debug mode") {
        for actual in PostureState.allCases {
            for preview in PostureState.allCases {
                try expectEqual(
                    NotchIndicatorPreview.effectiveState(actual: actual, preview: preview, debugEnabled: false),
                    actual,
                    "운영 모드 결과는 항상 실제 판정과 같다"
                )
            }
        }
    }

    TestRegistry.test("R4-PRV-005 the picker can reach all seven posture states") {
        try expectEqual(PostureState.allCases.count, 7, "상태가 늘면 미리보기 목록도 함께 늘어야 한다")
    }

    TestRegistry.test("R4-PRV-006 only the caution state renders under preview") {
        let shown = PostureState.allCases.filter {
            NotchIndicatorAppearance.make(
                for: NotchIndicatorPreview.effectiveState(actual: .noEval, preview: $0, debugEnabled: true),
                accessibility: .default
            ) != nil
        }
        try expectEqual(shown, [.bad], "미리보기에서도 주의만 배지를 그린다. 나머지를 고르면 숨김이 정상이다")
    }

    // MARK: R2-GEO — 합성 화면 기하 → 오른쪽 배지 frame (right-status-badge-plan §6)

    TestRegistry.test("R2-GEO-001 standard screen puts a 32pt badge at the right auxiliary origin") {
        let rect = try unwrap(
            NotchIndicatorLayout.badgeFrame(for: standardNotchScreen(), width: 32),
            "standard screen must produce a badge frame"
        )
        // 물리 노치의 둥근 모서리를 덮도록 왼쪽으로 12pt 파고든다. 노치 오른쪽으로 드러나는 폭은 32pt다.
        try expectRect(rect, equalsX: 834, y: 950, width: 44, height: 32, "R2-GEO-001")
    }

    TestRegistry.test("R2-GEO-002 real device geometry produces the documented badge frame") {
        // 검증 기기(내장 1728x1117, safeTop 32)의 실측치를 합성 입력으로 고정한다.
        let rect = try unwrap(
            NotchIndicatorLayout.badgeFrame(for: deviceNotchScreen()),
            "device geometry must produce a badge frame"
        )
        try expectRect(rect, equalsX: 944, y: 1085, width: 52, height: 32, "R2-GEO-002")
    }

    TestRegistry.test("R2-GEO-003 a 28pt badge keeps the origin and the band height") {
        let screen = deviceNotchScreen()
        let right = try unwrap(screen.auxiliaryTopRightArea, "right area")
        let rect = try unwrap(NotchIndicatorLayout.badgeFrame(for: screen, width: 28), "28pt badge frame")
        try expectRect(rect, equalsX: Double(right.minX) - 12, y: Double(right.minY), width: 40, height: Double(right.height), "R2-GEO-003")
    }

    TestRegistry.test("R2-GEO-004 a missing right auxiliary area hides the badge") {
        var screen = standardNotchScreen()
        screen.auxiliaryTopRightArea = nil
        try expect(NotchIndicatorLayout.badgeFrame(for: screen) == nil, "missing right area must hide")
    }

    TestRegistry.test("R2-GEO-005 a right auxiliary area narrower than the badge hides the badge") {
        var screen = standardNotchScreen()
        // 오른쪽 보조 영역 폭 20pt < 배지 32pt
        screen.auxiliaryTopRightArea = CGRect(x: 1492, y: 950, width: 20, height: 32)
        try expect(NotchIndicatorLayout.badgeFrame(for: screen, width: 32) == nil, "narrow right area must hide")
        let rect = try unwrap(NotchIndicatorLayout.badgeFrame(for: screen, width: 20), "width equal to the area is the inclusive boundary")
        try expectRect(rect, equalsX: 1480, y: 950, width: 32, height: 32, "R2-GEO-005 boundary")
    }

    TestRegistry.test("R2-GEO-006 non-positive or non-finite badge widths hide the badge") {
        for width in [0, -1, CGFloat.nan, CGFloat.infinity] {
            try expect(
                NotchIndicatorLayout.badgeFrame(for: standardNotchScreen(), width: width) == nil,
                "width \(width) must hide"
            )
        }
    }

    TestRegistry.test("R2-GEO-007 a negative screen origin is preserved in the badge frame") {
        let screen = NotchScreenGeometry(
            frame: CGRect(x: -1512, y: 0, width: 1512, height: 982),
            safeAreaTop: 32,
            auxiliaryTopLeftArea: CGRect(x: -1512, y: 950, width: 666, height: 32),
            auxiliaryTopRightArea: CGRect(x: -666, y: 950, width: 666, height: 32)
        )
        let rect = try unwrap(NotchIndicatorLayout.badgeFrame(for: screen), "negative origin badge")
        try expectRect(rect, equalsX: -678, y: 950, width: 52, height: 32, "R2-GEO-007")
    }

    TestRegistry.test("R2-GEO-008 a non-zero screen origin Y is taken from the right auxiliary area") {
        let screen = NotchScreenGeometry(
            frame: CGRect(x: 1512, y: 200, width: 1512, height: 982),
            safeAreaTop: 32,
            auxiliaryTopLeftArea: CGRect(x: 1512, y: 1150, width: 666, height: 32),
            auxiliaryTopRightArea: CGRect(x: 2358, y: 1150, width: 666, height: 32)
        )
        let rect = try unwrap(NotchIndicatorLayout.badgeFrame(for: screen), "offset origin badge")
        try expectRect(rect, equalsX: 2346, y: 1150, width: 52, height: 32, "R2-GEO-008")
    }

    TestRegistry.test("R2-GEO-009 mismatched auxiliary Y bands hide the badge") {
        var screen = standardNotchScreen()
        screen.auxiliaryTopRightArea = CGRect(x: 846, y: 918, width: 666, height: 64)
        try expect(NotchIndicatorLayout.badgeFrame(for: screen) == nil, "mismatched bands must hide")
    }

    TestRegistry.test("R2-GEO-010 a missing or reversed notch gap hides the badge") {
        var zeroGap = standardNotchScreen()
        zeroGap.auxiliaryTopLeftArea = CGRect(x: 0, y: 950, width: 756, height: 32)
        zeroGap.auxiliaryTopRightArea = CGRect(x: 756, y: 950, width: 756, height: 32)
        try expect(NotchIndicatorLayout.badgeFrame(for: zeroGap) == nil, "zero gap must hide")

        var swapped = standardNotchScreen()
        swapped.auxiliaryTopLeftArea = CGRect(x: 846, y: 950, width: 666, height: 32)
        swapped.auxiliaryTopRightArea = CGRect(x: 0, y: 950, width: 666, height: 32)
        try expect(NotchIndicatorLayout.badgeFrame(for: swapped) == nil, "swapped areas must hide")

        var overlapping = standardNotchScreen()
        overlapping.auxiliaryTopLeftArea = CGRect(x: 0, y: 950, width: 700, height: 32)
        overlapping.auxiliaryTopRightArea = CGRect(x: 690, y: 950, width: 822, height: 32)
        try expect(NotchIndicatorLayout.badgeFrame(for: overlapping) == nil, "overlap must hide")
    }

    TestRegistry.test("R2-GEO-011 every produced badge frame stays inside the right auxiliary area") {
        for screen in validNotchScreens() {
            for width in [CGFloat(28), 32] {
                let rect = try unwrap(NotchIndicatorLayout.badgeFrame(for: screen, width: width), "invariant badge")
                let right = try unwrap(screen.auxiliaryTopRightArea, "right area")
                try expect([rect.minX, rect.minY, rect.width, rect.height].allSatisfy(\.isFinite), "frame must be finite")
                try expect(rect.width > 0 && rect.height > 0, "frame must be positive")
                try expect(rect.minX >= screen.frame.minX && rect.maxX <= screen.frame.maxX, "frame must be horizontally inside the screen")
                try expect(rect.minY >= screen.frame.minY && rect.maxY <= screen.frame.maxY, "frame must be vertically inside the screen")
                let left = try unwrap(screen.auxiliaryTopLeftArea, "left area")
                try expectApprox(Double(rect.minX), Double(right.minX) - 12, "frame must reach back into the notch")
                try expect(rect.minX > left.maxX, "frame must not cross into the left auxiliary area")
                try expectApprox(Double(rect.minY), Double(right.minY), "frame must sit on the right area baseline")
                try expectApprox(Double(rect.height), Double(right.height), "frame must fill the band height")
                try expectApprox(Double(rect.maxX), Double(right.minX) + Double(width), "visible width past the notch must be the requested width")
                try expect(rect.maxX <= right.maxX, "frame must end inside the right area")
            }
        }
    }

    TestRegistry.test("R2-GEO-012 per-screen results do not depend on evaluation order") {
        let screens = validNotchScreens()
        let forward = screens.map { NotchIndicatorLayout.badgeFrame(for: $0) }
        let backward = screens.reversed().map { NotchIndicatorLayout.badgeFrame(for: $0) }
        for (index, rect) in forward.enumerated() {
            try expectEqual(rect, backward[screens.count - 1 - index], "screen \(index) result must be order independent")
        }
    }

    TestRegistry.test("R2-GEO-013 a missing left auxiliary area hides the badge") {
        var screen = standardNotchScreen()
        screen.auxiliaryTopLeftArea = nil
        try expect(NotchIndicatorLayout.badgeFrame(for: screen) == nil, "missing left area must hide")
    }

    TestRegistry.test("R2-GEO-014 a non-finite screen frame hides the badge") {
        var nanFrame = standardNotchScreen()
        nanFrame.frame = CGRect(x: CGFloat.nan, y: 0, width: 1512, height: 982)
        try expect(NotchIndicatorLayout.badgeFrame(for: nanFrame) == nil, "NaN frame must hide")

        var infiniteFrame = standardNotchScreen()
        infiniteFrame.frame = CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 982)
        try expect(NotchIndicatorLayout.badgeFrame(for: infiniteFrame) == nil, "infinite frame must hide")
    }

    TestRegistry.test("R2-GEO-015 an absent or degenerate safe area hides the badge") {
        var nanSafe = standardNotchScreen()
        nanSafe.safeAreaTop = .nan
        try expect(NotchIndicatorLayout.badgeFrame(for: nanSafe) == nil, "NaN safe area must hide")

        var zeroSafe = standardNotchScreen()
        zeroSafe.safeAreaTop = 0
        try expect(NotchIndicatorLayout.badgeFrame(for: zeroSafe) == nil, "zero safe area must hide")

        var fullSafe = standardNotchScreen()
        fullSafe.safeAreaTop = 982
        try expect(NotchIndicatorLayout.badgeFrame(for: fullSafe) == nil, "safe area covering the screen must hide")
    }

    TestRegistry.test("R2-GEO-016 an auxiliary area outside the screen hides the badge") {
        var screen = standardNotchScreen()
        screen.auxiliaryTopRightArea = CGRect(x: 846, y: 950, width: 700, height: 32)
        try expect(NotchIndicatorLayout.badgeFrame(for: screen) == nil, "out-of-screen area must hide")
    }

    TestRegistry.test("R2-GEO-017 an auxiliary area detached from the screen top hides the badge") {
        var screen = standardNotchScreen()
        screen.auxiliaryTopRightArea = CGRect(x: 846, y: 940, width: 666, height: 32)
        try expect(NotchIndicatorLayout.badgeFrame(for: screen) == nil, "area detached from the top must hide")
    }

    TestRegistry.test("R2-GEO-018 a zero-height auxiliary area hides the badge") {
        var screen = standardNotchScreen()
        screen.auxiliaryTopRightArea = CGRect(x: 846, y: 982, width: 666, height: 0)
        try expect(NotchIndicatorLayout.badgeFrame(for: screen) == nil, "zero-height area must hide")
    }

    TestRegistry.test("R2-GEO-019 a non-finite auxiliary area hides the badge") {
        var screen = standardNotchScreen()
        screen.auxiliaryTopRightArea = CGRect(x: CGFloat.infinity, y: 950, width: 666, height: 32)
        try expect(NotchIndicatorLayout.badgeFrame(for: screen) == nil, "infinite right area must hide")
    }

    TestRegistry.test("R2-GEO-020 the badge height follows the band, not a 32pt constant") {
        // safeAreaTop과 보조 영역 높이가 32가 아닌 화면에서도 배지는 밴드를 정확히 채워야 한다.
        let screen = tallBandNotchScreen()
        let right = try unwrap(screen.auxiliaryTopRightArea, "right area")
        let rect = try unwrap(NotchIndicatorLayout.badgeFrame(for: screen), "tall band badge")
        try expectRect(rect, equalsX: Double(right.minX) - 12, y: Double(right.minY), width: 52, height: 38, "R2-GEO-020")
        try expect(rect.height != 32, "height must not be hardcoded to the badge width")
    }

    TestRegistry.test("R2-GEO-021 a screen above the main screen uses its own band") {
        let screen = NotchScreenGeometry(
            frame: CGRect(x: 0, y: 982, width: 1512, height: 982),
            safeAreaTop: 32,
            auxiliaryTopLeftArea: CGRect(x: 0, y: 1932, width: 666, height: 32),
            auxiliaryTopRightArea: CGRect(x: 846, y: 1932, width: 666, height: 32)
        )
        let rect = try unwrap(NotchIndicatorLayout.badgeFrame(for: screen), "upper screen badge")
        try expectRect(rect, equalsX: 834, y: 1932, width: 52, height: 32, "R2-GEO-021")
    }
}

/// 실제 하드웨어 치수를 주장하지 않는 합성 기준 화면이다.
private func standardNotchScreen() -> NotchScreenGeometry {
    NotchScreenGeometry(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        safeAreaTop: 32,
        auxiliaryTopLeftArea: CGRect(x: 0, y: 950, width: 666, height: 32),
        auxiliaryTopRightArea: CGRect(x: 846, y: 950, width: 666, height: 32)
    )
}

/// 검증 기기(MacBook Pro 14", 내장 1728×1117)의 실측 기하다.
private func deviceNotchScreen() -> NotchScreenGeometry {
    NotchScreenGeometry(
        frame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
        safeAreaTop: 32,
        auxiliaryTopLeftArea: CGRect(x: 0, y: 1085, width: 771, height: 32),
        auxiliaryTopRightArea: CGRect(x: 956, y: 1085, width: 772, height: 32)
    )
}

/// 상단 밴드가 32pt가 아닌 화면이다. 배지 높이가 상수로 고정되지 않았는지 구분한다.
private func tallBandNotchScreen() -> NotchScreenGeometry {
    NotchScreenGeometry(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        safeAreaTop: 38,
        auxiliaryTopLeftArea: CGRect(x: 0, y: 944, width: 666, height: 38),
        auxiliaryTopRightArea: CGRect(x: 846, y: 944, width: 666, height: 38)
    )
}

private func validNotchScreens() -> [NotchScreenGeometry] {
    [
        standardNotchScreen(),
        deviceNotchScreen(),
        tallBandNotchScreen(),
        NotchScreenGeometry(
            frame: CGRect(x: -1512, y: 0, width: 1512, height: 982),
            safeAreaTop: 32,
            auxiliaryTopLeftArea: CGRect(x: -1512, y: 950, width: 666, height: 32),
            auxiliaryTopRightArea: CGRect(x: -666, y: 950, width: 666, height: 32)
        ),
        NotchScreenGeometry(
            frame: CGRect(x: 1512, y: 200, width: 1512, height: 982),
            safeAreaTop: 32,
            auxiliaryTopLeftArea: CGRect(x: 1512, y: 1150, width: 666, height: 32),
            auxiliaryTopRightArea: CGRect(x: 2358, y: 1150, width: 666, height: 32)
        ),
    ]
}

private func expectRect(
    _ rect: CGRect,
    equalsX x: Double,
    y: Double,
    width: Double,
    height: Double,
    _ message: String,
    file: StaticString = #fileID,
    line: UInt = #line
) throws {
    try expectApprox(Double(rect.minX), x, "\(message) x", file: file, line: line)
    try expectApprox(Double(rect.minY), y, "\(message) y", file: file, line: line)
    try expectApprox(Double(rect.width), width, "\(message) width", file: file, line: line)
    try expectApprox(Double(rect.height), height, "\(message) height", file: file, line: line)
}
