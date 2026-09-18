import SwiftUI
import Charts
import DakaCore

struct StatisticsView: View {
    @ObservedObject var model: AppModel
    @State private var rangeDays = 14

    private var summary: StatisticsSummary {
        model.statistics(rangeDays: rangeDays)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    metricCard("本月打卡", "\(summary.monthPunchDays) 天", "calendar")
                    metricCard("连续打卡", "\(summary.currentStreak) 天", "flame")
                    metricCard("平均上班", averageText, "clock")
                    metricCard("缺卡", "\(summary.missedDays) 天", "exclamationmark.triangle")
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("每日上班时长").font(.headline)
                        Spacer()
                        Picker("范围", selection: $rangeDays) {
                            Text("7 天").tag(7)
                            Text("14 天").tag(14)
                            Text("30 天").tag(30)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 220)
                    }

                    let chartDays = summary.days.filter { $0.workDuration != nil }
                    if chartDays.isEmpty {
                        Text("还没有足够的打卡记录")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 220)
                    } else {
                        Chart(chartDays, id: \.dateKey) { day in
                            BarMark(
                                x: .value("日期", String(day.dateKey.suffix(5))),
                                y: .value("小时", (day.workDuration ?? 0) / 3600)
                            )
                            .foregroundStyle(Color.accentColor.opacity(0.5))

                            LineMark(
                                x: .value("日期", String(day.dateKey.suffix(5))),
                                y: .value("小时", (day.workDuration ?? 0) / 3600)
                            )
                            .foregroundStyle(Color.accentColor)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                            .symbol(Circle())
                            .symbolSize(30)
                            .interpolationMethod(.catmullRom)
                        }
                        .chartYAxisLabel("小时")
                        .frame(height: 240)
                    }
                }
            }
        }
    }

    private var averageText: String {
        guard let average = summary.averageWorkDuration else { return "—" }
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
