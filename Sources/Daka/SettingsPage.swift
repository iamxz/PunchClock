import DakaCore

enum SettingsPage: String, CaseIterable, Identifiable {
    case schedule, workdays, attendance, system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .schedule: return "打卡时间"
        case .workdays: return "工作日"
        case .attendance: return "考勤规则"
        case .system: return "系统与启动"
        }
    }

    var symbol: String {
        switch self {
        case .schedule: return "clock"
        case .workdays: return "calendar"
        case .attendance: return "checklist"
        case .system: return "gearshape"
        }
    }
}

enum SidebarSelection: Hashable {
    case tool(ToolID)
    case settings(SettingsPage)
}
