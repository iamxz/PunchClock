import Foundation

/// 退出确认弹窗的文案。
///
/// 退出后打卡提醒会停止，属于有副作用的操作，因此把「退出影响」的说明集中在 Core 里，
/// 便于单测覆盖，也避免 UI 层随手改文案导致提醒丢失而不自知。
public enum QuitPrompt {
    public static let title = "确定要退出「打工人爱护自己」吗？"

    /// 退出影响说明：按今日打卡状态给出对应提示。
    /// - Parameters:
    ///   - skipped: 今天是否已设为休假。
    ///   - morningDone: 今天上班卡是否已打。
    ///   - eveningDone: 今天下班卡是否已满足工作时长完成。
    public static func impactText(skipped: Bool,
                                  morningDone: Bool,
                                  eveningDone: Bool) -> String {
        var lines: [String] = []

        if skipped {
            lines.append("今天已设为休假，退出不影响今日记录。")
        } else {
            var pending: [String] = []
            if !morningDone { pending.append("上班卡") }
            if !eveningDone { pending.append("下班卡") }
            if pending.isEmpty {
                lines.append("今日打卡已全部完成，退出不影响今日记录。")
            } else {
                lines.append("今日还有「\(pending.joined(separator: "、"))」未完成，退出后不会自动补记。")
            }
        }

        lines.append("退出后打卡提醒与全屏提醒都会停止，直到下次开机或手动启动。")
        lines.append("已有的打卡记录与设置不会丢失。")

        return lines.map { "• \($0)" }.joined(separator: "\n")
    }
}
