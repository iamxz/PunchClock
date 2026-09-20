import DakaCore

enum SettingsPage: String, CaseIterable, Identifiable {
    case schedule, workdays, system, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .schedule: return "考勤规则"
        case .workdays: return "工作日"
        case .system: return "系统与启动"
        case .about: return "关于 / 更新"
        }
    }

    var symbol: String {
        switch self {
        case .schedule: return "clock"
        case .workdays: return "calendar"
        case .system: return "gearshape"
        case .about: return "arrow.down.circle"
        }
    }
}

enum SidebarSelection: Hashable {
    case tool(ToolID)
    case settings(SettingsPage)
}
