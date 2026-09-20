import SwiftUI
import DakaCore

/// 考勤日历公共组件：以「月」为统计维度（每月 1 号 ~ 月末），
/// 在日历格中标注每日打卡状态与节假日。
///
/// 状态标记：
/// - 已打卡（done）：绿色对号 ✓ + 打卡时间
/// - 应打卡未打卡（missed）：红色感叹号 !
/// - 请假（leave）：紫色图标
/// - 待打卡（pending）：蓝色圆点（仅今天、窗口未过时）
/// - 非工作日 / 未来（none）：无标记
///
/// 节假日标记：法定假日显示节日名（红）、调休补班显示名称（橙）、手动覆盖显示「手动」（蓝）。
///
/// 右键（今天与过去的日期）可执行：标记 / 取消休假、补卡（遗漏）、清除该天记录。
public struct CalendarView: View {
    @Binding var displayedMonth: Date
    let records: [String: DayRecord]
    let settings: DakaCore.Settings
    let now: Date
    var calendar: Calendar = .current
    var onSelectDay: ((AttendanceDayCell) -> Void)?
    var onToggleLeave: ((AttendanceDayCell) -> Void)?
    var onMakeUp: ((AttendanceDayCell) -> Void)?
    var onClearPunches: ((AttendanceDayCell) -> Void)?

    public init(displayedMonth: Binding<Date>,
                records: [String: DayRecord],
                settings: DakaCore.Settings,
                now: Date,
                calendar: Calendar = .current,
                onSelectDay: ((AttendanceDayCell) -> Void)? = nil,
                onToggleLeave: ((AttendanceDayCell) -> Void)? = nil,
                onMakeUp: ((AttendanceDayCell) -> Void)? = nil,
                onClearPunches: ((AttendanceDayCell) -> Void)? = nil) {
        self._displayedMonth = displayedMonth
        self.records = records
        self.settings = settings
        self.now = now
        self.calendar = calendar
        self.onSelectDay = onSelectDay
        self.onToggleLeave = onToggleLeave
        self.onMakeUp = onMakeUp
        self.onClearPunches = onClearPunches
    }

    private var grid: MonthGrid {
        AttendanceCalendar.monthGrid(records: records, settings: settings,
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
            if hasMenuItems(item) {
                dayButton(item).contextMenu { menu(for: item) }
            } else {
                dayButton(item)
            }
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

    private func hasMenuItems(_ item: AttendanceDayCell) -> Bool {
        item.status == .leave                       // 可取消休假
            || item.isWorkday                       // 可登记休假（含未来工作日，提前请年假）
            || (!item.isFuture && canMakeUp(item))  // 可补卡（遗漏）
            || hasPunches(item)                     // 可清除记录
    }

    /// 右侧菜单：休假 / 补卡（遗漏）/ 清除该天记录。
    @ViewBuilder
    private func menu(for item: AttendanceDayCell) -> some View {
        if item.status == .leave {
            Button {
                onToggleLeave?(item)
            } label: {
                Label("取消休假", systemImage: "bed.double")
            }
        } else if item.isWorkday {
            Button {
                onToggleLeave?(item)
            } label: {
                Label(item.isFuture ? "登记休假" : "标记为休假", systemImage: "bed.double.fill")
            }
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
            LegendItem(color: .purple, icon: "bed.double.fill", text: "请假")
            LegendItem(color: .blue, icon: "circle.fill", text: "待打卡")
            LegendItem(color: .red, icon: "flag.fill", text: "法定假日")
            LegendItem(color: .orange, icon: "arrow.triangle.2.circlepath", text: "调休补班")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var hint: some View {
        Label("在日期上右键：标记休假、补卡（遗漏）或清除该天记录", systemImage: "cursorarrow.click.2")
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
        case .leave: parts.append("请假")
        case .pending: parts.append("待打卡")
        case .none: break
        }

        if cell.isFuture {
            if cell.isWorkday { parts.append("右键可登记休假") }
        } else {
            parts.append("右键可休假 / 补卡")
        }
        return ([base] + parts).joined(separator: " · ")
    }

    /// 缺卡的真正原因：缺上班卡 / 有下班卡但不达标 / 完全没打。
    private func missedReason(for cell: AttendanceDayCell) -> String {
        let record = records[cell.dateKey] ?? DayRecord()
        guard let morning = record.morningDoneAt else { return "缺上班卡" }
        let threshold = morning.addingTimeInterval(settings.workDuration)
        if let last = record.eveningPunches.max() {
            if last < threshold {
                return "下班卡 \(Self.timeFormatter.string(from: last)) 早于 \(Self.timeFormatter.string(from: threshold))，未达标"
            }
            return "缺卡"
        }
        return "缺下班卡（需不早于 \(Self.timeFormatter.string(from: threshold))）"
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
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
            Image(systemName: "bed.double.fill").foregroundStyle(.purple)
        case .pending:
            Image(systemName: "circle.fill").font(.caption).foregroundStyle(.blue)
        case .none:
            EmptyView()
        }
    }

    /// 节假日 / 调休的名称标记；普通工作日与周末不占用空间。
    @ViewBuilder
    private var dayTypeLabel: some View {
        switch dayType {
        case .holiday(let name):
            label(name, color: .red)
        case .makeupWorkday(let name):
            label(name, color: .orange)
        case .workday, .weekend:
            EmptyView()
        }
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
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon).foregroundStyle(color)
            Text(text)
        }
    }
}
