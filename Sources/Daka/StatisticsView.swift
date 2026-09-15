import SwiftUI
import DakaCore

struct StatisticsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let summary = model.statistics(rangeDays: 14)
        VStack(alignment: .leading, spacing: 12) {
            Text("本月打卡 \(summary.monthPunchDays) 天")
            Text("连续打卡 \(summary.currentStreak) 天")
            Text("缺卡 \(summary.missedDays) 天")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
