import SwiftUI
import DakaCore

/// 考勤日历公共组件：以「月」为统计维度（每月 1 号 ~ 月末），
/// 在日历格中标注每日打卡状态。
///
/// 状态标记：
/// - 已打卡（done）：绿色对号 ✓ + 打卡时间
/// - 应打卡未打卡（missed）：红色感叹号 !
/// - 请假（leave）：紫色图标
/// - 待打卡（pending）：蓝色圆点（仅今天、窗口未过时）
/// - 非工作日 / 未来（none）：无标记
public struct CalendarView: View {
    @Binding var displayedMonth: Date
    let records: [String: DayRecord]
    let settings: DakaCore.Settings
    let now: Date
    var calendar: Calendar = .current
    var onSelectDay: ((AttendanceDayCell) -> Void)?

    public init(displayedMonth: Binding<Date>,
                records: [String: DayRecord],
                settings: DakaCore.Settings,
                now: Date,
                calendar: Calendar = .current,
                onSelectDay: ((AttendanceDayCell) -> Void)? = nil) {
        self._displayedMonth = displayedMonth
        self.records = records
        self.settings = settings
        self.now = now
        self.calendar = calendar
        self.onSelectDay = onSelectDay
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
            Button {
                onSelectDay?(item)
            } label: {
                DayCellContent(cell: item)
            }
            .buttonStyle(.plain)
            .help(helpText(for: item))
        } else {
            Color.clear.frame(minHeight: 64)
        }
    }

    private var legend: some View {
        HStack(spacing: 16) {
            LegendItem(color: .green, icon: "checkmark.circle.fill", text: "已打卡")
            LegendItem(color: .red, icon: "exclamationmark.circle.fill", text: "缺卡")
            LegendItem(color: .purple, icon: "bed.double.fill", text: "请假")
            LegendItem(color: .blue, icon: "circle.fill", text: "待打卡")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func shiftMonth(by delta: Int) {
        guard let next = calendar.date(byAdding: .month, value: delta, to: displayedMonth) else { return }
        displayedMonth = next
    }

    private func helpText(for cell: AttendanceDayCell) -> String {
        let base = String(format: "%04d-%02d-%02d", grid.year, grid.month, cell.day)
        switch cell.status {
        case .done:
            let m = cell.morningDoneAt.map { Self.timeFormatter.string(from: $0) } ?? "—"
            let e = cell.eveningDoneAt.map { Self.timeFormatter.string(from: $0) } ?? "—"
            return "\(base) 已打卡 上班 \(m) / 下班 \(e)"
        case .missed: return "\(base) 缺卡"
        case .leave: return "\(base) 请假"
        case .pending: return "\(base) 待打卡"
        case .none: return base
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}

private struct DayCellContent: View {
    let cell: AttendanceDayCell

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("\(cell.day)")
                    .font(.subheadline.weight(cell.isToday ? .bold : .regular))
                    .foregroundStyle(cell.isWorkday ? Color.primary : Color.secondary)
                Spacer()
                marker
            }
            if cell.status == .done {
                times
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: 8))
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

    @ViewBuilder
    private var times: some View {
        HStack(spacing: 3) {
            if let m = cell.morningDoneAt {
                Text(Self.timeFormatter.string(from: m)).monospacedDigit()
            }
            if let e = cell.eveningDoneAt {
                Text("/ " + Self.timeFormatter.string(from: e)).monospacedDigit()
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private var backgroundColor: Color {
        switch cell.status {
        case .none: return Color(nsColor: .controlBackgroundColor)
        default: return Color(nsColor: .textBackgroundColor)
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
