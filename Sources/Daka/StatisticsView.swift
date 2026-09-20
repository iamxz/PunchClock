import SwiftUI
import Charts
import DakaCore

/// 补卡（遗漏）请求：针对某一天补齐缺失的打卡记录。
struct MakeUpPunchRequest: Identifiable {
    let dateKey: String
    let date: Date
    /// 该天仍缺失的打卡任务（上班 / 下班）。
    let missing: [PunchTask]
    /// 该天已有记录的摘要，用于弹窗提示。
    let existing: [String]
    /// 该天已有的上班卡（决定「合格下班卡」的下限时刻）。
    let existingMorning: Date?

    var id: String { dateKey }

    var title: String { Self.dayFormatter.string(from: date) }

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

    private var averageWorkDuration: TimeInterval? {
        let durations = grid.weeks.joined().compactMap { $0 }
            .filter { $0.status == .done }
            .compactMap { cell -> TimeInterval? in
                guard let m = cell.morningDoneAt, let e = cell.eveningDoneAt, e >= m else { return nil }
                return e.timeIntervalSince(m)
            }
        return durations.isEmpty ? nil : durations.reduce(0, +) / Double(durations.count)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    metricCard("本月打卡", "\(punchDays) 天", "checkmark.circle")
                    metricCard("连续打卡", "\(model.currentStreak) 天", "flame")
                    metricCard("平均上班", averageText, "clock")
                    metricCard("缺卡", "\(missedDays) 天", "exclamationmark.triangle")
                }

                CalendarView(displayedMonth: $displayedMonth,
                             records: model.records,
                             settings: model.settings,
                             now: model.now,
                             onToggleLeave: toggleLeave,
                             onMakeUp: { makeUpRequest = makeUpRequest(for: $0) },
                             onClearPunches: { pendingClear = $0 })
                .animation(.spring(response: 0.32, dampingFraction: 0.85), value: model.records)

                workDurationChart
            }
        }
        .overlayScrollers()
        .sheet(item: $makeUpRequest) { request in
            MakeUpPunchEditor(model: model, request: request)
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

    private func toggleLeave(_ cell: AttendanceDayCell) {
        let leave = cell.status != .leave
        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
            model.setSkipped(leave, on: cell.date)
        }
    }

    private func makeUpRequest(for cell: AttendanceDayCell) -> MakeUpPunchRequest {
        let record = model.records[cell.dateKey] ?? DayRecord()
        var missing: [PunchTask] = []
        if !record.morningDone { missing.append(.morning) }
        if !AttendanceRule.isEveningComplete(record, settings: model.settings, on: cell.date) {
            missing.append(.evening)
        }

        var existing: [String] = []
        if let morning = record.morningDoneAt {
            existing.append("上班 \(Self.timeFormatter.string(from: morning))")
        }
        for evening in record.eveningPunches {
            existing.append("下班 \(Self.timeFormatter.string(from: evening))")
        }

        return MakeUpPunchRequest(dateKey: cell.dateKey,
                                  date: cell.date,
                                  missing: missing,
                                  existing: existing,
                                  existingMorning: record.morningDoneAt)
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

// MARK: - 补卡（遗漏）弹窗

struct MakeUpPunchEditor: View {
    @ObservedObject var model: AppModel
    let request: MakeUpPunchRequest

    @Environment(\.dismiss) private var dismiss
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

        // 下班卡必须不早于「上班卡 + 工作时长」；优先按已存在的上班卡推算，否则按即将补的上班卡推算。
        let referenceMorning = request.existingMorning ?? morning
        let threshold = referenceMorning.addingTimeInterval(settings.workDuration)
        let qualifyingEvening = Self.roundedUpToMinute(threshold).addingTimeInterval(60)

        _morningEnabled = State(initialValue: request.missing.contains(.morning))
        _eveningEnabled = State(initialValue: request.missing.contains(.evening))
        _morningTime = State(initialValue: morning)
        _eveningTime = State(initialValue: qualifyingEvening)
    }

    /// 合格下班卡的下限时刻（依据实际上班卡推算）。
    private var eveningThreshold: Date? {
        let morning = request.existingMorning
            ?? (request.missing.contains(.morning) && morningEnabled ? morningTime : nil)
        guard let morning else { return nil }
        return morning.addingTimeInterval(model.settings.workDuration)
    }

    private var eveningQualified: Bool {
        guard eveningEnabled, let threshold = eveningThreshold else { return true }
        return eveningTime >= threshold
    }

    private var hasSelection: Bool {
        (request.missing.contains(.morning) && morningEnabled)
            || (request.missing.contains(.evening) && eveningEnabled)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("补卡（遗漏）")
                    .font(.headline)
                Text(request.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !request.existing.isEmpty {
                Label("该天已有：" + request.existing.joined(separator: "、"),
                      systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                if request.missing.contains(.morning) {
                    row(task: .morning, isOn: $morningEnabled, time: $morningTime)
                }
                if request.missing.contains(.evening) {
                    row(task: .evening, isOn: $eveningEnabled, time: $eveningTime)
                }
            }

            qualificationNotice

            if let feedback {
                Label(feedback, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            HStack {
                Text("只新增勾选的记录，不覆盖已有打卡")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("补卡") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!hasSelection)
            }
        }
        .padding(20)
        .frame(width: 400)
    }

    /// 「这条下班卡到底算不算」的显式提示 —— 这是补卡最容易踩的坑。
    @ViewBuilder
    private var qualificationNotice: some View {
        if request.missing.contains(.evening), eveningEnabled, let threshold = eveningThreshold {
            if eveningQualified {
                Label("下班卡 \(Self.timeText(eveningTime)) 计入当天考勤（需不早于 \(Self.timeText(threshold))）",
                      systemImage: "checkmark.seal")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Label("这条下班卡不计入当天考勤",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                    Text("上班卡 \(Self.timeText(threshold.addingTimeInterval(-model.settings.workDuration))) + 工作时长 \(Self.hoursText(model.settings.workDuration)) → 下班需不早于 \(Self.timeText(threshold))；当前选择 \(Self.timeText(eveningTime))。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("改为 \(Self.timeText(Self.roundedUpToMinute(threshold).addingTimeInterval(60)))") {
                        eveningTime = Self.roundedUpToMinute(threshold).addingTimeInterval(60)
                    }
                    .controlSize(.small)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func row(task: PunchTask, isOn: Binding<Bool>, time: Binding<Date>) -> some View {
        HStack(spacing: 10) {
            Toggle(isOn: isOn) {
                Label(task.title, systemImage: task == .morning ? "sunrise.fill" : "sunset.fill")
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
