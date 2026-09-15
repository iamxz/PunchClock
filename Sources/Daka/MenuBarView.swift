import SwiftUI
import DakaCore

struct MenuBarView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 12) {
            Text("今日打卡").font(.headline)

            VStack(spacing: 6) {
                statusRow(.morning, done: model.record.morningDone, at: model.record.morningDoneAt,
                          start: model.settings.morningWindowStart, deadline: model.settings.morningDeadline)
                statusRow(.evening, done: model.record.eveningDone, at: model.record.eveningDoneAt,
                          start: model.settings.eveningWindowStart, deadline: model.settings.eveningDeadline)
            }

            PunchButton(task: pendingTask) { task in
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

    private var pendingTask: PunchTask? {
        if !model.record.morningDone { return .morning }
        if !model.record.eveningDone { return .evening }
        return nil
    }

    private var scheduleInactive: Bool {
        !model.settings.enabled
            || model.record.skipped
            || !model.settings.workdays.contains(DakaDate.weekday(of: model.now))
    }

    private func statusRow(_ task: PunchTask, done: Bool, at: Date?, start: String, deadline: String) -> some View {
        HStack {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? Color.green : Color.secondary)
            Text(task.title)
            Spacer()
            if done, let at {
                Text(Self.timeFormatter.string(from: at)).foregroundStyle(.secondary)
            } else if scheduleInactive {
                Text("今日不提醒").foregroundStyle(.secondary)
            } else if model.reminderState.hard.contains(task) {
                Text("已过截止 \(deadline)").foregroundStyle(.red)
            } else if model.reminderState.gentle.contains(task) {
                Text("窗口内 \(start)–\(deadline)").foregroundStyle(.orange)
            } else {
                Text("待打卡 \(start)–\(deadline)").foregroundStyle(.secondary)
            }
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}
