import AppKit
import Combine
import QuartzCore
import SwiftUI

@MainActor
final class StatusItemController: NSObject {
    private let model: AppModel
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private var cancellables: Set<AnyCancellable> = []
    private var previousState: PostureState?
    private var recoveryWorkItem: DispatchWorkItem?

    init(model: AppModel) {
        self.model = model
        super.init()

        configureStatusItem()
        configurePopover()

        model.$postureState
            .sink { [weak self] state in
                self?.handleStateChange(state)
            }
            .store(in: &cancellables)
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else {
            return
        }
        button.target = self
        button.action = #selector(togglePopover)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        updateStatusIcon(for: model.postureState)
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 320, height: 520)
        popover.contentViewController = NSHostingController(rootView: MenuView(model: model))
    }

    private func handleStateChange(_ state: PostureState) {
        let shouldShowRecovery = previousState == .bad && state == .good
        previousState = state

        if shouldShowRecovery {
            showRecoveryIcon()
            return
        }

        recoveryWorkItem?.cancel()
        recoveryWorkItem = nil
        updateStatusIcon(for: state)
    }

    private func showRecoveryIcon() {
        updateStatusIcon(for: .good, tint: .systemGreen, labelOverride: "자세: 회복")

        let item = DispatchWorkItem { [weak self] in
            guard self?.model.postureState == .good else {
                return
            }
            self?.updateStatusIcon(for: .good)
        }
        recoveryWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: item)
    }

    private func updateStatusIcon(for state: PostureState, tint: NSColor? = nil, labelOverride: String? = nil) {
        guard let button = statusItem.button else {
            return
        }

        let symbol: String
        let label: String
        switch state {
        case .good:
            symbol = "tortoise.fill"
            label = "자세: 정상"
        case .bad:
            symbol = "exclamationmark.triangle.fill"
            label = "자세: 전방머리 징후"
        case .calibrating:
            symbol = "scope"
            label = "자세: 보정 중"
        case .noEval:
            symbol = "questionmark.circle"
            label = "자세: 추적 중"
        case .paused:
            symbol = "pause.circle.fill"
            label = "자세: 일시정지"
        case .blocked:
            symbol = "video.slash.fill"
            label = "자세: 카메라 확인 필요"
        }

        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        image?.isTemplate = true
        button.image = image
        button.contentTintColor = tint ?? tintColor(for: state)
        button.setAccessibilityLabel(labelOverride ?? label)

        if state == .bad {
            startPulse(on: button)
        } else {
            stopPulse(on: button)
        }
    }

    private func tintColor(for state: PostureState) -> NSColor? {
        switch state {
        case .bad:
            return .systemOrange
        case .good, .calibrating, .noEval, .paused, .blocked:
            return nil
        }
    }

    private func startPulse(on button: NSStatusBarButton) {
        stopPulse(on: button)
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            return
        }

        button.wantsLayer = true
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 1.0
        animation.toValue = 0.5
        animation.duration = 0.8
        animation.autoreverses = true
        animation.repeatCount = .infinity
        button.layer?.add(animation, forKey: "turtlemac.badPulse")
    }

    private func stopPulse(on button: NSStatusBarButton) {
        button.layer?.removeAnimation(forKey: "turtlemac.badPulse")
        button.alphaValue = 1
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else {
            return
        }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            ensurePopoverBelowMenuBar(button: button)
        }
    }

    private func ensurePopoverBelowMenuBar(button: NSStatusBarButton) {
        guard
            let window = popover.contentViewController?.view.window,
            let screen = button.window?.screen
        else {
            return
        }

        let visible = screen.visibleFrame
        if window.frame.maxY > visible.maxY {
            var frame = window.frame
            frame.origin.y = visible.maxY - frame.height - 4
            window.setFrame(frame, display: true)
        }
    }
}
