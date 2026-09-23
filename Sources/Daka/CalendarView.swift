import SwiftUI
import DakaCore

/// 考勤日历公共组件：以「月」为统计维度（每月 1 号 ~ 月末），
/// 在日历格中标注每日打卡状态、请假与节假日。
///
/// 状态标记：
/// - 已打卡（done）：绿色对号 ✓ + 打卡时间
/// - 应打卡未打卡（missed）：红色感叹号 !
/// - 待打卡（pending）：蓝色圆点（仅今天、窗口未过时）
/// - 非工作日 / 未来（none）：无标记
///
/// 请假：无论半天还是整天，统一在日期下方标紫色「假」，具体时段看 tooltip。
/// 节假日标记：法定假日显示节日名（红）、调休补班显示名称（橙）、手动覆盖显示「手动」（蓝）。
///
/// 右键可执行：新增/编辑/取消请假、补卡（遗漏）、清除该天记录。
public struct CalendarView: View {
    @Binding var displayedMonth: Date
    let records: [String: DayRecord]
    let settings: DakaCore.Settings
    let leaves: [LeaveRecord]
    let now: Date
    var calendar: Calendar = .current
    var onSelectDay: ((AttendanceDayCell) -> Void)?
    var onAddLeave: ((AttendanceDayCell) -> Void)?
    var onEditLeave: ((AttendanceDayCell, LeaveRecord) -> Void)?
    var onCancelLeave: ((AttendanceDayCell) -> Void)?
    var onMakeUp: ((AttendanceDayCell) -> Void)?
    var onClearPunches: ((AttendanceDayCell) -> Void)?

    public init(displayedMonth: Binding<Date>,
                records: [String: DayRecord],
                settings: DakaCore.Settings,
                leaves: [LeaveRecord],
                now: Date,
                calendar: Calendar = .current,
                onSelectDay: ((AttendanceDayCell) -> Void)? = nil,
                onAddLeave: ((AttendanceDayCell) -> Void)? = nil,
                onEditLeave: ((AttendanceDayCell, LeaveRecord) -> Void)? = nil,
                onCancelLeave: ((AttendanceDayCell) -> Void)? = nil,
                onMakeUp: ((AttendanceDayCell) -> Void)? = nil,
                onClearPunches: ((AttendanceDayCell) -> Void)? = nil) {
        self._displayedMonth = displayedMonth
        self.records = records
        self.settings = settings
        self.leaves = leaves
        self.now = now
        self.calendar = calendar
        self.onSelectDay = onSelectDay
        self.onAddLeave = onAddLeave
        self.onEditLeave = onEditLeave
        self.onCancelLeave = onCancelLeave
        self.onMakeUp = onMakeUp
        self.onClearPunches = onClearPunches
    }

    private var grid: MonthGrid {
        AttendanceCalendar.monthGrid(records: records, settings: settings, leaves: leaves,
                                     month: displayedMonth, now: now, calendar: calendar)
    }

    private var canGoNext: Bool {
        let current = calendar.dateComponents([.year, .month], from: now)
        let shown = calendar.dateComponents([.year, .month], from: displayedMonth)
        return (shown.year ?? 0, shown.month ?? 0) < (current.year ?? 0, current.month ?? 0)
    }

    private static let weekdayHeaders = ["日", "一", "二", "三", "四", "五", "六"]

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            weekdayHeader
            gridBody
            legend
            hint
        }
    }

    private var header: some View {
        HStack {
            Button {
                shiftMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            .help("上个月")

            Text(String(format: "%04d 年 %02d 月", grid.year, grid.month))
                .font(.headline)
                .frame(minWidth: 140, alignment: .center)

            Button {
                shiftMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
            .help("下个月")
            .disabled(!canGoNext)
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(Self.weekdayHeaders, id: \.self) { title in
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var gridBody: some View {
        VStack(spacing: 6) {
            ForEach(Array(grid.weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 6) {
                    ForEach(0..<7, id: \.self) { col in
                        cell(for: week[col])
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cell(for item: AttendanceDayCell?) -> some View {
        if let item {
            dayButton(item).contextMenu { menu(for: item) }
        } else {
            Color.clear.frame(minHeight: 68)
        }
    }

    private func dayButton(_ item: AttendanceDayCell) -> some View {
        Button {
            onSelectDay?(item)
        } label: {
            DayCellContent(cell: item,
                           dayType: settings.dayType(item.date, calendar: calendar))
        }
        .buttonStyle(.plain)
        .help(helpText(for: item))
    }

    /// 右侧菜单：请假（新增 / 编辑 / 取消）、补卡（遗漏）、清除该天记录。
    @ViewBuilder
    private func menu(for item: AttendanceDayCell) -> some View {
        let onThisDay = LeaveRules.records(intersecting: item.date, in: leaves, calendar: calendar)
        if onThisDay.isEmpty {
            Button {
                onAddLeave?(item)
            } label: {
                Label("新增请假…", systemImage: "calendar.badge.plus")
            }
        } else {
            ForEach(onThisDay) { leave in
                Button {
                    onEditLeave?(item, leave)
                } label: {
                    Label("编辑请假 \(Self.rangeText(leave, calendar: calendar))", systemImage: "pencil")
                }
            }
            Button(role: .destructive) {
                onCancelLeave?(item)
            } label: {
                Label(cancelTitle(for: onThisDay), systemImage: "trash")
            }
            .help("与这天相连的请假日程会整条撤销，包括跨天的部分")
        }

        if !item.isFuture, canMakeUp(item) {
            Button {
                onMakeUp?(item)
            } label: {
                Label("补卡（遗漏）…", systemImage: "plus.circle")
            }
        }

        if hasPunches(item) {
            Divider()
            Button(role: .destructive) {
                onClearPunches?(item)
            } label: {
                Label("清除该天记录", systemImage: "trash")
            }
        }
    }

    /// 取消动作会把与这天相连的请假整条删掉，跨多条/跨天时必须先把范围写在标题上。
    private func cancelTitle(for records: [LeaveRecord]) -> String {
        guard records.count == 1, let only = records.first else {
            return "取消请假（\(records.count) 条）"
        }
        let days = LeaveRules.naturalDays(of: only, calendar: calendar)
        return days > 1 ? "取消请假（共 \(days) 天）" : "取消请假"
    }

    private func canMakeUp(_ item: AttendanceDayCell) -> Bool {
        guard item.status != .leave else { return false }
        return !(item.morningDoneAt != nil && item.eveningDoneAt != nil)
    }

    private func hasPunches(_ item: AttendanceDayCell) -> Bool {
        guard let record = records[item.dateKey] else { return false }
        return !record.morningPunches.isEmpty || !record.eveningPunches.isEmpty
    }

    private var legend: some View {
        HStack(spacing: 12) {
            LegendItem(color: .green, icon: "checkmark.circle.fill", text: "已打卡")
            LegendItem(color: .red, icon: "exclamationmark.circle.fill", text: "缺卡")
            LegendItem(color: .purple, badge: "假", text: "请假")
            LegendItem(color: .blue, icon: "circle.fill", text: "待打卡")
            LegendItem(color: .red, icon: "flag.fill", text: "法定假日")
            LegendItem(color: .orange, icon: "arrow.triangle.2.circlepath", text: "调休补班")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var hint: some View {
        Label("在日期上右键：新增请假、补卡（遗漏）或清除该天记录", systemImage: "cursorarrow.click.2")
            .font(.caption)
            .foregroundStyle(.tertiary)
    }

    private func shiftMonth(by delta: Int) {
        guard let next = calendar.date(byAdding: .month, value: delta, to: displayedMonth) else { return }
        displayedMonth = next
    }

    private func helpText(for cell: AttendanceDayCell) -> String {
        let base = String(format: "%04d-%02d-%02d", grid.year, grid.month, cell.day)
        var parts: [String] = []

        let type = settings.dayType(cell.date, calendar: calendar)
        if let title = type.title { parts.append(title) }

        switch cell.status {
        case .done:
            let m = cell.morningDoneAt.map { Self.timeFormatter.string(from: $0) } ?? "—"
            let e = cell.eveningDoneAt.map { Self.timeFormatter.string(from: $0) } ?? "—"
            parts.append("已打卡 上班 \(m) / 下班 \(e)")
        case .missed: parts.append(missedReason(for: cell))
        case .leave, .none: break
        case .pending: parts.append("待打卡")
        }
        // 请假单独说：半天假的日子可以既是「已打卡」又带请假时段。
        parts += leaveNotes(for: cell)

        if cell.isFuture {
            if cell.isWorkday { parts.append("右键可提前请假") }
        } else {
            parts.append("右键可请假 / 补卡")
        }
        return ([base] + parts).joined(separator: " · ")
    }

    /// 当天请假的 tooltip：整天直接说「全天」，否则列出裁剪到当天的时段与合计时长；
    /// 跨天日程再附整条起止，免得只看当天误判请假长度。
    private func leaveNotes(for cell: AttendanceDayCell) -> [String] {
        let slices = cell.leaveSlices
        guard !slices.isEmpty else { return [] }
        if cell.leaveFraction >= 1 { return ["请假 全天"] }

        let segments = slices.map {
            "\(Self.timeFormatter.string(from: $0.start))–\(Self.timeFormatter.string(from: $0.end))"
        }.joined(separator: "、")
        let total = slices.reduce(TimeInterval(0)) { $0 + $1.duration }
        var notes = ["请假 \(segments) · 共 \(Self.hoursText(total))"]
        notes += LeaveRules.records(intersecting: cell.date, in: leaves, calendar: calendar)
            .filter { LeaveRules.naturalDays(of: $0, calendar: calendar) > 1 }
            .map {
                "跨天日程 \(Self.rangeText($0, calendar: calendar))" +
                "（共 \(LeaveRules.naturalDays(of: $0, calendar: calendar)) 天）"
            }
        return notes
    }

    /// 缺卡的真正原因：缺上班卡 / 有下班卡但不达标 / 完全没打。
    private func missedReason(for cell: AttendanceDayCell) -> String {
        let record = records[cell.dateKey] ?? DayRecord()
        guard record.morningDone else { return "缺上班卡" }
        guard let threshold = AttendanceRule.expectedLeave(record, settings: settings,
                                                           on: cell.date, leaves: leaves,
                                                           calendar: calendar) else {
            return "缺卡"
        }
        if let last = record.eveningPunches.max() {
            if last < threshold {
                return "下班卡 \(Self.timeFormatter.string(from: last)) 早于 \(Self.timeFormatter.string(from: threshold))，未达标"
            }
            return "缺卡"
        }
        return "缺下班卡（需不早于 \(Self.timeFormatter.string(from: threshold))）"
    }

    /// 请假日程的简述：同一天只写时刻，跨天带上日期。
    private static func rangeText(_ leave: LeaveRecord, calendar: Calendar) -> String {
        let lastMoment = leave.end.addingTimeInterval(-1)
        guard calendar.isDate(leave.start, inSameDayAs: lastMoment) else {
            return "\(dayTimeFormatter.string(from: leave.start)) → \(dayTimeFormatter.string(from: leave.end))"
        }
        return "\(timeFormatter.string(from: leave.start))–\(timeFormatter.string(from: leave.end))"
    }

    /// 时长文案：`2 小时` / `1.5 小时`。
    private static func hoursText(_ interval: TimeInterval) -> String {
        let hours = interval / 3600
        return hours == hours.rounded() ? "\(Int(hours)) 小时" : String(format: "%.1f 小时", hours)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let dayTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f
    }()
}

private struct DayCellContent: View {
    let cell: AttendanceDayCell
    let dayType: WorkdayDayType

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("\(cell.day)")
                    .font(.subheadline.weight(cell.isToday ? .bold : .regular))
                    .foregroundStyle(cell.isWorkday ? Color.primary : Color.secondary)
                Spacer()
                marker
            }
            dayTypeLabel
            if cell.status == .done {
                times
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(backgroundColor)
                RoundedRectangle(cornerRadius: 8).fill(dayTypeTint)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(cell.isToday ? Color.accentColor : Color.clear, lineWidth: 1.5)
        )
    }

    @ViewBuilder
    private var marker: some View {
        switch cell.status {
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .missed:
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
        case .leave:
            // 请假统一用下方「假」字标注（与「休/班」同一机制），不再占用右上角图标位。
            EmptyView()
        case .pending:
            Image(systemName: "circle.fill").font(.caption).foregroundStyle(.blue)
        case .none:
            EmptyView()
        }
    }

    /// 节假日 / 调休与请假共用的名称标记；普通工作日不占用空间。
    @ViewBuilder
    private var dayTypeLabel: some View {
        let items = labels
        if items.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: 3) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    label(item.text, color: item.color)
                }
            }
        }
    }

    /// 「中秋 假」「班 假」这类组合按顺序排在一起；半天假也要看得见「假」。
    private var labels: [(text: String, color: Color)] {
        var items: [(text: String, color: Color)] = []
        switch dayType {
        case .holiday(let name): items.append((name, .red))
        case .makeupWorkday(let name): items.append((name, .orange))
        case .workday, .weekend: break
        }
        if !cell.leaveSlices.isEmpty { items.append(("假", .purple)) }
        return items
    }

    private func label(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(color)
            .lineLimit(1)
            .truncationMode(.tail)
            .minimumScaleFactor(0.8)
    }

    @ViewBuilder
    private var times: some View {
        Text(timesText)
            .font(.system(size: 10).monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private var timesText: String {
        var parts: [String] = []
        if let m = cell.morningDoneAt { parts.append(Self.timeFormatter.string(from: m)) }
        if let e = cell.eveningDoneAt { parts.append(Self.timeFormatter.string(from: e)) }
        return parts.joined(separator: "–")
    }

    private var backgroundColor: Color {
        switch cell.status {
        case .none: return Color(nsColor: .controlBackgroundColor)
        default: return Color(nsColor: .textBackgroundColor)
        }
    }

    /// 节假日底色，与「工作日」设置页的图例保持同一套配色。
    private var dayTypeTint: Color {
        switch dayType {
        case .holiday: return Color.red.opacity(0.10)
        case .makeupWorkday: return Color.orange.opacity(0.12)
        case .workday, .weekend: return Color.clear
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}

private struct LegendItem: View {
    let color: Color
    let symbol: String?
    let badge: String?
    let text: String

    init(color: Color, icon: String, text: String) {
        self.color = color
        self.symbol = icon
        self.badge = nil
        self.text = text
    }

    /// 与日历格一致的「假」字标注：这里没有对应的 SF Symbol，直接用文字画。
    init(color: Color, badge: String, text: String) {
        self.color = color
        self.symbol = nil
        self.badge = badge
        self.text = text
    }

    var body: some View {
        HStack(spacing: 4) {
            if let badge {
                Text(badge)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(color)
            } else if let symbol {
                Image(systemName: symbol).foregroundStyle(color)
            }
            Text(text)
        }
    }
}
