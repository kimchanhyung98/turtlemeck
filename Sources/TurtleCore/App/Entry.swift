import AppKit

@MainActor private var retainedDelegate: AppDelegate?

@MainActor
public func runTurtleMacApp() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    retainedDelegate = delegate
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
