import SwiftUI
import Charts
import DakaCore

struct WaterToolView: View {
    @ObservedObject var model: AppModel
    @State private var rangeDays = 14

    private var status: HealthStatus { model.healthStatus }
    private var summary: HealthSummary { model.healthStatistics(rangeDays: rangeDays) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    HealthMetricCard(title: "今日喝水",
                                     value: "\(status.cups)/\(model.healthSettings.waterGoalCups) 杯",
                                     symbol: "drop.fill")
                    HealthMetricCard(title: "连续达标",
                                     value: "\(summary.waterStreak) 天",
                                     symbol: "flame")
                    HealthMetricCard(title: "平均每日",
                                     value: String(format: "%.1f 杯", summary.averageCups),
                                     symbol: "chart.bar")
                    HealthMetricCard(title: "距上次喝水",
                                     value: HealthFormat.minutes(status.minutesSinceDrink),
                                     symbol: "clock")
                }

                Button {
                    model.drinkWater()
                } label: {
                    Label("喝了一杯水", systemImage: "drop.fill")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("每日喝水").font(.headline)
                        Spacer()
                        rangePicker
                    }
                    Chart {
                        ForEach(summary.days, id: \.dateKey) { day in
                            BarMark(x: .value("日期", String(day.dateKey.suffix(5))),
                                    y: .value("杯", day.cups))
                                .foregroundStyle(Color.blue)
                        }
                        RuleMark(y: .value("目标", model.healthSettings.waterGoalCups))
                            .foregroundStyle(.secondary)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                    .chartYAxisLabel("杯")
                    .frame(height: 220)
                }

                Form {
                    Section("喝水设置") {
                        Toggle("启用提醒", isOn: Binding(
                            get: { model.healthSettings.waterEnabled },
                            set: { model.setWaterEnabled($0) }))
                        Stepper("每日目标：\(model.healthSettings.waterGoalCups) 杯",
                                value: Binding(
                                    get: { model.healthSettings.waterGoalCups },
                                    set: { model.setWaterGoalCups($0) }),
                                in: 1...20)
                        Stepper("提醒间隔：\(model.healthSettings.waterIntervalMinutes) 分钟",
                                value: Binding(
                                    get: { model.healthSettings.waterIntervalMinutes },
                                    set: { model.setWaterIntervalMinutes($0) }),
                                in: 15...240, step: 15)
                    }
                }
                .formStyle(.grouped)
            }
        }
    }

    private var rangePicker: some View {
        Picker("范围", selection: $rangeDays) {
            Text("7 天").tag(7)
            Text("14 天").tag(14)
            Text("30 天").tag(30)
        }
        .pickerStyle(.segmented)
        .frame(width: 220)
    }
}

struct MovementToolView: View {
    @ObservedObject var model: AppModel
    @State private var rangeDays = 14

    private var status: HealthStatus { model.healthStatus }
    private var summary: HealthSummary { model.healthStatistics(rangeDays: rangeDays) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    HealthMetricCard(title: "今日起身",
                                     value: "\(status.stands)/\(model.healthSettings.movementGoalCount) 次",
                                     symbol: "figure.walk")
                    HealthMetricCard(title: "连续达标",
                                     value: "\(summary.movementStreak) 天",
                                     symbol: "flame")
                    HealthMetricCard(title: "平均每日",
                                     value: String(format: "%.1f 次", summary.averageStands),
                                     symbol: "chart.bar")
                    HealthMetricCard(title: "距上次起身",
                                     value: HealthFormat.minutes(status.minutesSinceStand),
                                     symbol: "clock")
                }

                Button {
                    model.standUp()
                } label: {
                    Label("起来走走", systemImage: "figure.walk")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("每日起身次数").font(.headline)
                        Spacer()
                        rangePicker
                    }
                    Chart {
                        ForEach(summary.days, id: \.dateKey) { day in
                            BarMark(x: .value("日期", String(day.dateKey.suffix(5))),
                                    y: .value("次", day.stands))
                                .foregroundStyle(Color.green)
                        }
                        RuleMark(y: .value("目标", model.healthSettings.movementGoalCount))
                            .foregroundStyle(.secondary)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                    .chartYAxisLabel("次")
                    .frame(height: 220)
                }

                Form {
                    Section("走动设置") {
                        Toggle("启用提醒", isOn: Binding(
                            get: { model.healthSettings.movementEnabled },
                            set: { model.setMovementEnabled($0) }))
                        Stepper("每日目标：\(model.healthSettings.movementGoalCount) 次",
                                value: Binding(
                                    get: { model.healthSettings.movementGoalCount },
                                    set: { model.setMovementGoalCount($0) }),
                                in: 1...20)
                        Stepper("提醒间隔：\(model.healthSettings.movementIntervalMinutes) 分钟",
                                value: Binding(
                                    get: { model.healthSettings.movementIntervalMinutes },
                                    set: { model.setMovementIntervalMinutes($0) }),
                                in: 15...240, step: 15)
                    }
                }
                .formStyle(.grouped)
            }
        }
    }

    private var rangePicker: some View {
        Picker("范围", selection: $rangeDays) {
            Text("7 天").tag(7)
            Text("14 天").tag(14)
            Text("30 天").tag(30)
        }
        .pickerStyle(.segmented)
        .frame(width: 220)
    }
}

struct HealthMetricCard: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
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

enum HealthFormat {
    static func minutes(_ value: Int?) -> String {
        guard let value else { return "—" }
        if value < 60 { return "\(value) 分钟" }
        return "\(value / 60) 小时 \(value % 60) 分"
    }
}
