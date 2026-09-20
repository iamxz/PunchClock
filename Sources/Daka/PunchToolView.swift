import SwiftUI
import DakaCore

// MARK: - 补卡 / 改时间 的编辑目标

struct PunchEditorTarget: Identifiable {
    let task: PunchTask
    let index: Int?
    let initial: Date

    var id: String { "\(task.rawValue)-\(index.map(String.init) ?? "new")" }
    var isNew: Bool { index == nil }
}

// MARK: - 打卡统计页

struct PunchToolView: View {
    @ObservedObject var model: AppModel
    @State private var editor: PunchEditorTarget?
    @State private var pendingDeletion: PunchEditorTarget?

    var body: some View {
        VStack(spacing: 16) {
            errorBanner

            TodayPunchCard(
                model: model,
                onAdd: { task in
                    editor = PunchEditorTarget(task: task, index: nil, initial: model.now)
                },
                onEdit: { task, index, date in
                    editor = PunchEditorTarget(task: task, index: index, initial: date)
                },
                onDelete: { task, index, date in
                    pendingDeletion = PunchEditorTarget(task: task, index: index, initial: date)
                }
            )

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

    /// 写盘失败（如权限问题）时给出可复制的错误，并允许手动关闭，避免旧信息长期驻留。
    @ViewBuilder
    private var errorBanner: some View {
        if let error = model.errorMessage {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(error)
                    .font(.callout)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button {
                    model.clearError()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("关闭提示")
            }
            .padding(10)
            .background(Color.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}

// MARK: - 今日打卡卡片

private struct TodayPunchCard: View {
    @ObservedObject var model: AppModel
    let onAdd: (PunchTask) -> Void
    let onEdit: (PunchTask, Int, Date) -> Void
    let onDelete: (PunchTask, Int, Date) -> Void

    private var doneCount: Int {
        (model.record.morningDone ? 1 : 0) + (model.isEveningComplete ? 1 : 0)
    }

    private var allDone: Bool { doneCount == 2 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            VStack(spacing: 0) {
                PunchTaskSection(task: .morning,
                                 dates: model.record.morningPunches,
                                 isDone: model.record.morningDone,
                                 onAdd: onAdd, onEdit: onEdit, onDelete: onDelete)
                Divider().padding(.leading, 50)
                PunchTaskSection(task: .evening,
                                 dates: model.record.eveningPunches,
                                 isDone: model.isEveningComplete,
                                 onAdd: onAdd, onEdit: onEdit, onDelete: onDelete)
            }
            .background(Color(nsColor: .textBackgroundColor).opacity(0.6),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08))
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.record)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("今日打卡").font(.headline)
            statusBadge
            Spacer()
        }
    }

    private var statusBadge: some View {
        let tint: Color = allDone ? .green : .secondary
        return HStack(spacing: 4) {
            Image(systemName: allDone ? "checkmark.seal.fill" : "circle.dashed")
                .font(.system(size: 10, weight: .semibold))
                .symbolEffect(.bounce, value: allDone)
            Text(statusText)
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(tint.opacity(allDone ? 0.14 : 0.10), in: Capsule())
    }

    private var statusText: String {
        if allDone { return "今日已完成" }
        return doneCount == 0 ? "今日待打卡" : "已完成 \(doneCount)/2"
    }
}

// MARK: - 单个任务（上班 / 下班）

private struct PunchTaskSection: View {
    let task: PunchTask
    let dates: [Date]
    let isDone: Bool
    let onAdd: (PunchTask) -> Void
    let onEdit: (PunchTask, Int, Date) -> Void
    let onDelete: (PunchTask, Int, Date) -> Void

    private var tint: Color { task == .morning ? .orange : .indigo }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                iconBadge

                VStack(alignment: .leading, spacing: 1) {
                    Text(task.title)
                        .font(.callout.weight(.semibold))
                    Text(isDone ? "已完成" : "今天还没有打卡")
                        .font(.caption)
                        .foregroundStyle(isDone ? AnyShapeStyle(Color.green) : AnyShapeStyle(.secondary))
                }

                Spacer(minLength: 12)

                if !dates.isEmpty {
                    Button {
                        onAdd(task)
                    } label: {
                        Label("补卡", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("补一条\(task.title)记录")
                }
            }

            if dates.isEmpty {
                emptyAction
                    .padding(.leading, 40)
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(dates.enumerated()), id: \.element) { index, date in
                        PunchRecordRow(index: index,
                                       date: date,
                                       tint: tint,
                                       onEdit: { onEdit(task, index, date) },
                                       onDelete: { onDelete(task, index, date) })
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.92, anchor: .top).combined(with: .opacity),
                            removal: .opacity.combined(with: .move(edge: .leading))))
                    }
                }
                .padding(.leading, 40)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
    }

    private var iconBadge: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.15))
                .frame(width: 30, height: 30)
            Image(systemName: task == .morning ? "sunrise.fill" : "sunset.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(tint)
                .symbolEffect(.bounce, value: isDone)
        }
        .accessibilityHidden(true)
    }

    /// 空状态的「补卡」投放区：整行可点，比一句灰色文字直观得多。
    private var emptyAction: some View {
        Button {
            onAdd(task)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 13))
                Text("补卡")
                    .font(.callout.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
        }
        .buttonStyle(DashedActionButtonStyle(tint: tint))
        .help("补一条\(task.title)记录")
    }
}

// MARK: - 单条打卡记录

private struct PunchRecordRow: View {
    let index: Int
    let date: Date
    let tint: Color
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var hovering = false
    @State private var deleteHovering = false

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "clock")
                    .font(.system(size: 10, weight: .semibold))
                Text(Self.timeFormatter.string(from: date))
                    .font(.callout.weight(.medium))
                    .monospacedDigit()
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12), in: Capsule())

            Spacer(minLength: 8)

            Button {
                onEdit()
            } label: {
                Label("改时间", systemImage: "clock.arrow.circlepath")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("修改这条记录的时间")

            Button {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(deleteHovering ? .red : nil)
            .foregroundStyle(deleteHovering ? AnyShapeStyle(Color.red) : AnyShapeStyle(.secondary))
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.15)) { deleteHovering = hovering }
            }
            .help("删除这条打卡记录")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.primary.opacity(hovering ? 0.05 : 0),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .animation(.easeOut(duration: 0.15), value: hovering)
        .onHover { hovering = $0 }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}

// MARK: - 空状态按钮样式（虚线框 + 悬停高亮 + 按压回弹）

private struct DashedActionButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        DashedActionButtonBody(configuration: configuration, tint: tint)
    }
}

private struct DashedActionButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let tint: Color

    @State private var hovering = false

    var body: some View {
        configuration.label
            .foregroundStyle(hovering ? AnyShapeStyle(tint) : AnyShapeStyle(.secondary))
            .background(tint.opacity(hovering ? 0.12 : 0.05),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(tint.opacity(hovering ? 0.75 : 0.35),
                                  style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
            }
            .scaleEffect(configuration.isPressed ? 0.978 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.7),
                       value: configuration.isPressed)
            .animation(.easeOut(duration: 0.18), value: hovering)
            .onHover { hovering = $0 }
    }
}

// MARK: - 补卡 / 改时间 弹窗

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

    /// 合格下班卡的下限时刻（上班卡 + 工作时长）。
    private var eveningThreshold: Date? {
        model.eveningThreshold(on: model.now)
    }

    private var eveningQualified: Bool {
        guard target.task == .evening, let threshold = eveningThreshold else { return true }
        return time >= threshold
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: target.task == .morning ? "sunrise.fill" : "sunset.fill")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(tint)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(target.isNew ? "补卡" : "修改时间")
                        .font(.headline)
                    Text(target.task.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            DatePicker("打卡时间", selection: $time, displayedComponents: .hourAndMinute)
                .datePickerStyle(.field)

            if target.task == .evening, let threshold = eveningThreshold {
                if eveningQualified {
                    Label("计入当天考勤（下班需不早于 \(Self.timeText(threshold))）",
                          systemImage: "checkmark.seal")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("这条下班卡不计入当天考勤", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.orange)
                        Text("上班卡 \(Self.timeText(threshold.addingTimeInterval(-model.settings.workDuration))) + 工作时长 \(Self.hoursText(model.settings.workDuration)) → 下班需不早于 \(Self.timeText(threshold))；当前选择 \(Self.timeText(time))。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("改为 \(Self.timeText(Self.roundedUpToMinute(threshold).addingTimeInterval(60)))") {
                            time = Self.roundedUpToMinute(threshold).addingTimeInterval(60)
                        }
                        .controlSize(.small)
                    }
                    .padding(10)
                    .frame(maxWidth: 300, alignment: .leading)
                    .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                }
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(target.isNew ? "补卡" : "保存") {
                    if let index = target.index {
                        model.updatePunch(target.task, index: index, to: time)
                    } else {
                        model.addPunch(target.task, at: time)
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private var tint: Color { target.task == .morning ? .orange : .indigo }

    private static func roundedUpToMinute(_ date: Date) -> Date {
        let calendar = Calendar.current
        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return calendar.date(from: comps) ?? date
    }

    private static func timeText(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    private static func hoursText(_ interval: TimeInterval) -> String {
        let hours = interval / 3600
        return hours == hours.rounded() ? "\(Int(hours)) 小时" : String(format: "%.1f 小时", hours)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}
