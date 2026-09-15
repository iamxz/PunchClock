import Foundation

/// 生成定点启动用的 launchd LaunchAgent plist 文本。
public enum LaunchAgentPlist {
    public static let label = "com.xue.daka.schedule"

    public static func make(morningWindowStart: String,
                            morningDeadline: String,
                            eveningWindowStart: String,
                            eveningDeadline: String,
                            bundleID: String) -> String {
        let times: [(hour: Int, minute: Int)] = [
            morningWindowStart, morningDeadline, eveningWindowStart, eveningDeadline
        ].compactMap { DakaDate.timeComponents($0).map { (hour: $0.hour, minute: $0.minute) } }

        var intervals = ""
        for time in times {
            intervals += "        <dict>\n"
            intervals += "            <key>Hour</key>\n"
            intervals += "            <integer>\(time.hour)</integer>\n"
            intervals += "            <key>Minute</key>\n"
            intervals += "            <integer>\(time.minute)</integer>\n"
            intervals += "        </dict>\n"
        }

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key><string>\(label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>/usr/bin/open</string>
                <string>-b</string>
                <string>\(bundleID)</string>
            </array>
            <key>StartCalendarInterval</key>
            <array>
        \(intervals)    </array>
        </dict>
        </plist>
        """
    }
}
