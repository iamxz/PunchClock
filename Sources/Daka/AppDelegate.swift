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

        // 系统关机/注销开始时置放行；若用户取消注销，60 秒后重新封锁退出。
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willPowerOffNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                AppModel.shared.allowTermination = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
                MainActor.assumeIsolated { AppModel.shared.allowTermination = false }
            }
        }

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

    /// 放行退出，但先弹确认框说明影响（退出后打卡提醒会停止）；取消则继续运行。
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated { AppModel.shared.shouldTerminate() }
    }
}
