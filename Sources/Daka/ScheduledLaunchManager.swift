import Foundation
import DakaCore

/// 管理 ~/Library/LaunchAgents/com.xue.daka.schedule.plist：到窗口时间用 `open -b` 拉起应用。
enum ScheduledLaunchManager {
    struct InstallResult {
        var installed: Bool
        var warning: String?

        static let skipped = InstallResult(installed: false, warning: nil)
    }

    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(LaunchAgentPlist.label).plist")
    }

    private static let queue = DispatchQueue(label: "com.xue.daka.scheduled-launch")

    /// 异步写入并加载 LaunchAgent（launchctl 可能耗时，避免阻塞主线程）。
    /// 完成后在主线程回调安装结果。
    static func install(settings: Settings, completion: @escaping (InstallResult) -> Void) {
        queue.async {
            let result = performInstall(settings: settings)
            DispatchQueue.main.async { completion(result) }
        }
    }

    private static func performInstall(settings: Settings) -> InstallResult {
        guard settings.scheduledLaunchEnabled else { return performUninstall() }
        guard Bundle.main.bundlePath.hasPrefix("/Applications/") else { return .skipped }
        guard let bundleID = Bundle.main.bundleIdentifier else { return .skipped }

        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        let times: [String]
        if let start = fmt.date(from: settings.workStartTime) {
            let flexEnd = start.addingTimeInterval(settings.flexDuration)
            let workEnd = start.addingTimeInterval(settings.workDuration)
            times = [settings.workStartTime, fmt.string(from: flexEnd), fmt.string(from: workEnd)]
        } else {
            times = []
        }
        guard times.contains(where: { DakaDate.timeComponents($0) != nil }) else { return .skipped }

        let plist = LaunchAgentPlist.make(times: times, bundleID: bundleID)
        guard !plist.isEmpty else { return InstallResult(installed: false, warning: "定点启动生成失败") }

        do {
            try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try plist.write(to: plistURL, atomically: true, encoding: .utf8)
        } catch {
            return InstallResult(installed: false,
                                 warning: "定点启动写入失败：\(error.localizedDescription)")
        }

        let uid = getuid()
        bootout(uid: uid)
        let bootstrap = runLaunchctl(["bootstrap", "gui/\(uid)", plistURL.path])
        if bootstrap.status != 0 {
            let detail = bootstrap.stderr.isEmpty ? "退出码 \(bootstrap.status)" : bootstrap.stderr
            return InstallResult(installed: false, warning: "定点启动加载失败（\(detail)）")
        }
        return InstallResult(installed: true, warning: nil)
    }

    /// 移除 LaunchAgent：先 bootout 再删 plist。
    private static func performUninstall() -> InstallResult {
        bootout(uid: getuid())
        guard FileManager.default.fileExists(atPath: plistURL.path) else {
            return InstallResult(installed: false, warning: nil)
        }
        do {
            try FileManager.default.removeItem(at: plistURL)
            return InstallResult(installed: false, warning: nil)
        } catch {
            return InstallResult(installed: false,
                                 warning: "定点启动移除失败：\(error.localizedDescription)")
        }
    }

    private static func bootout(uid: uid_t) {
        _ = runLaunchctl(["bootout", "gui/\(uid)/\(LaunchAgentPlist.label)"])
    }

    @discardableResult
    private static func runLaunchctl(_ args: [String]) -> (status: Int32, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        let errorPipe = Pipe()
        process.standardError = errorPipe
        do {
            try process.run()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let text = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return (process.terminationStatus, text)
        } catch {
            return (-1, error.localizedDescription)
        }
    }
}
