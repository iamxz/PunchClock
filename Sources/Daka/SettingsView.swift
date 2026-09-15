import SwiftUI
import DakaCore

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Toggle("启用提醒", isOn: Binding(get: { model.settings.enabled },
                                            set: { model.setEnabled($0) }))

            Section("打卡窗口") {
                DatePicker("上班窗口开始", selection: bound(\.morningWindowStart, model.updateMorningStart),
                           displayedComponents: .hourAndMinute)
                DatePicker("上班窗口截止", selection: bound(\.morningDeadline, model.updateMorningDeadline),
                           displayedComponents: .hourAndMinute)
                DatePicker("下班窗口开始", selection: bound(\.eveningWindowStart, model.updateEveningStart),
                           displayedComponents: .hourAndMinute)
                DatePicker("下班窗口截止", selection: bound(\.eveningDeadline, model.updateEveningDeadline),
                           displayedComponents: .hourAndMinute)
            }

            Section("工作日") {
                HStack {
                    ForEach(Self.weekdayOptions, id: \.value) { option in
                        Toggle(option.label, isOn: weekdayBinding(option.value))
                            .toggleStyle(.button)
                    }
                }
            }

            Section("今天") {
                if model.record.skipped {
                    Button("恢复打卡提醒") { model.setSkipped(false) }
                } else {
                    Button("标记今天不打卡（休假）") { model.setSkipped(true) }
                }
            }

            Section("自启与定点") {
                HStack {
                    Image(systemName: LoginItemManager.isEnabled ? "checkmark.circle.fill" : "exclamationmark.triangle")
                        .foregroundStyle(LoginItemManager.isEnabled ? Color.green : Color.orange)
                    Text(LoginItemManager.isEnabled ? "开机自启已启用"
                         : (LoginItemManager.requiresApproval ? "开机自启需在系统设置中允许" : "开机自启未启用"))
                    Spacer()
                    if LoginItemManager.requiresApproval {
                        Button("打开设置") { LoginItemManager.openSystemSettings() }
                    } else if !LoginItemManager.isEnabled {
                        Button("启用") { model.repairLoginItem() }
                    }
                }
                HStack {
                    Image(systemName: model.scheduledLaunchInstalled ? "checkmark.circle.fill" : "exclamationmark.triangle")
                        .foregroundStyle(model.scheduledLaunchInstalled ? Color.green : Color.orange)
                    Text(model.scheduledLaunchInstalled ? "定点启动已启用" : "定点启动未启用")
                }
            }

            Section("调试") {
                HStack {
                    Button("+10 分钟") { model.debugAdvanceClock(by: 600) }
                    Button("重置时间") { model.resetClock() }
                }
            }

            if let error = model.errorMessage {
                Text(error).foregroundStyle(.red)
            }
            if let warning = model.startupWarning {
                Text(warning).foregroundStyle(.orange)
            }
            if let warning = model.scheduledLaunchWarning {
                Text(warning).foregroundStyle(.orange)
            }
        }
        .formStyle(.grouped)
    }

    private static let weekdayOptions: [(label: String, value: Int)] = [
        ("一", 2), ("二", 3), ("三", 4), ("四", 5), ("五", 6), ("六", 7), ("日", 1)
    ]

    private func weekdayBinding(_ value: Int) -> Binding<Bool> {
        Binding(get: { model.settings.workdays.contains(value) },
                set: { on in
                    var days = model.settings.workdays
                    if on { days.insert(value) } else { days.remove(value) }
                    model.setWorkdays(days)
                })
    }

    private func bound(_ keyPath: KeyPath<DakaCore.Settings, String>,
                       _ update: @escaping (String) -> Void) -> Binding<Date> {
        Binding(get: { Self.dateFrom(model.settings[keyPath: keyPath], now: model.now) },
                set: { update(Self.hhmm(from: $0)) })
    }

    private static func dateFrom(_ hhmm: String, now: Date) -> Date {
        DakaDate.date(on: now, at: hhmm) ?? now
    }

    private static func hhmm(from date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}
