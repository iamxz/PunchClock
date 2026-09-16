import SwiftUI
import DakaCore

private let settingsWeekdayOptions: [(label: String, value: Int)] = [
    ("一", 2), ("二", 3), ("三", 4), ("四", 5), ("五", 6), ("六", 7), ("日", 1)
]

private func settingsDateFrom(_ hhmm: String, now: Date) -> Date {
    DakaDate.date(on: now, at: hhmm) ?? now
}

private func settingsHHMM(from date: Date) -> String {
    let c = Calendar.current.dateComponents([.hour, .minute], from: date)
    return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
}

private func settingsHoursText(_ hours: Double) -> String {
    hours == hours.rounded() ? String(Int(hours)) : String(format: "%.1f", hours)
}

struct ScheduleSettingsView: View {
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

            Section("重复提醒") {
                Stepper(value: Binding(get: { Int(model.settings.reminderIntervalSeconds / 60) },
                                       set: { model.setReminderIntervalMinutes($0) }),
                        in: 1...60) {
                    Text("每隔 \(Int(model.settings.reminderIntervalSeconds / 60)) 分钟重复提醒")
                }
                Text("进入打卡窗口即全屏提醒，完成对应打卡后停止。窗口截止时间仅用于统计缺卡。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func bound(_ keyPath: KeyPath<DakaCore.Settings, String>,
                       _ update: @escaping (String) -> Void) -> Binding<Date> {
        Binding(get: { settingsDateFrom(model.settings[keyPath: keyPath], now: model.now) },
                set: { update(settingsHHMM(from: $0)) })
    }
}

struct WorkdaySettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section("工作日") {
                HStack {
                    ForEach(settingsWeekdayOptions, id: \.value) { option in
                        Toggle(option.label, isOn: weekdayBinding(option.value))
                            .toggleStyle(.button)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func weekdayBinding(_ value: Int) -> Binding<Bool> {
        Binding(get: { model.settings.workdays.contains(value) },
                set: { on in
                    var days = model.settings.workdays
                    if on { days.insert(value) } else { days.remove(value) }
                    model.setWorkdays(days)
                })
    }
}

struct AttendanceSettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section("考勤规则") {
                Stepper(value: Binding(get: { model.settings.minWorkDurationHours },
                                       set: { model.setMinWorkHours($0) }),
                        in: 1...12, step: 0.5) {
                    Text("每日最少工时：\(settingsHoursText(model.settings.minWorkDurationHours)) 小时")
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct SystemSettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
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

            Section("应用") {
                Button("退出应用") { model.confirmQuit() }
            }

            if model.hasSettingsFeedback {
                Section {
                    SettingsFeedbackView(model: model)
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct SettingsFeedbackView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
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
    }
}
