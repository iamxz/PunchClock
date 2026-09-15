import SwiftUI
import DakaCore

struct MenuBarView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 12) {
            Text("今日打卡").font(.headline)

            VStack(spacing: 6) {
                statusRow(.morning, done: model.record.morningDone, at: model.record.morningDoneAt,
                          count: model.record.morningPunches.count,
                          start: model.settings.morningWindowStart, deadline: model.settings.morningDeadline)
                statusRow(.evening, done: model.isEveningComplete, at: model.effectiveEveningPunch,
                          count: model.record.eveningPunches.count,
                          start: model.settings.eveningWindowStart, deadline: model.settings.eveningDeadline)
            }

            PunchButton(task: PunchTarget.resolve(record: model.record,
                                                  now: model.now,
                                                  minWorkDuration: model.minWorkDuration)) { task in
                model.punch(task)
            }

            Divider()

            HStack {
                Button("显示") { model.openMainWindow() }
                    .frame(maxWidth: .infinity)
                Button("退出") { model.quit() }
                    .frame(maxWidth: .infinity)
                    .disabled(model.hasHardTasks)
            }
        }
        .padding(16)
        .frame(width: 220)
    }

    private var scheduleInactive: Bool {
        !model.settings.enabled
            || model.record.skipped
            || !model.settings.workdays.contains(DakaDate.weekday(of: model.now))
    }

    private func statusRow(_ task: PunchTask, done: Bool, at: Date?, count: Int, start: String, deadline: String) -> some View {
        let suffix = count > 1 ? "（\(count) 次）" : ""
        return HStack {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? Color.green : Color.secondary)
            Text(task.title)
            Spacer()
            if done, let at {
                Text(count > 1 ? "\(Self.timeFormatter.string(from: at))（\(count) 次）" : Self.timeFormatter.string(from: at))
                    .foregroundStyle(.secondary)
            } else if scheduleInactive {
                Text("今日不提醒").foregroundStyle(.secondary)
            } else if model.reminderState.hard.contains(task) {
                Text("已过截止 \(deadline)\(suffix)").foregroundStyle(.red)
            } else if model.reminderState.gentle.contains(task) {
                Text("窗口内 \(start)–\(deadline)\(suffix)").foregroundStyle(.orange)
            } else {
                Text("待打卡 \(start)–\(deadline)\(suffix)").foregroundStyle(.secondary)
            }
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}
