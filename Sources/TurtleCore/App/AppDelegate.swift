import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var statusController: StatusItemController?
    private var onboardingController: OnboardingWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        statusController = StatusItemController(model: model)

        if model.hasCompletedOnboarding {
            model.start()
        } else {
            showOnboarding()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
    }

    private func showOnboarding() {
        let controller = OnboardingWindowController(model: model)
        onboardingController = controller
        controller.showWindow(nil)
    }
}
