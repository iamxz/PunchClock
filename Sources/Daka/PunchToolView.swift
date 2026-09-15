import SwiftUI
import DakaCore

struct PunchEditorTarget: Identifiable {
    let task: PunchTask
    let index: Int?
    let initial: Date

    var id: String { "\(task.rawValue)-\(index.map(String.init) ?? "new")" }
    var isNew: Bool { index == nil }
}

struct PunchToolView: View {
    @ObservedObject var model: AppModel
    @State private var editor: PunchEditorTarget?
    @State private var pendingDeletion: PunchEditorTarget?

    var body: some View {
        VStack(spacing: 16) {
            todayPunches

            HStack {
                if model.record.skipped {
                    Button("恢复打卡提醒") { model.setSkipped(false) }
                } else {
                    Button("标记今天不打卡（休假）") { model.setSkipped(true) }
                }
                Spacer()
            }

            StatisticsView(model: model)
        }
        .sheet(item: $editor) { target in
            PunchTimeEditor(model: model, target: target)
        }
        .confirmationDialog("删除这条打卡记录？", isPresented: deletionBinding, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if let target = pendingDeletion, let index = target.index {
                    model.removePunch(target.task, index: index)
                }
                pendingDeletion = nil
            }
            Button("取消", role: .cancel) { pendingDeletion = nil }
        }
    }

    private var deletionBinding: Binding<Bool> {
        Binding(get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } })
    }

    private var todayPunches: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("今日打卡").font(.headline)
            taskSection(.morning, dates: model.record.morningPunches)
            Divider()
            taskSection(.evening, dates: model.record.eveningPunches)
        }
    }

    private func taskSection(_ task: PunchTask, dates: [Date]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(task.title, systemImage: task == .morning ? "sunrise" : "sunset")
                Spacer()
                Button {
                    editor = PunchEditorTarget(task: task, index: nil, initial: model.now)
                } label: {
                    Label("补卡", systemImage: "plus")
                }
                .buttonStyle(.borderless)
            }
            if dates.isEmpty {
                Text("今天还没有打卡")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(dates.enumerated()), id: \.offset) { index, date in
                    HStack {
                        Text(Self.timeFormatter.string(from: date))
                            .monospacedDigit()
                        Spacer()
                        Button("改时间") {
                            editor = PunchEditorTarget(task: task, index: index, initial: date)
                        }
                        .buttonStyle(.borderless)
                        Button("删除", role: .destructive) {
                            pendingDeletion = PunchEditorTarget(task: task, index: index, initial: date)
                        }
                        .buttonStyle(.borderless)
                    }
                    .font(.callout)
                }
            }
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}

struct PunchTimeEditor: View {
    @ObservedObject var model: AppModel
    let target: PunchEditorTarget
    @Environment(\.dismiss) private var dismiss
    @State private var time: Date

    init(model: AppModel, target: PunchEditorTarget) {
        self.model = model
        self.target = target
        _time = State(initialValue: target.initial)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(target.isNew ? "补卡 · \(target.task.title)" : "修改时间 · \(target.task.title)")
                .font(.headline)
            DatePicker("打卡时间", selection: $time, displayedComponents: .hourAndMinute)
                .datePickerStyle(.field)
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("保存") {
                    if let index = target.index {
                        model.updatePunch(target.task, index: index, to: time)
                    } else {
                        model.addPunch(target.task, at: time)
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}
