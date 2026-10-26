import SwiftUI
import Charts
import DakaCore

/// 补卡 / 改时间请求：针对某一天补齐缺失记录，或修正已有记录的时刻。
struct MakeUpPunchRequest: Identifiable {
    let dateKey: String
    let date: Date
    /// 该天仍缺失的打卡任务（上班 / 下班）。
    let missing: [PunchTask]
    /// 该天已有的上班卡（最早一条），及它在记录数组里的下标。
    let existingMorning: Date?
    let existingMorningIndex: Int?
    /// 该天已有的下班卡（最晚一条），及它在记录数组里的下标。
    let existingEvening: Date?
    let existingEveningIndex: Int?
    /// 同一任务是否存了多条记录（弹窗会说明这里改的是哪一条）。
    let hasMultiplePunches: Bool

    var id: String { dateKey }

    var hasExisting: Bool { existingMorning != nil || existingEvening != nil }
    var hasMissing: Bool { !missing.isEmpty }

    var title: String { Self.dayFormatter.string(from: date) }

    /// 弹窗标题：只有缺失时是补卡，已有记录时说明还能改时间。
    var editorTitle: String {
        if hasExisting && hasMissing { return "补卡 / 改时间" }
        return hasMissing ? "补卡（遗漏）" : "改时间"
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy 年 M 月 d 日 EEEE"
        return f
    }()
}

struct StatisticsView: View {
    @ObservedObject var model: AppModel
    @State private var displayedMonth: Date
    @State private var makeUpRequest: MakeUpPunchRequest?
    @State private var leaveRequest: LeaveEditRequest?
    @State private var pendingClear: AttendanceDayCell?
    /// 走势图的时间范围（天）。
    @State private var chartRangeDays = 14

    init(model: AppModel) {
        self._model = ObservedObject(wrappedValue: model)
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.year, .month], from: model.now)) ?? model.now
        self._displayedMonth = State(initialValue: start)
    }

    /// 当前展示月份的考勤网格（统计区间：该月 1 号 ~ 月末）。
    private var grid: MonthGrid {
        model.attendanceMonthGrid(month: displayedMonth)
    }

    private var punchDays: Int {
        grid.weeks.joined().compactMap { $0 }.filter { $0.status == .done }.count
    }

    private var missedDays: Int {
        grid.weeks.joined().compactMap { $0 }.filter { $0.status == .missed }.count
    }

    /// 本月迟到次数。只有会判迟到的弹性方式才显示这张卡。
    private var lateDays: Int {
        grid.weeks.joined().compactMap { $0 }.filter { $0.isLate }.count
    }

    private var averageWorkDuration: TimeInterval? {
        let durations = grid.weeks.joined().compactMap { $0 }.compactMap(\.workDuration)
        return durations.isEmpty ? nil : durations.reduce(0, +) / Double(durations.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                metricCard("本月打卡", "\(punchDays) 天", "checkmark.circle")
                metricCard("连续打卡", "\(model.currentStreak) 天", "flame")
                metricCard("平均上班", averageText, "clock")
                if model.settings.recordsLateArrival {
                    metricCard("本月迟到", "\(lateDays) 次", "calendar.badge.exclamationmark")
                }
                metricCard("缺卡", "\(missedDays) 天", "exclamationmark.triangle")
                metricCard("本月请假", Statistics.leaveDaysText(model.monthLeaveDays(month: displayedMonth)) + " 天", "figure.walk")
            }

            CalendarView(displayedMonth: $displayedMonth,
                         records: model.records,
                         settings: model.settings,
                         leaves: model.leaves,
                         now: model.now,
                         onAddLeave: { leaveRequest = LeaveEditRequest(date: $0.date, leave: nil) },
                         onEditLeave: { cell, leave in
                             leaveRequest = LeaveEditRequest(date: cell.date, leave: leave)
                         },
                         onCancelLeave: { cancelLeave($0) },
                         onEditPunches: { makeUpRequest = makeUpRequest(for: $0) },
                         onClearPunches: { pendingClear = $0 })
            .animation(.spring(response: 0.32, dampingFraction: 0.85), value: model.records)
            .animation(.spring(response: 0.32, dampingFraction: 0.85), value: model.leaves)

            workDurationChart
        }
        .sheet(item: $makeUpRequest) { request in
            MakeUpPunchEditor(model: model, request: request)
        }
        .sheet(item: $leaveRequest) { request in
            LeaveEditor(model: model, request: request)
        }
        .confirmationDialog("清除该天的全部打卡记录？",
                            isPresented: clearBinding,
                            titleVisibility: .visible) {
            Button("清除", role: .destructive) {
                if let day = pendingClear?.date {
                    model.clearPunches(on: day)
                }
                pendingClear = nil
            }
            Button("取消", role: .cancel) { pendingClear = nil }
        } message: {
            if let cell = pendingClear {
                Text("\(cell.dateKey) 的上班与下班记录都会被删除，不可撤销。")
            }
        }
    }

    private var clearBinding: Binding<Bool> {
        Binding(get: { pendingClear != nil },
                set: { if !$0 { pendingClear = nil } })
    }

    // MARK: - 日历右键动作

    /// 取消与这天相连的请假：跨天日程整条撤销，一次点完。
    private func cancelLeave(_ cell: AttendanceDayCell) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
            model.removeLeaves(on: cell.date)
        }
    }

    private func makeUpRequest(for cell: AttendanceDayCell) -> MakeUpPunchRequest {
        let record = model.records[cell.dateKey] ?? DayRecord()
        var missing: [PunchTask] = []
        if !record.morningDone { missing.append(.morning) }
        if !AttendanceRule.isEveningComplete(record, settings: model.settings, on: cell.date,
                                             leaves: model.leaves) {
            missing.append(.evening)
        }

        // 日历只展示最早的上班卡与最晚的下班卡，改时间也改这两条。
        let morning = record.morningDoneAt
        let evening = record.eveningPunches.max()

        return MakeUpPunchRequest(dateKey: cell.dateKey,
                                  date: cell.date,
                                  missing: missing,
                                  existingMorning: morning,
                                  existingMorningIndex: morning.flatMap { record.morningPunches.firstIndex(of: $0) },
                                  existingEvening: evening,
                                  existingEveningIndex: evening.flatMap { record.eveningPunches.firstIndex(of: $0) },
                                  hasMultiplePunches: record.morningPunches.count > 1
                                      || record.eveningPunches.count > 1)
    }

    private var averageText: String {
        guard let average = averageWorkDuration else { return "—" }
        let hours = Int(average) / 3600
        let minutes = (Int(average) % 3600) / 60
        return "\(hours)h\(minutes)m"
    }

    // MARK: - 每日工作时长走势图

    /// 走势图的数据源：按所选范围独立统计（与上方「本月」指标口径不同）。
    private var chartSummary: StatisticsSummary {
        model.statistics(rangeDays: chartRangeDays)
    }

    /// 只保留能算出时长的日期（上下班均达标），缺卡当天不参与连线，避免走势被拉平。
    private var chartDays: [DailyStat] {
        chartSummary.days.filter { $0.workDuration != nil }
    }

    /// Y 轴上限：取实际最大工时向上取整，并保证至少 9 小时，避免柱子顶到边框。
    private var chartMaxHours: Double {
        let peak = chartDays.compactMap { $0.workDuration }.max().map { $0 / 3600 } ?? 0
        return max(9, peak.rounded(.up))
    }

    @ViewBuilder
    private var workDurationChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Label("每日工作时长走势", systemImage: "chart.bar.xaxis")
                    .font(.headline)
                Spacer()
                Picker("范围", selection: $chartRangeDays) {
                    Text("7 天").tag(7)
                    Text("14 天").tag(14)
                    Text("30 天").tag(30)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 200)
                .help("切换走势图的统计范围")
            }

            if chartDays.isEmpty {
                emptyChartPlaceholder
            } else {
                chart
                chartFooter
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 10))
        .animation(.easeOut(duration: 0.22), value: chartRangeDays)
        .animation(.easeOut(duration: 0.22), value: model.records)
    }

    private var chart: some View {
        Chart {
            ForEach(chartDays, id: \.dateKey) { day in
                BarMark(
                    x: .value("日期", Self.axisLabel(day.dateKey)),
                    y: .value("工时", hours(day))
                )
                .foregroundStyle(Color.accentColor.opacity(0.28))
                .cornerRadius(3)

                LineMark(
                    x: .value("日期", Self.axisLabel(day.dateKey)),
                    y: .value("工时", hours(day))
                )
                .foregroundStyle(Color.accentColor)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.catmullRom)
                .symbol(Circle())
                .symbolSize(26)
            }

            if let average = chartSummary.averageWorkDuration {
                RuleMark(y: .value("平均", average / 3600))
                    .foregroundStyle(.secondary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .annotation(position: .top, alignment: .leading, spacing: 2) {
                        Text("平均 \(Self.durationText(average))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .chartYScale(domain: 0...chartMaxHours)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { value in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.15))
                AxisValueLabel {
                    if let hour = value.as(Double.self) {
                        Text("\(Int(hour))h")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: chartRangeDays > 14 ? 6 : 7)) { _ in
                AxisValueLabel()
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: 220)
    }

    private var chartFooter: some View {
        HStack(spacing: 14) {
            HStack(spacing: 5) {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 7, height: 7)
                Text("已完成 \(chartDays.count) 天")
            }
            if let average = chartSummary.averageWorkDuration {
                HStack(spacing: 5) {
                    Image(systemName: "minus")
                        .font(.system(size: 10, weight: .bold))
                    Text("平均 \(Self.durationText(average))")
                }
            }
            Spacer(minLength: 0)
            Text("仅统计上下班均达标的当天")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var emptyChartPlaceholder: some View {
        VStack(spacing: 6) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 22))
                .foregroundStyle(.tertiary)
            Text("最近 \(chartRangeDays) 天还没有完整的打卡记录")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("上下班都达标后，这里会画出每日工作时长走势")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
    }

    private func hours(_ day: DailyStat) -> Double {
        (day.workDuration ?? 0) / 3600
    }

    /// "2026-09-15" → "09-15"
    private static func axisLabel(_ dateKey: String) -> String {
        String(dateKey.suffix(5))
    }

    private static func durationText(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        return "\(hours)h\(minutes)m"
    }

    private func metricCard(_ title: String, _ value: String, _ systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}

// MARK: - 补卡 / 改时间弹窗

struct MakeUpPunchEditor: View {
    @ObservedObject var model: AppModel
    let request: MakeUpPunchRequest

    @Environment(\.dismiss) private var dismiss
    @State private var existingMorningEnabled: Bool
    @State private var existingMorningTime: Date
    @State private var existingEveningEnabled: Bool
    @State private var existingEveningTime: Date
    @State private var morningEnabled: Bool
    @State private var morningTime: Date
    @State private var eveningEnabled: Bool
    @State private var eveningTime: Date
    @State private var feedback: String?

    init(model: AppModel, request: MakeUpPunchRequest) {
        self.model = model
        self.request = request

        let calendar = Calendar.current
        let settings = model.settings
        let fallback = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: request.date) ?? request.date
        let morning = DakaDate.date(on: request.date, at: settings.workStartTime, calendar: calendar) ?? fallback

        // 下班卡必须不早于「上班卡 + 扣除当天请假后仍需工作的时长」；
        // 优先按已存在的上班卡推算，否则按即将补的上班卡推算。
        let referenceMorning = request.existingMorning ?? morning
        let threshold = Self.eveningThreshold(model: model, request: request, morning: referenceMorning)
            ?? referenceMorning.addingTimeInterval(settings.workDuration)
        let qualifyingEvening = Self.roundedUpToMinute(threshold).addingTimeInterval(60)

        _existingMorningEnabled = State(initialValue: false)
        _existingMorningTime = State(initialValue: request.existingMorning ?? morning)
        _existingEveningEnabled = State(initialValue: false)
        _existingEveningTime = State(initialValue: request.existingEvening ?? qualifyingEvening)
        _morningEnabled = State(initialValue: request.missing.contains(.morning))
        _morningTime = State(initialValue: morning)
        _eveningEnabled = State(initialValue: request.missing.contains(.evening))
        _eveningTime = State(initialValue: qualifyingEvening)
    }

    /// 保存后这一天的上班卡（取最早一条）。
    private var resultingMorning: Date? {
        var candidates: [Date] = []
        if let existing = request.existingMorning {
            candidates.append(existingMorningEnabled ? existingMorningTime : existing)
        }
        if request.missing.contains(.morning), morningEnabled {
            candidates.append(morningTime)
        }
        return candidates.min()
    }

    /// 保存后这一天的下班卡（取最晚一条）。
    private var resultingEvening: Date? {
        var candidates: [Date] = []
        if let existing = request.existingEvening {
            candidates.append(existingEveningEnabled ? existingEveningTime : existing)
        }
        if request.missing.contains(.evening), eveningEnabled {
            candidates.append(eveningTime)
        }
        return candidates.max()
    }

    /// 合格下班卡的下限时刻（依据保存后的上班卡推算）。
    private var eveningThreshold: Date? {
        guard let morning = resultingMorning else { return nil }
        return Self.eveningThreshold(model: model, request: request, morning: morning)
    }

    /// 该天的合格下班卡下限：直接复用考勤规则，避免弹窗与日历各算一套。
    private static func eveningThreshold(model: AppModel,
                                         request: MakeUpPunchRequest,
                                         morning: Date) -> Date? {
        var probe = model.records[request.dateKey] ?? DayRecord()
        probe.morningPunches = [morning]
        return AttendanceRule.expectedLeave(probe, settings: model.settings, on: request.date,
                                            leaves: model.leaves)
    }

    private var hasSelection: Bool {
        existingMorningEnabled || existingEveningEnabled
            || (request.missing.contains(.morning) && morningEnabled)
            || (request.missing.contains(.evening) && eveningEnabled)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(request.editorTitle)
                    .font(.headline)
                Text(request.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if request.hasMultiplePunches {
                Label("同一天有多条打卡时，这里改的是最早的上班卡、最晚的下班卡。",
                      systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                if request.hasExisting {
                    sectionTitle("已有记录 · 勾选后可改时间")
                    if let existing = request.existingMorning {
                        row(task: .morning, isOn: $existingMorningEnabled,
                            time: $existingMorningTime, note: "原 \(Self.timeText(existing))")
                    }
                    if let existing = request.existingEvening {
                        row(task: .evening, isOn: $existingEveningEnabled,
                            time: $existingEveningTime, note: "原 \(Self.timeText(existing))")
                    }
                }

                if request.hasMissing {
                    if request.hasExisting { sectionTitle("补卡（遗漏）") }
                    if request.missing.contains(.morning) {
                        row(task: .morning, isOn: $morningEnabled, time: $morningTime, note: nil)
                    }
                    if request.missing.contains(.evening) {
                        row(task: .evening, isOn: $eveningEnabled, time: $eveningTime, note: nil)
                    }
                }
            }

            qualificationNotice

            if let feedback {
                Label(feedback, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            HStack {
                Text(request.hasExisting ? "只写入勾选的项目，未勾选的已有记录保持不变" : "只新增勾选的记录")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(request.hasExisting ? "保存" : "补卡") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!hasSelection)
            }
        }
        .padding(20)
        .frame(width: 400)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
    }

    /// 「这条下班卡到底算不算」的显式提示 —— 这是补卡 / 改时间最容易踩的坑。
    @ViewBuilder
    private var qualificationNotice: some View {
        if hasSelection, let evening = resultingEvening, let morning = resultingMorning,
           let threshold = eveningThreshold {
            if evening >= threshold {
                Label("下班卡 \(Self.timeText(evening)) 计入当天考勤（需不早于 \(Self.timeText(threshold))）",
                      systemImage: "checkmark.seal")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Label("下班卡 \(Self.timeText(evening)) 不计入当天考勤",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                    Text("上班卡 \(Self.timeText(morning)) + 应工作 \(Self.hoursText(threshold.timeIntervalSince(morning))) → 下班需不早于 \(Self.timeText(threshold))；当前 \(Self.timeText(evening))。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("改为 \(Self.timeText(Self.roundedUpToMinute(threshold).addingTimeInterval(60)))") {
                        adoptQualifyingEvening()
                    }
                    .controlSize(.small)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    /// 一键把下班卡调到合格时刻：优先改已有记录，没有才补一条新的。
    private func adoptQualifyingEvening() {
        guard let threshold = eveningThreshold else { return }
        let fixed = Self.roundedUpToMinute(threshold).addingTimeInterval(60)
        if request.existingEvening != nil {
            existingEveningEnabled = true
            existingEveningTime = fixed
            eveningEnabled = false
        } else if request.missing.contains(.evening) {
            eveningEnabled = true
            eveningTime = fixed
        }
    }

    private func row(task: PunchTask,
                     isOn: Binding<Bool>,
                     time: Binding<Date>,
                     note: String?) -> some View {
        HStack(spacing: 10) {
            Toggle(isOn: isOn) {
                VStack(alignment: .leading, spacing: 1) {
                    Label(task.title, systemImage: task == .morning ? "sunrise.fill" : "sunset.fill")
                    if let note {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .toggleStyle(.checkbox)

            Spacer(minLength: 8)

            DatePicker("", selection: time, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .disabled(!isOn.wrappedValue)
                .opacity(isOn.wrappedValue ? 1 : 0.45)
        }
        .animation(.easeOut(duration: 0.15), value: isOn.wrappedValue)
    }

    private func save() {
        var written = 0
        var skipped = 0

        if let index = request.existingMorningIndex, existingMorningEnabled {
            model.updatePunch(.morning, index: index, to: existingMorningTime, on: request.date)
            written += 1
        }
        if let index = request.existingEveningIndex, existingEveningEnabled {
            model.updatePunch(.evening, index: index, to: existingEveningTime, on: request.date)
            written += 1
        }
        if request.missing.contains(.morning), morningEnabled {
            model.addPunch(.morning, at: morningTime) ? (written += 1) : (skipped += 1)
        }
        if request.missing.contains(.evening), eveningEnabled {
            model.addPunch(.evening, at: eveningTime) ? (written += 1) : (skipped += 1)
        }

        if let error = model.errorMessage {
            feedback = error
            return
        }
        if skipped > 0 && written == 0 {
            feedback = "同一分钟内已有记录，未重复写入"
            return
        }
        dismiss()
    }

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
