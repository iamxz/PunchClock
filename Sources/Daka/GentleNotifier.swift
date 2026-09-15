import Foundation
import UserNotifications
import DakaCore

/// 温和提醒通道：本地通知。未打包运行或无权限时静默（菜单栏警示仍在）。
final class GentleNotifier {
    private var center: UNUserNotificationCenter? {
        guard Bundle.main.bundleIdentifier != nil else { return nil }
        return UNUserNotificationCenter.current()
    }

    func requestAuthorizationIfNeeded() {
        guard let center else { return }
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notify(tasks: [PunchTask]) {
        guard let center, !tasks.isEmpty else { return }
        let content = UNMutableNotificationContent()
        content.title = "打卡提醒"
        if tasks.count > 1 {
            content.body = "\(tasks.map(\.title).joined(separator: "、")) 都还没完成，记得在窗口内打卡。"
        } else {
            content.body = "\(tasks[0].title)：还在打卡窗口内，记得完成。"
        }
        content.sound = .default
        let request = UNNotificationRequest(identifier: "daka.gentle",
                                            content: content,
                                            trigger: nil)
        center.add(request)
    }
}
