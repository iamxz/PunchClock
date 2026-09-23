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
                if let error = model.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
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
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                        Text("喝了一杯水")
                        Image(systemName: "drop.fill")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(HealthActionButtonStyle(tint: Color(red: 10 / 255, green: 132 / 255, blue: 255 / 255)))

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
                                .foregroundStyle(Color.blue.opacity(0.5))

                            LineMark(x: .value("日期", String(day.dateKey.suffix(5))),
                                     y: .value("杯", day.cups))
                                .foregroundStyle(Color.blue)
                                .lineStyle(StrokeStyle(lineWidth: 2))
                                .symbol(Circle())
                                .symbolSize(28)
                                .interpolationMethod(.catmullRom)
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
            .padding(20)
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
                if let error = model.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
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
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                        Text("起来走走")
                        Image(systemName: "figure.walk")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(HealthActionButtonStyle(tint: Color(red: 52 / 255, green: 199 / 255, blue: 89 / 255)))

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
                                .foregroundStyle(Color.green.opacity(0.5))

                            LineMark(x: .value("日期", String(day.dateKey.suffix(5))),
                                     y: .value("次", day.stands))
                                .foregroundStyle(Color.green)
                                .lineStyle(StrokeStyle(lineWidth: 2))
                                .symbol(Circle())
                                .symbolSize(28)
                                .interpolationMethod(.catmullRom)
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
            .padding(20)
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

/// 喝水/久坐页主操作按钮：整行大胶囊、主题色渐变、悬停提亮、按下缩小。
struct HealthActionButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        HealthActionButton(configuration: configuration, tint: tint)
    }
}

private struct HealthActionButton: View {
    let configuration: ButtonStyleConfiguration
    let tint: Color
    @State private var hovering = false

    var body: some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background {
                Capsule()
                    .fill(tint)
                    .overlay(
                        Capsule().fill(
                            LinearGradient(
                                colors: [.white.opacity(0.18), .black.opacity(0.14)],
                                startPoint: .top,
                                endPoint: .bottom)
                        )
                    )
                    .shadow(color: tint.opacity(hovering ? 0.5 : 0.28),
                            radius: hovering ? 10 : 5,
                            y: 3)
            }
            .brightness(hovering ? 0.06 : 0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.15), value: hovering)
            .onHover { hovering = $0 }
            .contentShape(Capsule())
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
