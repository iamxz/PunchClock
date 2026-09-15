import SwiftUI
import DakaCore

struct MenuBarView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("今日打卡").font(.headline)

            statusRow(task: .morning, done: model.record.morningDone,
                      at: model.record.morningDoneAt,
                      start: model.settings.morningWindowStart,
                      deadline: model.settings.morningDeadline,
                      inactive: scheduleInactive)
            statusRow(task: .evening, done: model.record.eveningDone,
                      at: model.record.eveningDoneAt,
                      start: model.settings.eveningWindowStart,
                      deadline: model.settings.eveningDeadline,
                      inactive: scheduleInactive)

            HStack {
                Button("上班打卡") { model.punch(.morning) }
                    .disabled(model.record.morningDone)
                Button("下班打卡") { model.punch(.evening) }
                    .disabled(model.record.eveningDone)
            }

            Divider()

            if model.record.skipped {
                Text("今天已标记为不打卡").foregroundStyle(.secondary)
                Button("恢复打卡提醒") { model.setSkipped(false) }
            } else {
                Button("标记今天不打卡（休假）") { model.setSkipped(true) }
            }

            Divider()

            Toggle("启用提醒", isOn: Binding(
                get: { model.settings.enabled },
                set: { model.setEnabled($0) }))

            DatePicker("上班开始", selection: morningStartBinding, displayedComponents: .hourAndMinute)
            DatePicker("上班截止", selection: morningDeadlineBinding, displayedComponents: .hourAndMinute)
            DatePicker("下班开始", selection: eveningStartBinding, displayedComponents: .hourAndMinute)
            DatePicker("下班截止", selection: eveningDeadlineBinding, displayedComponents: .hourAndMinute)

            Divider()

            HStack {
                Button("调试：+10 分钟") { model.debugAdvanceClock(by: 600) }
                Button("重置时间") { model.resetClock() }
            }

            if let error = model.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
            }

            if let warning = model.startupWarning {
                Text(warning).font(.caption).foregroundStyle(.orange)
            }

            Divider()

            HStack {
                Image(systemName: LoginItemManager.isEnabled ? "checkmark.circle.fill" : "exclamationmark.triangle")
                    .foregroundStyle(LoginItemManager.isEnabled ? Color.green : Color.orange)
                Text(LoginItemManager.isEnabled
                     ? "开机自启已启用"
                     : (LoginItemManager.requiresApproval ? "开机自启需在系统设置中允许" : "开机自启未启用"))
                Spacer()
                if LoginItemManager.requiresApproval {
                    Button("打开设置") { LoginItemManager.openSystemSettings() }
                } else if !LoginItemManager.isEnabled {
                    Button("启用") { model.repairLoginItem() }
                }
            }

            Divider()

            Button("退出 Daka") { model.quit() }
                .disabled(model.hasHardTasks)
            if model.hasHardTasks {
                Text("有已过期的打卡未完成，无法退出").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: 320)
    }

    private var scheduleInactive: Bool {
        !model.settings.enabled
            || model.record.skipped
            || !model.settings.workdays.contains(DakaDate.weekday(of: Date()))
    }

    private func statusRow(task: PunchTask, done: Bool, at: Date?, start: String, deadline: String, inactive: Bool) -> some View {
        HStack {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? Color.green : Color.secondary)
            Text(task.title)
            Spacer()
            if done, let at {
                Text(Self.timeFormatter.string(from: at)).foregroundStyle(.secondary)
            } else if model.reminderState.hard.contains(task) {
                Text("已过截止 \(deadline)").foregroundStyle(.red)
            } else if model.reminderState.gentle.contains(task) {
                Text("窗口内待打卡 \(start)–\(deadline)").foregroundStyle(.orange)
            } else if inactive {
                Text("今日不提醒").foregroundStyle(.secondary)
            } else {
                Text("待打卡 · \(start)–\(deadline)").foregroundStyle(.secondary)
            }
        }
    }

    private var morningStartBinding: Binding<Date> {
        Binding(get: { Self.dateFrom(model.settings.morningWindowStart) },
                set: { model.updateMorningStart(Self.hhmm(from: $0)) })
    }

    private var morningDeadlineBinding: Binding<Date> {
        Binding(get: { Self.dateFrom(model.settings.morningDeadline) },
                set: { model.updateMorningDeadline(Self.hhmm(from: $0)) })
    }

    private var eveningStartBinding: Binding<Date> {
        Binding(get: { Self.dateFrom(model.settings.eveningWindowStart) },
                set: { model.updateEveningStart(Self.hhmm(from: $0)) })
    }

    private var eveningDeadlineBinding: Binding<Date> {
        Binding(get: { Self.dateFrom(model.settings.eveningDeadline) },
                set: { model.updateEveningDeadline(Self.hhmm(from: $0)) })
    }

    private static func dateFrom(_ hhmm: String) -> Date {
        DakaDate.date(on: Date(), at: hhmm) ?? Date()
    }

    private static func hhmm(from date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}
