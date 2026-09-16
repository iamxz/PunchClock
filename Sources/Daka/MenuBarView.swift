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
        .frame(width: 180)
    }

    private var scheduleInactive: Bool {
        !model.settings.enabled
            || model.record.skipped
            || !model.settings.workdays.contains(DakaDate.weekday(of: model.now))
    }

    private func statusRow(_ task: PunchTask, done: Bool, count: Int, deadline: String) -> some View {
        let suffix = count > 1 ? "（\(count) 次）" : ""
        return HStack {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? Color.green : Color.secondary)
            Text(task.title)
            Spacer()
            if done {
                Text("已完成\(suffix)").foregroundStyle(.secondary)
            } else if scheduleInactive {
                Text("今日不提醒").foregroundStyle(.secondary)
            } else if model.reminderState.contains(task) {
                if let due = DakaDate.date(on: model.now, at: deadline), model.now >= due {
                    Text("已过截止\(suffix)").foregroundStyle(.red)
                } else {
                    Text("窗口内\(suffix)").foregroundStyle(.orange)
                }
            } else {
                Text("待打卡\(suffix)").foregroundStyle(.secondary)
            }
        }
    }
}
