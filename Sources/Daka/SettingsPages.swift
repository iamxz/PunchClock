import SwiftUI
import DakaCore

private func settingsDateFrom(_ hhmm: String, now: Date) -> Date {
    DakaDate.date(on: now, at: hhmm) ?? now
}

private func settingsHHMM(from date: Date) -> String {
    let c = Calendar.current.dateComponents([.hour, .minute], from: date)
    return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
}

private func settingsHoursText(_ hours: Double) -> String {
    hours == hours.rounded() ? String(Int(hours)) : String(format: "%.1f", hours)
}

struct ScheduleSettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Toggle("启用提醒", isOn: Binding(get: { model.settings.enabled },
                                            set: { model.setEnabled($0) }))

            Section("考勤规则") {
                DatePicker("上班时间",
                           selection: Binding(
                            get: { settingsDateFrom(model.settings.workStartTime, now: model.now) },
                            set: { model.updateWorkStart(settingsHHMM(from: $0)) }),
                           displayedComponents: .hourAndMinute)
                Stepper(value: Binding(get: { model.settings.flexMinutes },
                                       set: { model.setFlexMinutes($0) }),
                        in: 0...120, step: 5) {
                    Text("弹性时间：\(model.settings.flexMinutes) 分钟")
                }
                Stepper(value: Binding(get: { model.settings.workDurationHours },
                                       set: { model.setWorkDurationHours($0) }),
                        in: 0.5...12, step: 0.5) {
                    Text("工作时长：\(settingsHoursText(model.settings.workDurationHours)) 小时")
                }
                Text("下班提醒随上班卡时间浮动：早到按上班时间算，晚打顺延下班。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("重复提醒") {
                Stepper(value: Binding(get: { Int(model.settings.reminderIntervalSeconds / 60) },
                                       set: { model.setReminderIntervalMinutes($0) }),
                        in: 1...60) {
                    Text("每隔 \(Int(model.settings.reminderIntervalSeconds / 60)) 分钟重复提醒")
                }
                Text("进入打卡窗口即全屏提醒，完成对应打卡后停止。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct WorkdaySettingsView: View {
    @ObservedObject var model: AppModel
    @State private var displayYear: Int
    @State private var displayMonth: Int

    private let calendar = Calendar.current
    private let weekdaySymbols = ["日", "一", "二", "三", "四", "五", "六"]

    init(model: AppModel) {
        self.model = model
        let comps = Calendar.current.dateComponents([.year, .month], from: Date())
        _displayYear = State(initialValue: comps.year ?? 2026)
        _displayMonth = State(initialValue: comps.month ?? 9)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                    Text("\(displayYear) 年 \(displayMonth) 月")
                        .font(.headline)
                        .frame(minWidth: 120, alignment: .center)
                    Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                    Spacer()
                    Button("回到本月") { goToday() }
                }

                HStack {
                    ForEach(weekdaySymbols, id: \.self) { sym in
                        Text(sym)
                            .font(.caption)
                            .frame(maxWidth: .infinity)
                            .foregroundStyle(.secondary)
                    }
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7),
                          spacing: 8) {
                    ForEach(monthCells(), id: \.self) { cell in
                        if let date = cell {
                            WorkdayDayCell(date: date,
                                          type: model.settings.dayType(date, calendar: calendar)) {
                                model.cycleWorkdayOverride(for: date, calendar: calendar)
                            }
                        } else {
                            Color.clear.frame(height: 46)
                        }
                    }
                }

                legend

                Text("基础工作日为周一至周五，已内置 2025–2026 年法定节假日与调休数据。点击某天可手动微调：默认 → 强制相反 → 强制还原 → 默认（蓝色边框表示手动覆盖）。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
        }
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem(color: .primary, label: "班（工作日）")
            legendItem(color: .secondary, label: "休（周末）")
            legendItem(color: .red, label: "休（法定假日）")
            legendItem(color: .orange, label: "班（调休补班）")
            legendItem(color: .blue, label: "手动覆盖")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color.opacity(0.25))
                .frame(width: 12, height: 12)
            Text(label)
        }
    }

    private func shiftMonth(_ delta: Int) {
        let comps = DateComponents(year: displayYear, month: displayMonth, day: 1)
        guard let date = calendar.date(from: comps),
              let newDate = calendar.date(byAdding: .month, value: delta, to: date) else { return }
        let nc = calendar.dateComponents([.year, .month], from: newDate)
        displayYear = nc.year ?? displayYear
        displayMonth = nc.month ?? displayMonth
    }

    private func goToday() {
        let nc = calendar.dateComponents([.year, .month], from: Date())
        displayYear = nc.year ?? displayYear
        displayMonth = nc.month ?? displayMonth
    }

    private func monthCells() -> [Date?] {
        var comps = DateComponents(year: displayYear, month: displayMonth, day: 1)
        guard let first = calendar.date(from: comps) else { return [] }
        let leading = calendar.component(.weekday, from: first) - 1
        let days = calendar.range(of: .day, in: .month, for: first)?.count ?? 0
        var result: [Date?] = Array(repeating: nil, count: leading)
        for d in 1...days {
            comps.day = d
            if let date = calendar.date(from: comps) { result.append(date) }
        }
        while result.count % 7 != 0 { result.append(nil) }
        return result
    }
}

struct WorkdayDayCell: View {
    let date: Date
    let type: WorkdayDayType
    let onTap: () -> Void

    private let calendar = Calendar.current

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 13))
                Text(type.badge)
                    .font(.system(size: 10))
            }
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(backgroundColor)
            .foregroundStyle(foregroundColor)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.blue, lineWidth: type.isCustom ? 1.5 : 0)
            )
            .help(helpText)
        }
        .buttonStyle(.plain)
    }

    private var backgroundColor: Color {
        switch type {
        case .workday: return Color.secondary.opacity(0.08)
        case .weekend: return Color.clear
        case .holiday: return Color.red.opacity(0.12)
        case .makeupWorkday: return Color.orange.opacity(0.14)
        case .customWorkday, .customOff: return Color.blue.opacity(0.12)
        }
    }

    private var foregroundColor: Color {
        switch type {
        case .workday: return Color.primary
        case .weekend: return Color.secondary
        case .holiday: return Color.red
        case .makeupWorkday: return Color.orange
        case .customWorkday, .customOff: return Color.blue
        }
    }

    private var helpText: String {
        if type.isCustom { return "手动微调" }
        return type.title ?? ""
    }
}

struct SystemSettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section("自启与定点") {
                HStack {
                    Image(systemName: LoginItemManager.isEnabled ? "checkmark.circle.fill" : "exclamationmark.triangle")
                        .foregroundStyle(LoginItemManager.isEnabled ? Color.green : Color.orange)
                    Text(LoginItemManager.isEnabled ? "开机自启已启用"
                         : (LoginItemManager.requiresApproval ? "开机自启需在系统设置中允许" : "开机自启未启用"))
                    Spacer()
                    if LoginItemManager.requiresApproval {
                        Button("打开设置") { LoginItemManager.openSystemSettings() }
                    } else if !LoginItemManager.isEnabled {
                        Button("启用") { model.repairLoginItem() }
                    }
                }
                HStack {
                    Image(systemName: model.scheduledLaunchInstalled ? "checkmark.circle.fill" : "exclamationmark.triangle")
                        .foregroundStyle(model.scheduledLaunchInstalled ? Color.green : Color.orange)
                    Text(model.scheduledLaunchInstalled ? "定点启动已启用" : "定点启动未启用")
                }
            }

            Section("应用") {
                Button("退出应用") { model.confirmQuit() }
            }

            if model.hasSettingsFeedback {
                Section {
                    SettingsFeedbackView(model: model)
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct SettingsFeedbackView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let error = model.errorMessage {
                Text(error).foregroundStyle(.red)
            }
            if let warning = model.startupWarning {
                Text(warning).foregroundStyle(.orange)
            }
            if let warning = model.scheduledLaunchWarning {
                Text(warning).foregroundStyle(.orange)
            }
        }
    }
}
