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
        .frame(width: 160)
    }
}
