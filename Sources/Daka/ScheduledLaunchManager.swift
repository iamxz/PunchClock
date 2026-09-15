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
        guard Bundle.main.bundlePath.hasPrefix("/Applications/") else { return .skipped }
        guard let bundleID = Bundle.main.bundleIdentifier else { return .skipped }

        let times = [settings.morningWindowStart, settings.morningDeadline,
                     settings.eveningWindowStart, settings.eveningDeadline]
        guard times.contains(where: { DakaDate.timeComponents($0) != nil }) else { return .skipped }

        let plist = LaunchAgentPlist.make(morningWindowStart: settings.morningWindowStart,
                                          morningDeadline: settings.morningDeadline,
                                          eveningWindowStart: settings.eveningWindowStart,
                                          eveningDeadline: settings.eveningDeadline,
                                          bundleID: bundleID)
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
        _ = runLaunchctl(["bootout", "gui/\(uid)/\(LaunchAgentPlist.label)"])
        let bootstrap = runLaunchctl(["bootstrap", "gui/\(uid)", plistURL.path])
        if bootstrap.status != 0 {
            let detail = bootstrap.stderr.isEmpty ? "退出码 \(bootstrap.status)" : bootstrap.stderr
            return InstallResult(installed: false, warning: "定点启动加载失败（\(detail)）")
        }
        return InstallResult(installed: true, warning: nil)
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
