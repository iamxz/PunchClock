import SwiftUI
import DakaCore

struct ToolPanelView: View {
    @ObservedObject var model: AppModel
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("今日概览").font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                summaryRow("打卡", punchSummary, "checkmark.seal")
                summaryRow("喝水", "\(model.healthStatus.cups)/\(model.healthSettings.waterGoalCups) 杯", "drop")
                summaryRow("走动", "已起身 \(model.healthStatus.stands) 次", "figure.walk")
            }
            .font(.caption)

            HStack {
                Button {
                    model.drinkWater()
                } label: {
                    Label("喝水", systemImage: "drop.fill")
                        .frame(maxWidth: .infinity)
                }
                Button {
                    model.standUp()
                } label: {
                    Label("走动", systemImage: "figure.walk")
                        .frame(maxWidth: .infinity)
                }
            }

            Divider()

            Text("工具").font(.caption).foregroundStyle(.secondary)
            ForEach(model.tools) { tool in
                Button {
                    onClose()
                    model.openControlCenter(selecting: tool.id)
                } label: {
                    HStack {
                        Image(systemName: tool.symbol).frame(width: 18)
                        Text(tool.title)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Divider()

            PunchButton(task: PunchTarget.resolve(record: model.record,
                                                  now: model.now,
                                                  minWorkDuration: model.minWorkDuration),
                        record: model.record,
                        nowProvider: { model.now },
                        minWorkDuration: model.minWorkDuration) { task in
                model.punch(task)
            }

            Button("控制中心") { onClose(); model.openControlCenter() }
                .frame(maxWidth: .infinity)
        }
        .padding(14)
        .frame(width: 260)
    }

    private var punchSummary: String {
        let morning = model.record.morningDone ? "上班已完成" : "上班待打卡"
        let evening = model.isEveningComplete ? "下班已完成" : "下班待打卡"
        return "\(morning) · \(evening)"
    }

    private func summaryRow(_ title: String, _ value: String, _ symbol: String) -> some View {
        HStack {
            Image(systemName: symbol).frame(width: 18)
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }
}
