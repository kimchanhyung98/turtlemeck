import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var statusController: StatusItemController?
    private var mainWindowController: NSWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        switch AppUIMode.current {
        case .menuBar:
            NSApplication.shared.setActivationPolicy(.accessory)
            statusController = StatusItemController(model: model)
        case .window:
            NSApplication.shared.setActivationPolicy(.regular)
            showMainWindow()
        }

        model.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
    }

    private func showMainWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "turtlemeck"
        window.contentViewController = NSHostingController(
            rootView: ScrollView { MenuView(model: model) }
        )
        window.setContentSize(NSSize(width: 600, height: 680))
        window.isReleasedWhenClosed = false
        window.center()

        let controller = NSWindowController(window: window)
        mainWindowController = controller
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
