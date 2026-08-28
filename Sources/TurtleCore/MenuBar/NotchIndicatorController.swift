import AppKit
import Combine

/// macOS 접근성 표시 설정의 스냅샷이다.
/// 읽는 위치를 한 군데로 모으고 순수 정책 계산이 `NSWorkspace`에 직접 접근하지 않게 한다.
public struct AccessibilityDisplayPreferences: Equatable, Sendable {
    public var reduceMotion: Bool
    public var differentiateWithoutColor: Bool
    public var increaseContrast: Bool

    public init(reduceMotion: Bool = false, differentiateWithoutColor: Bool = false, increaseContrast: Bool = false) {
        self.reduceMotion = reduceMotion
        self.differentiateWithoutColor = differentiateWithoutColor
        self.increaseContrast = increaseContrast
    }

    public static let `default` = AccessibilityDisplayPreferences()
}

/// 자세 상태를 노치 배지 표시로 바꾸는 순수 정책이다.
/// 실제 시스템 색상 선택과 창 생성은 Adapter가 담당하고, 여기서는 의미(kind)와 등장 방식만 결정한다.
public struct NotchIndicatorAppearance: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case caution

        /// 팝오버의 주의 표현(`MenuView`)과 같은 모양을 쓰도록 맞춘 값이다. 한쪽을 바꾸면 함께 확인한다.
        public var symbolName: String {
            switch self {
            case .caution:
                return "exclamationmark.triangle.fill"
            }
        }
    }

    public var kind: Kind
    /// 검은 영역이 노치에서 펼쳐진 뒤 아이콘이 나타나는 1회성 등장 애니메이션 사용 여부다.
    public var usesEntranceAnimation: Bool

    public init(kind: Kind, usesEntranceAnimation: Bool) {
        self.kind = kind
        self.usesEntranceAnimation = usesEntranceAnimation
    }

    /// `bad`에서만 주의 배지를 표시한다. 정상 자세를 포함한 나머지 상태에서는 아무것도 표시하지 않는다.
    public static func make(
        for postureState: PostureState,
        accessibility: AccessibilityDisplayPreferences
    ) -> NotchIndicatorAppearance? {
        switch postureState {
        case .bad:
            return NotchIndicatorAppearance(
                kind: .caution,
                usesEntranceAnimation: !accessibility.reduceMotion
            )
        case .good, .calibrating, .noEval, .paused, .blocked, .needsCalibration:
            return nil
        }
    }
}

/// 디버그 모드에서 노치가 그릴 자세 상태만 강제로 바꾸는 미리보기 규칙이다.
/// 카메라·자세 판정·통계·알림은 그대로 돌아가고 노치가 그리는 상태만 달라진다.
public enum NotchIndicatorPreview {
    /// 디버그 모드가 아닐 때는 미리보기 값이 남아 있어도 실제 판정을 그대로 쓴다.
    public static func effectiveState(
        actual: PostureState,
        preview: PostureState?,
        debugEnabled: Bool
    ) -> PostureState {
        guard debugEnabled, let preview else { return actual }
        return preview
    }
}

/// 오버레이별 비동기 애니메이션 완료가 여전히 최신 전환에 속하는지 판별한다.
@_spi(Testing)
public struct NotchIndicatorTransitionGenerations {
    private var nextGeneration: UInt = 0
    private var currentByOverlay: [ObjectIdentifier: UInt] = [:]

    public init() {}

    /// 새 전환을 시작하고 해당 오버레이의 이전 완료를 모두 무효화한다.
    public mutating func begin(for overlayID: ObjectIdentifier) -> UInt {
        nextGeneration &+= 1
        currentByOverlay[overlayID] = nextGeneration
        return nextGeneration
    }

    /// 완료가 해당 오버레이에서 가장 최근에 시작한 전환에 속하는지 반환한다.
    public func isCurrent(_ generation: UInt, for overlayID: ObjectIdentifier) -> Bool {
        currentByOverlay[overlayID] == generation
    }

    /// 화면 재구성 전에 기존 오버레이의 모든 완료를 무효화한다.
    public mutating func invalidateAll() {
        currentByOverlay.removeAll(keepingCapacity: true)
    }
}

/// 실제 `NSScreen` 없이 합성 기하를 테스트할 수 있도록 화면 정보를 담는 값 타입이다.
public struct NotchScreenGeometry: Equatable, Sendable {
    public var frame: CGRect
    public var safeAreaTop: CGFloat
    public var auxiliaryTopLeftArea: CGRect?
    public var auxiliaryTopRightArea: CGRect?

    public init(
        frame: CGRect,
        safeAreaTop: CGFloat,
        auxiliaryTopLeftArea: CGRect?,
        auxiliaryTopRightArea: CGRect?
    ) {
        self.frame = frame
        self.safeAreaTop = safeAreaTop
        self.auxiliaryTopLeftArea = auxiliaryTopLeftArea
        self.auxiliaryTopRightArea = auxiliaryTopRightArea
    }
}

/// 노치 좌우 보조 상단 영역에 놓을 배지 frame을 계산하는 순수 좌표 계획이다.
/// 기하가 모호하면 표시하지 않는다(fail closed). 특정 모델·메뉴 막대 높이 상수를 쓰지 않는다.
public enum NotchIndicatorLayout {
    /// 부동소수점 노이즈 허용 오차다. 잘못된 기하를 억지로 화면 안에 맞추는 데 사용하지 않는다.
    private static let epsilon: CGFloat = 1e-3

    /// 물리 노치와 한 덩어리로 보이도록 배지를 노치 쪽으로 파고들게 하는 기본 겹침이다.
    /// 컷아웃의 둥근 모서리 안쪽에 남는 밝은 쐐기를 덮는 용도이며, 이 구간은 노치에 가려 보이지 않는다.
    public static let defaultNotchOverlap: CGFloat = 12

    public static func supportsIndicator(
        on screen: NotchScreenGeometry,
        width: CGFloat = 40
    ) -> Bool {
        badgeFrame(for: screen, side: .left, width: width) != nil
            || badgeFrame(for: screen, side: .right, width: width) != nil
    }

    public static func badgeFrame(
        for screen: NotchScreenGeometry,
        side: NotchIndicatorSide = .right,
        width: CGFloat = 40,
        notchOverlap: CGFloat = NotchIndicatorLayout.defaultNotchOverlap
    ) -> CGRect? {
        let frame = screen.frame
        // 화면 크기와 유한성
        guard frame.width > 0, frame.height > 0,
              frame.minX.isFinite, frame.minY.isFinite,
              frame.width.isFinite, frame.height.isFinite
        else { return nil }

        // 상단 안전 영역
        guard screen.safeAreaTop.isFinite,
              screen.safeAreaTop > 0,
              screen.safeAreaTop < frame.height
        else { return nil }

        // 좌우 보조 상단 영역 존재
        guard let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea
        else { return nil }

        // 보조 영역 크기와 유한성
        for area in [left, right] {
            guard area.minX.isFinite, area.minY.isFinite,
                  area.width.isFinite, area.height.isFinite,
                  area.width > 0, area.height > 0
            else { return nil }
        }

        // 보조 영역이 화면 안에 있음
        for area in [left, right] {
            guard area.minX >= frame.minX - epsilon, area.maxX <= frame.maxX + epsilon,
                  area.minY >= frame.minY - epsilon, area.maxY <= frame.maxY + epsilon
            else { return nil }
        }

        // 두 영역이 화면 상단에 닿아 있고 Y 밴드가 일치해야 노치 양옆 영역으로 본다
        guard abs(left.maxY - frame.maxY) <= epsilon,
              abs(right.maxY - frame.maxY) <= epsilon,
              abs(left.minY - right.minY) <= epsilon,
              abs(left.maxY - right.maxY) <= epsilon
        else { return nil }

        // 왼쪽 → 오른쪽 순서와 양수 간격. 노치가 실제로 존재하는지 확인하는 근거로 유지한다.
        guard left.minX < left.maxX, left.maxX <= right.minX, right.minX < right.maxX
        else { return nil }
        let notchWidth = right.minX - left.maxX
        guard notchWidth > 0, notchWidth < frame.width else { return nil }

        // 노치 바깥으로 드러나는 폭은 선택한 보조 영역 안에 들어가야 한다.
        let auxiliaryArea = side == .left ? left : right
        guard width.isFinite, width > 0, width <= auxiliaryArea.width else { return nil }

        // 겹침은 노치 안에서만 허용한다. 반대편 보조 영역까지 넘어가면 표시하지 않는다.
        guard notchOverlap.isFinite, notchOverlap >= 0, notchOverlap < notchWidth else { return nil }

        let rect: CGRect
        // 생성식이 노치 경계 접촉과 `notchOverlap`만큼의 겹침을 보장하므로,
        // 여기서는 선택한 보조 영역의 바깥쪽과 반대편 보조 영역 경계만 확인한다.
        switch side {
        case .left:
            rect = CGRect(
                x: left.maxX - width,
                y: left.minY,
                width: width + notchOverlap,
                height: left.height
            )
            guard rect.minX >= left.minX - epsilon,
                  rect.maxX < right.minX + epsilon
            else { return nil }
        case .right:
            rect = CGRect(
                x: right.minX - notchOverlap,
                y: right.minY,
                width: width + notchOverlap,
                height: right.height
            )
            guard rect.maxX <= right.maxX + epsilon,
                  rect.minX > left.maxX - epsilon
            else { return nil }
        }

        // 최종 불변식 확인: 선택한 보조 영역과 노치 안에만 걸치고 전체는 화면 안이다.
        guard rect.minY >= auxiliaryArea.minY - epsilon, rect.maxY <= auxiliaryArea.maxY + epsilon,
              rect.minX >= frame.minX, rect.maxX <= frame.maxX,
              rect.minY >= frame.minY, rect.maxY <= frame.maxY
        else { return nil }
        return rect
    }
}

/// 배지의 검은 영역을 그리는 view다. 모서리마다 곡률 방향이 달라 `cornerRadius`로는 표현할 수 없다.
private final class NotchBadgeBackgroundView: NSView {
    override func makeBackingLayer() -> CALayer {
        let shape = CAShapeLayer()
        shape.fillColor = NSColor.black.cgColor
        return shape
    }

    var shapeLayer: CAShapeLayer? { layer as? CAShapeLayer }
}

/// 유효한 노치 화면 하나에 대응하는 오버레이 창과 그 화면 기하다.
private struct NotchOverlay {
    var screen: NSScreen
    var geometry: NotchScreenGeometry
    var side: NotchIndicatorSide
    var panel: NSPanel
    var backgroundView: NotchBadgeBackgroundView
    var iconView: NSImageView
}

/// 노치 좌우 상태 배지의 수명 주기를 소유하는 MenuBar Module의 표시 Adapter다.
/// 호출자는 생성해 유지하기만 하면 되고, 화면·창·관찰자 세부사항은 내부에 숨긴다.
@MainActor
final class NotchIndicatorController {
    /// 노치 바깥으로 드러나는 배지 폭이다. 아이콘 좌우 여백이 약 8pt가 되도록 잡았다.
    private static let badgeWidth: CGFloat = 40
    /// 배지 안 glyph의 optical size다.
    private static let iconPointSize: CGFloat = 16
    /// 화면 맨 위에서 바깥으로 벌어지는 역곡선의 반지름이다. 위쪽이 가장 넓다.
    private static let topFlareRadius: CGFloat = 8
    /// 노치 바깥쪽 아래 모서리를 볼록하게 둥글리는 반지름이다.
    private static let bottomCornerRadius: CGFloat = 8
    /// 검은 영역이 노치에서 자라 나오는 시간이다.
    private static let revealDuration: TimeInterval = 0.42
    /// 검은 영역이 다 펼쳐진 뒤 아이콘이 떠오르는 시간이다.
    private static let iconFadeDuration: TimeInterval = 0.20
    /// 아이콘이 먼저 사라지는 시간이다.
    private static let iconExitDuration: TimeInterval = 0.14
    /// 검은 영역이 노치 안으로 접히는 시간이다.
    private static let collapseDuration: TimeInterval = 0.36
    /// 아이콘이 떠오를 때 시작 배율이다. 노치 안에서 튀어나오는 느낌을 준다.
    private static let iconEntranceScale: CGFloat = 0.55
    /// 아이콘은 노치 안쪽 겹침과 바깥쪽 벌어짐을 제외한 검은 구간의 중앙에 놓는다.
    private static func iconCenterOffset(for side: NotchIndicatorSide) -> CGFloat {
        let offset = (NotchIndicatorLayout.defaultNotchOverlap - topFlareRadius) / 2
        return side == .left ? -offset : offset
    }

    /// 오른쪽 배지의 외곽선을 만든 뒤 왼쪽 배지는 전체 panel 안에서 수평 반전한다.
    private static func badgePath(
        width: CGFloat,
        height: CGFloat,
        side: NotchIndicatorSide,
        containerWidth: CGFloat? = nil
    ) -> CGPath {
        let path = CGMutablePath()
        guard width > 0, height > 0 else { return path }
        // 폭이 좁을 때는 두 곡률을 같은 비율로 줄여 경로가 뒤집히지 않게 한다.
        let shrink = min(1, width / max(topFlareRadius + bottomCornerRadius, 0.01))
        let flare = topFlareRadius * shrink
        let corner = min(bottomCornerRadius * shrink, height / 2)
        let bodyX = width - flare

        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: bodyX - corner, y: 0))
        path.addArc(
            center: CGPoint(x: bodyX - corner, y: corner),
            radius: corner,
            startAngle: -.pi / 2,
            endAngle: 0,
            clockwise: false
        )
        path.addLine(to: CGPoint(x: bodyX, y: height - flare))
        path.addArc(
            center: CGPoint(x: width, y: height - flare),
            radius: flare,
            startAngle: .pi,
            endAngle: .pi / 2,
            clockwise: true
        )
        path.addLine(to: CGPoint(x: 0, y: height))
        path.closeSubpath()
        guard side == .left else { return path }

        // 왼쪽 배지는 전체 panel의 오른쪽 끝이 노치에 닿는다. 접힌 path도 panel 오른쪽에 남도록
        // 현재 shape 폭이 아니라 전체 container 폭을 기준으로 수평 반전한다.
        let mirrorWidth = containerWidth ?? width
        var transform = CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: mirrorWidth, ty: 0)
        return path.copy(using: &transform) ?? path
    }

    private let model: AppModel
    private var overlays: [NotchOverlay] = []
    private var appearance: NotchIndicatorAppearance?
    private var transitionGenerations = NotchIndicatorTransitionGenerations()
    private var cancellables: Set<AnyCancellable> = []
    private var screenParametersObserver: NSObjectProtocol?
    private var accessibilityObserver: NSObjectProtocol?

    init(model: AppModel) {
        self.model = model
        rebuildOverlays()

        model.$postureState
            .combineLatest(model.$notchPreviewState)
            .map { actual, preview in
                NotchIndicatorPreview.effectiveState(
                    actual: actual,
                    preview: preview,
                    debugEnabled: AppLaunchFlags.debugEnabled
                )
            }
            .removeDuplicates()
            .sink { [weak self] state in
                self?.render(state)
            }
            .store(in: &cancellables)

        model.$settings
            .map(\.activeNotchIndicatorSides)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] sides in
                self?.rebuildOverlays(sides: sides)
            }
            .store(in: &cancellables)

        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.rebuildOverlays()
            }
        }
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.render(self.currentEffectiveState())
            }
        }
    }

    isolated deinit {
        if let screenParametersObserver {
            NotificationCenter.default.removeObserver(screenParametersObserver)
        }
        if let accessibilityObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver)
        }
        for overlay in overlays {
            overlay.panel.orderOut(nil)
        }
    }

    /// 현재 `NSScreen.screens`를 다시 읽어 오버레이를 전체 재구성한다.
    /// 화면 ID를 영속화하지 않으므로 중복 제거나 화면 객체 수명 문제가 없다.
    private func rebuildOverlays(sides requestedSides: [NotchIndicatorSide]? = nil) {
        for overlay in overlays {
            overlay.panel.orderOut(nil)
        }
        transitionGenerations.invalidateAll()
        let sides = requestedSides ?? model.settings.activeNotchIndicatorSides
        let screens = NSScreen.screens.map { screen -> (screen: NSScreen, geometry: NotchScreenGeometry) in
            (
                screen,
                NotchScreenGeometry(
                    frame: screen.frame,
                    safeAreaTop: screen.safeAreaInsets.top,
                    auxiliaryTopLeftArea: screen.auxiliaryTopLeftArea,
                    auxiliaryTopRightArea: screen.auxiliaryTopRightArea
                )
            )
        }
        model.setHasNotchedDisplay(
            screens.contains { NotchIndicatorLayout.supportsIndicator(on: $0.geometry, width: Self.badgeWidth) }
        )
        overlays = screens.flatMap { item in
            sides.compactMap { side -> NotchOverlay? in
                // 실제 배지 폭으로 검증한다. 상태와 무관하게 frame이 같으므로 여기서 확인한 것이 곧 표시 조건이다.
                guard NotchIndicatorLayout.badgeFrame(
                    for: item.geometry,
                    side: side,
                    width: Self.badgeWidth
                ) != nil else {
                    return nil
                }
                return makeOverlay(screen: item.screen, geometry: item.geometry, side: side)
            }
        }
        // 화면 재구성은 상태 전이가 아니므로 표시 중이던 배지는 애니메이션 없이 즉시 복원한다.
        applyAppearance(animated: false)
    }

    private func makeOverlay(
        screen: NSScreen,
        geometry: NotchScreenGeometry,
        side: NotchIndicatorSide
    ) -> NotchOverlay {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = .statusBar
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .canJoinAllApplications,
            .fullScreenAuxiliary,
            .ignoresCycle,
        ]
        // 장식용 오버레이이므로 접근성 창 목록에 노출하지 않는다.
        // 노출되면 보조 기술이 빈 대화상자로 읽고 외부에서 위치를 옮길 수 있다.
        panel.setAccessibilityElement(false)

        let content = NSView()
        content.wantsLayer = true
        content.setAccessibilityElement(false)

        // 물리 노치와 이어지는 불투명 검정이다. 동적 색이 아니므로 라이트·다크에서 같다.
        // 외곽 경로를 접었다 펼치는 애니메이션을 위해 content가 아니라 별도 view가 배경을 그린다.
        let background = NotchBadgeBackgroundView()
        background.wantsLayer = true
        background.setAccessibilityElement(false)
        content.addSubview(background)

        let icon = NSImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.wantsLayer = true
        icon.imageScaling = .scaleNone
        icon.setAccessibilityElement(false)
        content.addSubview(icon)
        NSLayoutConstraint.activate([
            // panel은 노치 안쪽까지 걸쳐 있으므로 아이콘은 노치 바깥 영역의 중앙에 놓는다.
            icon.centerXAnchor.constraint(
                equalTo: content.centerXAnchor,
                constant: Self.iconCenterOffset(for: side)
            ),
            icon.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])

        panel.contentView = content
        return NotchOverlay(
            screen: screen,
            geometry: geometry,
            side: side,
            panel: panel,
            backgroundView: background,
            iconView: icon
        )
    }

    /// 확정된 자세 상태를 현재 접근성 선호와 함께 표시에 반영한다.
    private func render(_ state: PostureState) {
        let accessibility = currentAccessibilityPreferences()
        let next = NotchIndicatorAppearance.make(
            for: state,
            accessibility: accessibility
        )
        // 동작 줄이기를 퇴장 도중 켜면 진행 중인 애니메이션을 즉시 끝낸다.
        // 그 외의 같은 결과는 다시 적용하지 않아 진행 중인 전환을 유지한다.
        guard next != appearance else {
            if next == nil, accessibility.reduceMotion {
                applyAppearance()
            }
            return
        }
        appearance = next
        applyAppearance()
    }

    private func applyAppearance(animated: Bool = true) {
        guard let appearance, let image = symbolImage(for: appearance.kind) else {
            // 상태가 숨김이거나 SF Symbol을 얻지 못하면 빈 검은 상자를 남기지 않고 접어 넣는다.
            for overlay in overlays {
                let overlayID = ObjectIdentifier(overlay.panel)
                let generation = transitionGenerations.begin(for: overlayID)
                collapse(overlay, generation: generation)
            }
            return
        }
        for overlay in overlays {
            let overlayID = ObjectIdentifier(overlay.panel)
            let generation = transitionGenerations.begin(for: overlayID)
            guard let rect = NotchIndicatorLayout.badgeFrame(
                for: overlay.geometry,
                side: overlay.side,
                width: Self.badgeWidth
            ) else {
                overlay.panel.orderOut(nil)
                continue
            }
            let aligned = overlay.screen.backingAlignedRect(rect, options: [.alignAllEdgesNearest])
            guard aligned.width > 0, aligned.height > 0 else {
                overlay.panel.orderOut(nil)
                continue
            }
            // 접히는 중에 다시 주의로 바뀌면 처음부터 다시 펼친다.
            let isCollapsing = overlay.backgroundView.shapeLayer?.animation(forKey: "notchCollapse") != nil
            let wasHidden = !overlay.panel.isVisible || isCollapsing
            if isCollapsing {
                overlay.backgroundView.shapeLayer?.removeAnimation(forKey: "notchCollapse")
            }
            overlay.panel.setFrame(aligned, display: false)
            overlay.iconView.image = image
            overlay.iconView.contentTintColor = color(for: appearance.kind)

            let full = CGRect(origin: .zero, size: aligned.size)
            let fullPath = Self.badgePath(
                width: full.width,
                height: full.height,
                side: overlay.side
            )
            overlay.backgroundView.frame = full
            guard wasHidden, animated, appearance.usesEntranceAnimation else {
                // 같은 상태가 다시 들어오면 다시 재생하지 않고 완성된 모습을 유지한다.
                // 사라지던 중이었다면 진행 중인 페이드를 취소해야 아이콘이 투명하게 남지 않는다.
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                overlay.iconView.layer?.removeAllAnimations()
                overlay.backgroundView.shapeLayer?.path = fullPath
                overlay.iconView.alphaValue = 1
                CATransaction.commit()
                // alpha를 1로 만든 뒤 제거해야 취소된 펼침의 완료 블록이 등장을 재생하지 않는다.
                overlay.backgroundView.shapeLayer?.removeAnimation(forKey: "notchReveal")
                overlay.panel.orderFrontRegardless()
                continue
            }

            // 노치 안에 숨어 있던 검은 영역이 선택한 방향으로 자라 나온 뒤 아이콘이 뒤따라 떠오른다.
            let collapsedPath = Self.badgePath(
                width: NotchIndicatorLayout.defaultNotchOverlap,
                height: full.height,
                side: overlay.side,
                containerWidth: full.width
            )
            let icon = overlay.iconView
            let shape = overlay.backgroundView.shapeLayer
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            icon.layer?.removeAllAnimations()
            shape?.path = fullPath
            icon.alphaValue = 0
            CATransaction.commit()
            overlay.panel.orderFrontRegardless()

            let reveal = CABasicAnimation(keyPath: "path")
            reveal.fromValue = collapsedPath
            reveal.toValue = fullPath
            reveal.duration = Self.revealDuration
            // 밀려 나온 뒤 끝에서 천천히 멎는 감속 곡선이다.
            reveal.timingFunction = CAMediaTimingFunction(controlPoints: 0.33, 1, 0.68, 1)

            CATransaction.begin()
            CATransaction.setCompletionBlock { [weak self] in
                Task { @MainActor [weak self] in
                    self?.finishReveal(for: overlayID, generation: generation)
                }
            }
            shape?.add(reveal, forKey: "notchReveal")
            CATransaction.commit()
        }
    }

    private func finishReveal(for overlayID: ObjectIdentifier, generation: UInt) {
        // 펼침이 취소돼도(접힘 전환, 즉시 적용) 완료 블록은 호출된다.
        // 최신 전환이면서 여전히 표시 중이고 아이콘이 아직 숨겨져 있을 때만 등장을 재생한다.
        guard let overlay = overlay(matching: overlayID, generation: generation),
              appearance != nil,
              overlay.iconView.alphaValue == 0
        else { return }

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = Self.iconEntranceScale
        scale.toValue = 1
        scale.duration = Self.iconFadeDuration
        scale.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
        overlay.iconView.layer?.add(scale, forKey: "notchIconEntrance")
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.iconFadeDuration
            overlay.iconView.animator().alphaValue = 1
        }
    }

    /// 검은 영역을 노치 안으로 접어 넣은 뒤 창을 내린다.
    private func collapse(_ overlay: NotchOverlay, generation: UInt) {
        let panel = overlay.panel
        let background = overlay.backgroundView
        let icon = overlay.iconView
        // 퇴장도 호출 시점의 동작 줄이기 설정을 따른다.
        guard overlay.panel.isVisible, !currentAccessibilityPreferences().reduceMotion else {
            icon.layer?.removeAllAnimations()
            background.shapeLayer?.removeAllAnimations()
            panel.orderOut(nil)
            return
        }
        guard background.shapeLayer?.animation(forKey: "notchCollapse") == nil else { return }
        background.shapeLayer?.removeAnimation(forKey: "notchReveal")

        // 아이콘이 먼저 사라지고, 그다음 검은 영역이 노치 안으로 되돌아간다.
        let overlayID = ObjectIdentifier(panel)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.iconExitDuration
            icon.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                self?.startCollapse(for: overlayID, generation: generation)
            }
        }
    }

    private func startCollapse(for overlayID: ObjectIdentifier, generation: UInt) {
        guard let overlay = overlay(matching: overlayID, generation: generation),
              appearance == nil
        else { return }
        guard !currentAccessibilityPreferences().reduceMotion else {
            overlay.iconView.layer?.removeAllAnimations()
            overlay.backgroundView.shapeLayer?.removeAllAnimations()
            overlay.panel.orderOut(nil)
            return
        }
        let size = overlay.backgroundView.frame.size
        let collapsedWidth = NotchIndicatorLayout.defaultNotchOverlap
        guard size.width > collapsedWidth, size.height > 0 else {
            overlay.panel.orderOut(nil)
            return
        }

        let collapse = CABasicAnimation(keyPath: "path")
        collapse.fromValue = Self.badgePath(
            width: size.width,
            height: size.height,
            side: overlay.side
        )
        collapse.toValue = Self.badgePath(
            width: collapsedWidth,
            height: size.height,
            side: overlay.side,
            containerWidth: size.width
        )
        collapse.duration = Self.collapseDuration
        collapse.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.6, 1)
        collapse.fillMode = .forwards
        collapse.isRemovedOnCompletion = false

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            Task { @MainActor [weak self] in
                self?.finishCollapse(for: overlayID, generation: generation)
            }
        }
        overlay.backgroundView.shapeLayer?.add(collapse, forKey: "notchCollapse")
        CATransaction.commit()
    }

    private func finishCollapse(for overlayID: ObjectIdentifier, generation: UInt) {
        guard let overlay = overlay(matching: overlayID, generation: generation) else { return }
        overlay.backgroundView.shapeLayer?.removeAnimation(forKey: "notchCollapse")
        guard appearance == nil else { return }
        overlay.panel.orderOut(nil)
    }

    private func overlay(matching overlayID: ObjectIdentifier, generation: UInt) -> NotchOverlay? {
        guard transitionGenerations.isCurrent(generation, for: overlayID) else { return nil }
        return overlays.first { ObjectIdentifier($0.panel) == overlayID }
    }

    /// tint를 적용할 수 있도록 template SF Symbol을 만든다. 이름을 해석하지 못하면 nil이다.
    private func symbolImage(for kind: NotchIndicatorAppearance.Kind) -> NSImage? {
        guard let image = NSImage(systemSymbolName: kind.symbolName, accessibilityDescription: nil) else {
            return nil
        }
        let configured = image.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: Self.iconPointSize, weight: .semibold)
        )
        configured?.isTemplate = true
        return configured
    }

    /// 의미 토큰을 실제 시스템 색상으로 변환한다.
    private func color(for kind: NotchIndicatorAppearance.Kind) -> NSColor {
        switch kind {
        case .caution:
            return .systemYellow
        }
    }

    /// 접근성 알림처럼 구독 밖에서 다시 그릴 때도 미리보기가 유지되도록 한 군데로 모은다.
    private func currentEffectiveState() -> PostureState {
        NotchIndicatorPreview.effectiveState(
            actual: model.postureState,
            preview: model.notchPreviewState,
            debugEnabled: AppLaunchFlags.debugEnabled
        )
    }

    private func currentAccessibilityPreferences() -> AccessibilityDisplayPreferences {
        let workspace = NSWorkspace.shared
        return AccessibilityDisplayPreferences(
            reduceMotion: workspace.accessibilityDisplayShouldReduceMotion,
            differentiateWithoutColor: workspace.accessibilityDisplayShouldDifferentiateWithoutColor,
            increaseContrast: workspace.accessibilityDisplayShouldIncreaseContrast
        )
    }
}
