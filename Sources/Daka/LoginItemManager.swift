import Foundation
import ServiceManagement

enum LoginItemManager {
    /// 仅在作为 .app bundle 运行时注册；`swift run` 下跳过。
    static func registerIfNeeded() {
        guard Bundle.main.bundlePath.hasSuffix(".app") else { return }
        if SMAppService.mainApp.status == .enabled { return }
        do {
            try SMAppService.mainApp.register()
        } catch {
            try? writeLaunchAgentFallback()
        }
    }

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
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
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.xue.daka.plist")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try plist.write(to: url, atomically: true, encoding: .utf8)
    }
}
