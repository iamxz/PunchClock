import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindow: MainWindowController?

    func applicationWillFinishLaunching(_ notification: Notification) {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if let existing = others.first {
            existing.activate(options: [])
            exit(0)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        let model = AppModel.shared
        let controller = MainWindowController(model: model)
        self.mainWindow = controller
        model.mainWindow = controller

        model.start()

        let isBackground = CommandLine.arguments.contains("--background")
        let launchKey = "NSApplicationLaunchIsDefaultLaunchKey"
        let isUserLaunch = (notification.userInfo?[launchKey] as? Bool) ?? true
        if !isBackground && isUserLaunch {
            controller.show()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { mainWindow?.show() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let hard = MainActor.assumeIsolated { AppModel.shared.hasHardTasks }
        return hard ? .terminateCancel : .terminateNow
    }
}
