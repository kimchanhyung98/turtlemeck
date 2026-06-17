import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController: NSWindowController {
    init(model: AppModel) {
        let view = OnboardingView(model: model)
        let controller = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: controller)
        window.title = "turtlemac"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 480, height: 420))
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}
