import SwiftUI
import DakaCore

struct MenuBarView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("今日打卡").font(.headline)

            statusRow(.morning, done: model.record.morningDone, at: model.record.morningDoneAt,
                      start: model.settings.morningWindowStart, deadline: model.settings.morningDeadline)
            statusRow(.evening, done: model.record.eveningDone, at: model.record.eveningDoneAt,
                      start: model.settings.eveningWindowStart, deadline: model.settings.eveningDeadline)

            Divider()

            HStack {
                Button("上班打卡") { model.punch(.morning) }
                    .disabled(model.record.morningDone)
                Button("下班打卡") { model.punch(.evening) }
                    .disabled(model.record.eveningDone)
            }

            Divider()

            Button("打开 Daka") { model.openMainWindow() }
            Button("退出 Daka") { model.quit() }
                .disabled(model.hasHardTasks)

            if let warning = model.scheduledLaunchWarning {
                Text(warning).font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(14)
        .frame(width: 280)
    }

    private func statusRow(_ task: PunchTask, done: Bool, at: Date?, start: String, deadline: String) -> some View {
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
