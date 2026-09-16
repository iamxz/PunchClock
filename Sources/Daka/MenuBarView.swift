import SwiftUI
import DakaCore

struct MenuBarView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("今日打卡").font(.headline)
                Spacer()
                Button {
                    model.openControlCenter()
                } label: {
                    Image(systemName: "switch.2")
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .help("打开控制中心")
                .accessibilityLabel("控制中心")
            }

            VStack(spacing: 6) {
                statusRow(.morning, done: model.record.morningDone,
                          count: model.record.morningPunches.count,
                          deadline: model.settings.morningDeadline)
                statusRow(.evening, done: model.isEveningComplete,
                          count: model.record.eveningPunches.count,
                          deadline: model.settings.eveningDeadline)
            }

            PunchButton(task: PunchTarget.resolve(record: model.record,
                                                  now: model.now,
                                                  minWorkDuration: model.minWorkDuration),
                        record: model.record,
                        nowProvider: { model.now },
                        minWorkDuration: model.minWorkDuration) { task in
                model.punch(task)
            }
        }
        .padding(16)
        .frame(width: 200)
    }

    private var scheduleInactive: Bool {
        !model.settings.enabled
            || model.record.skipped
            || !model.settings.workdays.contains(DakaDate.weekday(of: model.now))
    }

    private func statusRow(_ task: PunchTask, done: Bool, count: Int, deadline: String) -> some View {
        let suffix = count > 1 ? "（\(count) 次）" : ""
        let status: (text: String, color: Color) = {
            if done { return ("已完成\(suffix)", .secondary) }
            if scheduleInactive { return ("今日不提醒", .secondary) }
            if model.reminderState.contains(task) {
                if let due = DakaDate.date(on: model.now, at: deadline), model.now >= due {
                    return ("已过截止\(suffix)", .red)
                }
                return ("窗口内\(suffix)", .orange)
            }
            return ("待打卡\(suffix)", .secondary)
        }()
        return HStack {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? Color.green : Color.secondary)
            Text(task.title)
            Spacer()
            Text(status.text)
                .foregroundStyle(status.color)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }
}
