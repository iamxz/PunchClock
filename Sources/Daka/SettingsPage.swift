import DakaCore

enum SettingsPage: String, CaseIterable, Identifiable {
    case schedule, system, about, debug

    var id: String { rawValue }

    var title: String {
        switch self {
        case .schedule: return "考勤规则"
        case .system: return "系统与启动"
        case .about: return "关于 / 更新"
        case .debug: return "测试面板"
        }
    }

    var symbol: String {
        switch self {
        case .schedule: return "clock"
        case .system: return "gearshape"
        case .about: return "arrow.down.circle"
        case .debug: return "hammer"
        }
    }
}

enum SidebarSelection: Hashable {
    case tool(ToolID)
    case settings(SettingsPage)
}
