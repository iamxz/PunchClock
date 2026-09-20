import SwiftUI
import DakaCore

struct StatisticsView: View {
    @ObservedObject var model: AppModel
    @State private var displayedMonth: Date

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
                             now: model.now)
            }
        }
    }

    private var averageText: String {
        guard let average = averageWorkDuration else { return "—" }
        let hours = Int(average) / 3600
        let minutes = (Int(average) % 3600) / 60
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
}
