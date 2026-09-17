import SwiftUI
import DakaCore

struct ControlCenterView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        NavigationSplitView {
            List(selection: sidebarSelection) {
                ForEach(model.tools) { tool in
                    VStack(alignment: .leading, spacing: 2) {
                        Label(tool.title, systemImage: tool.symbol)
                        Text(summary(for: tool.id))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(SidebarSelection.tool(tool.id))
                }

                Section("设置") {
                    ForEach(SettingsPage.allCases) { page in
                        Label(page.title, systemImage: page.symbol)
                            .tag(SidebarSelection.settings(page))
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 200, max: 260)
        } detail: {
            detail(for: model.selectedSidebar)
                .padding(20)
        }
        .frame(minWidth: 720, minHeight: 520)
    }

    private func summary(for id: ToolID) -> String {
        switch id {
        case .punch:
            let morning = model.record.morningDone ? "上班已完成" : "上班待打卡"
            let evening = model.isEveningComplete ? "下班已完成" : "下班待打卡"
            return "\(morning) · \(evening)"
        case .water:
            return "今日 \(model.healthStatus.cups)/\(model.healthSettings.waterGoalCups) 杯"
        case .sedentary:
            return "已起身 \(model.healthStatus.stands) 次"
        }
    }

    private var sidebarSelection: Binding<SidebarSelection?> {
        Binding(get: { model.selectedSidebar },
                set: { if let value = $0 { model.select(value) } })
    }

    @ViewBuilder
    private func detail(for selection: SidebarSelection) -> some View {
        switch selection {
        case .tool(.punch):
            PunchToolView(model: model)
        case .tool(.water):
            WaterToolView(model: model)
        case .tool(.sedentary):
            MovementToolView(model: model)
        case .settings(.schedule):
            ScheduleSettingsView(model: model)
        case .settings(.workdays):
            WorkdaySettingsView(model: model)
        case .settings(.system):
            SystemSettingsView(model: model)
        }
    }
}
