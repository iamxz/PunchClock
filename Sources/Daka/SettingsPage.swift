import DakaCore

enum SettingsPage: String, CaseIterable, Identifiable {
    case schedule, workdays, system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .schedule: return "考勤规则"
        case .workdays: return "工作日"
        case .system: return "系统与启动"
        }
    }

    var symbol: String {
        switch self {
        case .schedule: return "clock"
        case .workdays: return "calendar"
        case .system: return "gearshape"
        }
    }
}

enum SidebarSelection: Hashable {
    case tool(ToolID)
    case settings(SettingsPage)
}
