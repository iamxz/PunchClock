import SwiftUI
import DakaCore

struct MenuBarView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("今日打卡").font(.headline)

            statusRow(task: .morning, done: model.record.morningDone,
                      at: model.record.morningDoneAt, due: model.settings.morningTime)
            statusRow(task: .evening, done: model.record.eveningDone,
                      at: model.record.eveningDoneAt, due: model.settings.eveningTime)

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

            DatePicker("上班时间", selection: morningBinding, displayedComponents: .hourAndMinute)
            DatePicker("下班时间", selection: eveningBinding, displayedComponents: .hourAndMinute)

            Divider()

            HStack {
                Button("调试：+10 分钟") { model.debugAdvanceClock(by: 600) }
                Button("重置时间") { model.resetClock() }
            }

            if let error = model.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
            }

            Divider()

            HStack {
                Image(systemName: LoginItemManager.isEnabled ? "checkmark.circle.fill" : "exclamationmark.triangle")
                    .foregroundStyle(LoginItemManager.isEnabled ? Color.green : Color.orange)
                Text(LoginItemManager.isEnabled ? "开机自启已启用" : "开机自启未启用")
                Spacer()
                if !LoginItemManager.isEnabled {
                    Button("启用") { model.repairLoginItem() }
                }
            }

            Divider()

            Button("退出 Daka") { model.quit() }
                .disabled(model.hasPendingTasks)
            if model.hasPendingTasks {
                Text("有待完成的打卡，无法退出").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: 320)
    }

    private func statusRow(task: PunchTask, done: Bool, at: Date?, due: String) -> some View {
        HStack {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? Color.green : Color.secondary)
            Text(task.title)
            Spacer()
            if done, let at {
                Text(Self.timeFormatter.string(from: at)).foregroundStyle(.secondary)
            } else {
                Text("待打卡 · \(due)").foregroundStyle(.orange)
            }
        }
    }

    private var morningBinding: Binding<Date> {
        Binding(get: { Self.dateFrom(model.settings.morningTime) },
                set: { model.updateMorning(Self.hhmm(from: $0)) })
    }

    private var eveningBinding: Binding<Date> {
        Binding(get: { Self.dateFrom(model.settings.eveningTime) },
                set: { model.updateEvening(Self.hhmm(from: $0)) })
    }

    private static func dateFrom(_ hhmm: String) -> Date {
        let (h, m) = DakaDate.timeComponents(hhmm) ?? (9, 0)
        var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        c.hour = h
        c.minute = m
        c.second = 0
        return Calendar.current.date(from: c) ?? Date()
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
