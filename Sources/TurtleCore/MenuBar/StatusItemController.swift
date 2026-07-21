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
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?

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
        popover.delegate = self
        let hosting = NSHostingController(rootView: MenuView(model: model).frame(width: 304))
        hosting.sizingOptions = .preferredContentSize
        popover.contentViewController = hosting
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
        let emoji: String?
        let label: String
        switch state {
        case .good:
            symbol = "face.smiling"
            emoji = "🙂"
            label = "자세: 정상"
        case .bad:
            symbol = "tortoise.fill"
            emoji = "😢"
            label = "자세: 흐트러짐"
        case .calibrating:
            symbol = "scope"
            emoji = nil
            label = "자세: 보정 중"
        case .noEval:
            symbol = "figure.stand"
            emoji = "🐢"
            label = "자세: 초기 상태"
        case .paused:
            symbol = "pause.circle.fill"
            emoji = "🫥"
            label = "자세: 일시정지"
        case .blocked:
            symbol = "video.slash.fill"
            emoji = nil
            label = "자세: 카메라 확인 필요"
        case .needsCalibration:
            symbol = "scope"
            emoji = nil
            label = "자세: 보정 필요"
        }

        if let emoji {
            button.image = nil
            button.attributedTitle = NSAttributedString(
                string: emoji,
                attributes: [.font: NSFont.systemFont(ofSize: 15)]
            )
            button.contentTintColor = nil
        } else {
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
            image?.isTemplate = true
            button.attributedTitle = NSAttributedString(string: "")
            button.image = image
            button.contentTintColor = tint ?? tintColor(for: state)
        }
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
        case .good, .calibrating, .noEval, .paused, .blocked, .needsCalibration:
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
        button.layer?.add(animation, forKey: "turtlemeck.badPulse")
    }

    private func stopPulse(on button: NSStatusBarButton) {
        button.layer?.removeAnimation(forKey: "turtlemeck.badPulse")
        button.alphaValue = 1
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else {
            return
        }

        if popover.isShown {
            closePopover()
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            ensurePopoverBelowMenuBar(button: button)
            startEventMonitoring()
        }
    }

    private func closePopover() {
        stopEventMonitoring()
        popover.performClose(nil)
    }

    private func startEventMonitoring() {
        stopEventMonitoring()

        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            guard let self else {
                return event
            }
            guard self.popover.isShown else {
                return event
            }
            if event.window == self.popover.contentViewController?.view.window {
                return event
            }
            if event.window == self.statusItem.button?.window {
                return event
            }
            self.closePopover()
            return event
        }

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.popover.isShown else {
                    return
                }
                self.closePopover()
            }
        }
    }

    private func stopEventMonitoring() {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
            self.globalEventMonitor = nil
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

extension StatusItemController: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        stopEventMonitoring()
    }
}
