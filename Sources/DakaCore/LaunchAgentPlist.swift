import Foundation

/// 生成定点启动用的 launchd LaunchAgent plist 文本。
public enum LaunchAgentPlist {
    public static let label = "com.xue.daka.schedule"

    public static func make(morningWindowStart: String,
                            morningDeadline: String,
                            eveningWindowStart: String,
                            eveningDeadline: String,
                            bundleID: String) -> String {
        var intervals: [[String: Int]] = []
        for hhmm in [morningWindowStart, morningDeadline, eveningWindowStart, eveningDeadline] {
            guard let time = DakaDate.timeComponents(hhmm) else { continue }
            let entry = ["Hour": time.hour, "Minute": time.minute]
            if !intervals.contains(entry) {
                intervals.append(entry)
            }
        }

        var plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": ["/bin/sh", "-c",
                                 "/usr/bin/pgrep -u \"$(id -u)\" -x Daka >/dev/null 2>&1 || /usr/bin/open -b \(bundleID) --args --background"]
        ]
        if !intervals.isEmpty {
            plist["StartCalendarInterval"] = intervals
        }

        guard let data = try? PropertyListSerialization.data(fromPropertyList: plist,
                                                             format: .xml,
                                                             options: 0),
              let xml = String(data: data, encoding: .utf8) else {
            return ""
        }
        return xml
    }
}
