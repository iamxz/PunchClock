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
        return FileManager.default.fileExists(atPath: launchAgentURL.path)
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
