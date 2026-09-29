import SwiftUI
import DakaCore

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

            Section("考勤规则") {
                DatePicker("上班时间",
                           selection: Binding(
                            get: { settingsDateFrom(model.settings.workStartTime, now: model.now) },
                            set: { model.updateWorkStart(settingsHHMM(from: $0)) }),
                           displayedComponents: .hourAndMinute)
                Picker("弹性方式", selection: Binding(
                    get: { model.settings.flexMode },
                    set: { model.setFlexMode($0) })) {
                    ForEach(DakaCore.Settings.FlexMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                Text(model.settings.flexMode.flexMeaning)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Stepper(value: Binding(get: { model.settings.flexMinutes },
                                       set: { model.setFlexMinutes($0) }),
                        in: 0...120, step: 5) {
                    Text("弹性时间：\(model.settings.flexMinutes) 分钟")
                }
                Toggle("晚到记迟到", isOn: Binding(get: { model.settings.recordsLateArrival },
                                                   set: { model.setRecordsLateArrival($0) }))
                Text("上班卡晚于「上班时间 + 弹性时间」记一次迟到，日历提示与统计页的「本月迟到」跟着出现。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Stepper(value: Binding(get: { model.settings.workDurationHours },
                                       set: { model.setWorkDurationHours($0) }),
                        in: 0.5...12, step: 0.5) {
                    Text("工作时长：\(settingsHoursText(model.settings.workDurationHours)) 小时")
                }
            }

            Section("重复提醒") {
                Stepper(value: Binding(get: { Int(model.settings.reminderIntervalSeconds / 60) },
                                       set: { model.setReminderIntervalMinutes($0) }),
                        in: 1...60) {
                    Text("每隔 \(Int(model.settings.reminderIntervalSeconds / 60)) 分钟重复提醒")
                }
                Text("进入打卡窗口即全屏提醒，完成对应打卡后停止。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                Toggle("开机自启", isOn: Binding(
                    get: { model.loginItemEnabled },
                    set: { model.setLoginItemEnabled($0) }))
                if LoginItemManager.requiresApproval {
                    HStack {
                        Text("需在「系统设置 → 登录项」中允许").font(.caption).foregroundStyle(.orange)
                        Spacer()
                        Button("打开设置") { LoginItemManager.openSystemSettings() }
                    }
                }

                Toggle("定点启动", isOn: Binding(
                    get: { model.settings.scheduledLaunchEnabled },
                    set: { model.setScheduledLaunchEnabled($0) }))
                if model.settings.scheduledLaunchEnabled && !model.scheduledLaunchInstalled
                    && model.scheduledLaunchWarning == nil {
                    Text("当前运行位置不支持定点启动，需安装到「应用程序」目录").font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("应用") {
                Button("退出应用") { model.quit() }
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
