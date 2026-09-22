import Foundation
import ServiceManagement

enum LoginItemManager {
    static var launchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.xue.daka.plist")
    }

    /// 仅在作为 .app bundle 运行时注册；`swift run` 下跳过。返回错误信息（成功为 nil）。
    @discardableResult
    static func registerIfNeeded() -> String? {
        guard Bundle.main.bundlePath.hasSuffix(".app") else { return nil }
        let status = SMAppService.mainApp.status
        if status == .enabled || status == .requiresApproval { return nil }
        do {
            try SMAppService.mainApp.register()
            return nil
        } catch {
            do {
                try writeLaunchAgentFallback()
                return nil
            } catch {
                return "开机自启注册失败：\(error.localizedDescription)"
            }
        }
    }

    static var isEnabled: Bool {
        let status = SMAppService.mainApp.status
        if status == .requiresApproval { return false }
        if status == .enabled { return true }
        guard let contents = try? String(contentsOf: launchAgentURL, encoding: .utf8) else { return false }
        return contents.contains(Bundle.main.bundlePath)
    }

    /// 开关开机自启。返回错误信息（成功为 nil）。
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> String? {
        guard Bundle.main.bundlePath.hasSuffix(".app") else { return nil }
        if enabled { return isEnabled ? nil : registerIfNeeded() }

        var unregisterError: Error?
        do {
            try SMAppService.mainApp.unregister()
        } catch {
            unregisterError = error
        }
        // 回退方案写入的 LaunchAgent 文件一律清掉
        if FileManager.default.fileExists(atPath: launchAgentURL.path) {
            try? FileManager.default.removeItem(at: launchAgentURL)
        }
        guard let unregisterError, SMAppService.mainApp.status == .enabled else { return nil }
        return "关闭开机自启失败：\(unregisterError.localizedDescription)"
    }

    static var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private static func writeLaunchAgentFallback() throws {
        let executable = Bundle.main.bundlePath + "/Contents/MacOS/Daka"
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key><string>com.xue.daka</string>
            <key>ProgramArguments</key>
            <array><string>\(executable)</string></array>
            <key>RunAtLoad</key><true/>
        </dict>
        </plist>
        """
        try FileManager.default.createDirectory(at: launchAgentURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try plist.write(to: launchAgentURL, atomically: true, encoding: .utf8)
    }
}
