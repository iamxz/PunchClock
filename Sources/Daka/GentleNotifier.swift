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
        guard !tasks.isEmpty else { return }
        let body: String
        if tasks.count > 1 {
            body = "\(tasks.map(\.title).joined(separator: "、")) 都还没完成，记得在窗口内打卡。"
        } else {
            body = "\(tasks[0].title)：还在打卡窗口内，记得完成。"
        }
        notify(id: "daka.gentle", title: "打卡提醒", body: body)
    }

    func notify(id: String, title: String, body: String) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        center.add(request)
    }
}
