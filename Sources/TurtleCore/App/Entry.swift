import AppKit

@MainActor private var retainedDelegate: AppDelegate?

enum AppLaunchFlags {
    static var debugEnabled: Bool {
        CommandLine.arguments.contains("--debug") ||
            ProcessInfo.processInfo.environment["TURTLEMECK_DEBUG"] == "1"
    }
}

enum AppUIMode: Equatable {
    case menuBar
    case window

    static var current: AppUIMode {
        AppLaunchFlags.debugEnabled ? .window : .menuBar
    }
}

@MainActor
public func runTurtleMeckApp() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    retainedDelegate = delegate
    app.delegate = delegate
    app.setActivationPolicy(AppUIMode.current == .window ? .regular : .accessory)
    app.run()
}
