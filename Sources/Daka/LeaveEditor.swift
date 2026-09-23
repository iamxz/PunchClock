import SwiftUI
import DakaCore

/// 请假编辑弹窗的请求：`leave == nil` 为新增，否则编辑这条已有日程。
/// `date` 是右键点中的那一天，用于新增时给出「全天」默认值。
struct LeaveEditRequest: Identifiable {
    let date: Date
    let leave: LeaveRecord?

    var id: String { leave.map { $0.id.uuidString } ?? DakaDate.key(for: date) }
}

/// 新增 / 编辑一段请假：起止精确到分钟，可以只请当天几小时，也可以一次跨多天。
struct LeaveEditor: View {
    @ObservedObject var model: AppModel
    let request: LeaveEditRequest

    @Environment(\.dismiss) private var dismiss
    @State private var start: Date
    @State private var end: Date
    @State private var label: String

    private let calendar = Calendar.current

    init(model: AppModel, request: LeaveEditRequest) {
        self.model = model
        self.request = request

        let settings = model.settings
        let calendar = Calendar.current
        if let leave = request.leave {
            _start = State(initialValue: leave.start)
            _end = State(initialValue: leave.end)
            _label = State(initialValue: leave.label ?? "")
        } else {
            // 默认「当天整个应上班窗口」：不想改就是整天请假，一次点击即可。
            let day = request.date
            let anchor = DakaDate.date(on: day, at: settings.workStartTime, calendar: calendar)
                ?? calendar.startOfDay(for: day)
            _start = State(initialValue: anchor)
            _end = State(initialValue: anchor.addingTimeInterval(settings.workDuration))
            _label = State(initialValue: "")
        }
    }

    private var isValid: Bool { end > start }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(request.leave == nil ? "新增请假" : "编辑请假")
                    .font(.headline)
                Text("请假时长会抵扣当天的应上班时长，打卡加请假凑满即算正常。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                picker("开始", selection: $start)
                picker("结束", selection: $end)
                TextField("备注（可选）", text: $label)
                    .textFieldStyle(.roundedBorder)
            }

            notes

            HStack {
                Text("跨天的请假是一条整体，取消时会整条撤销")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("保存") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
        }
        .padding(20)
        .frame(width: 400)
    }

    private func picker(_ title: String, selection: Binding<Date>) -> some View {
        HStack(spacing: 10) {
            Text(title).frame(width: 36, alignment: .leading)
            DatePicker("", selection: selection, displayedComponents: [.date, .hourAndMinute])
                .labelsHidden()
                .datePickerStyle(.compact)
        }
    }

    // MARK: - 提示

    @ViewBuilder
    private var notes: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !isValid {
                Label("结束时间需晚于开始时间", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
            }
            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(captions.enumerated()), id: \.offset) { _, text in
                Label(text, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var captions: [String] {
        guard isValid else { return [] }
        var items: [String] = []

        let days = LeaveRules.naturalDays(of: candidate, calendar: calendar)
        if days > 1 { items.append("覆盖 \(days) 个自然日") }
        if let summary = deductionSummary { items.append(summary) }
        if restDays > 0 {
            items.append("其中 \(restDays) 天不是工作日，不计入请假统计")
        }
        if overlapsExisting { items.append("与其他请假重叠的部分不会重复计入") }
        return items
    }

    /// 「折算 2 小时 · 约 0.5 天」：与统计同一条算法，只算工作日、按应上班窗口裁剪。
    private var deductionSummary: String? {
        let (seconds, days) = deduction
        guard seconds > 0 else { return nil }
        return "折算 \(Self.hoursText(seconds)) · 约 \(Statistics.leaveDaysText(days)) 天"
    }

    /// 候选日程在应上班窗口内的实际抵扣：只统计工作日，口径与 `Statistics.leaveDays` 一致。
    private var deduction: (seconds: TimeInterval, days: Double) {
        var seconds: TimeInterval = 0
        var days: Double = 0
        for day in workDays {
            seconds += AttendanceRule.leaveDuration(model.settings, on: day,
                                                    leaves: [candidate], calendar: calendar)
            days += AttendanceRule.leaveFraction(model.settings, on: day,
                                                 leaves: [candidate], calendar: calendar)
        }
        return (seconds, days)
    }

    private var affectedDays: [Date] {
        guard isValid else { return [] }
        var result: [Date] = []
        var day = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end.addingTimeInterval(-1))
        while day <= last {
            result.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }

    private var workDays: [Date] {
        affectedDays.filter { model.settings.isWorkday($0, calendar: calendar) }
    }

    /// 落在周末/节假日的那几天。
    private var restDays: Int { affectedDays.count - workDays.count }

    private var overlapsExisting: Bool {
        model.leaves.contains { other in
            other.id != candidate.id && LeaveRules.overlap((candidate.start, candidate.end),
                                                           (other.start, other.end)) > 0
        }
    }

    private var candidate: LeaveRecord {
        if var leave = request.leave {
            leave.start = start
            leave.end = end
            leave.label = note
            return leave
        }
        return LeaveRecord(start: start, end: end, label: note)
    }

    private var note: String? {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func save() {
        let saved: Bool
        if let leave = request.leave {
            saved = model.updateLeave(id: leave.id, from: start, to: end, label: note)
        } else {
            saved = model.addLeave(from: start, to: end, label: note)
        }
        if saved { dismiss() }
    }

    private static func hoursText(_ interval: TimeInterval) -> String {
        let hours = interval / 3600
        return hours == hours.rounded() ? "\(Int(hours)) 小时" : String(format: "%.1f 小时", hours)
    }
}
