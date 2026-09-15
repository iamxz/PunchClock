import Foundation
import DakaCore

/// 管理 ~/Library/LaunchAgents/com.xue.daka.schedule.plist：到窗口时间用 `open -b` 拉起应用。
enum ScheduledLaunchManager {
    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(LaunchAgentPlist.label).plist")
    }

    /// 写入并加载 LaunchAgent。成功返回 nil，失败返回错误信息。无有效时间时跳过。
    @discardableResult
    static func install(settings: Settings) -> String? {
        guard Bundle.main.bundlePath.hasSuffix(".app") else { return nil }
        guard let bundleID = Bundle.main.bundleIdentifier else { return nil }

        let times = [settings.morningWindowStart, settings.morningDeadline,
                     settings.eveningWindowStart, settings.eveningDeadline]
        guard times.contains(where: { DakaDate.timeComponents($0) != nil }) else { return nil }

        let plist = LaunchAgentPlist.make(morningWindowStart: settings.morningWindowStart,
                                          morningDeadline: settings.morningDeadline,
                                          eveningWindowStart: settings.eveningWindowStart,
                                          eveningDeadline: settings.eveningDeadline,
                                          bundleID: bundleID)
        guard !plist.isEmpty else { return "定点启动生成失败" }

        do {
            try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try plist.write(to: plistURL, atomically: true, encoding: .utf8)
        } catch {
            return "定点启动写入失败：\(error.localizedDescription)"
        }

        let uid = getuid()
        runLaunchctl(["bootout", "gui/\(uid)/\(LaunchAgentPlist.label)"])
        let status = runLaunchctl(["bootstrap", "gui/\(uid)", plistURL.path])
        if status != 0 {
            return "定点启动加载失败（launchctl bootstrap 退出码 \(status)）"
        }
        return nil
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    @discardableResult
    private static func runLaunchctl(_ args: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = args
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }
}
