import SwiftUI
import DakaCore

/// Toast 配色：对齐微信提示的调色（品牌绿为主，喝水用蓝、失败用红）。
///
/// 卡片底色统一是深色、符号一律白色，所以这里只需要给出各类型的强调色。
enum ToastPalette {
    /// 微信品牌绿 #07C160。
    static let brand = Color(red: 0.027, green: 0.757, blue: 0.376)
    /// 喝水提醒蓝 #2E9BF6。
    static let water = Color(red: 0.180, green: 0.608, blue: 0.965)
    /// 失败 / 警示红 #FA5151。
    static let warn = Color(red: 0.980, green: 0.318, blue: 0.318)
}

/// 健康提醒文案（弱提示 toast 与健康提醒共用一份，避免两处漂移）。
enum HealthCopy {
    static func title(_ kind: HealthAlert.Kind) -> String {
        switch kind {
        case .water: return "该喝水啦 💧"
        case .movement: return "起来走两步 🚶"
        }
    }

    static func body(_ kind: HealthAlert.Kind, minutes: Int) -> String {
        switch kind {
        case .water: return "已经 \(minutes) 分钟没喝水了，起来接杯水吧。"
        case .movement: return "坐了 \(minutes) 分钟，活动一下肩颈和腿吧。"
        }
    }

    static func icon(_ kind: HealthAlert.Kind) -> String {
        kind == .water ? "drop.fill" : "figure.walk"
    }

    static func tint(_ kind: HealthAlert.Kind) -> Color {
        kind == .water ? ToastPalette.water : ToastPalette.brand
    }
}

/// Toast 文案模板库。
///
/// 线上提示（打卡、喝水、久坐）与「设置 → 测试面板」的预览共用同一份定义：
/// 改文案只需要改这里，面板里看到的就是真实提示，不会出现两处漂移。
enum ToastTemplate: String, CaseIterable, Identifiable {
    case punchMorning
    case punchEvening
    case punchEveningPartial
    case punchEveningMissingMorning
    case waterReminder
    case movementReminder
    case settingsSaved
    case operationFailed

    enum Group: String, CaseIterable, Identifiable {
        case punch, health, general

        var id: String { rawValue }

        var title: String {
            switch self {
            case .punch: return "打卡"
            case .health: return "健康提醒"
            case .general: return "通用样式"
            }
        }

        /// 补充说明（仅通用样式需要）。
        var caption: String? {
            self == .general ? "通用样式用于参考文案长短与配色，当前业务流程不会自动触发。" : nil
        }
    }

    var id: String { rawValue }

    var group: Group {
        switch self {
        case .punchMorning, .punchEvening, .punchEveningPartial, .punchEveningMissingMorning:
            return .punch
        case .waterReminder, .movementReminder:
            return .health
        case .settingsSaved, .operationFailed:
            return .general
        }
    }

    /// 面板里展示的模板名。
    var name: String {
        switch self {
        case .punchMorning: return "上班打卡成功"
        case .punchEvening: return "下班打卡成功"
        case .punchEveningPartial: return "下班已记录（未满时长）"
        case .punchEveningMissingMorning: return "下班已记录（缺上班卡）"
        case .waterReminder: return "喝水提醒"
        case .movementReminder: return "起身活动提醒"
        case .settingsSaved: return "设置已保存"
        case .operationFailed: return "保存失败"
        }
    }

    /// 预览用 toast：动态数字取示例值，文案与线上提示完全一致。
    var toast: ToastCenter.Toast {
        switch self {
        case .punchMorning:
            return ToastTemplate.punch(task: .morning, feedback: nil)
        case .punchEvening:
            return ToastTemplate.punch(task: .evening, feedback: nil)
        case .punchEveningPartial:
            return ToastTemplate.punch(
                task: .evening,
                feedback: "已记录 18:30；距上班满 8 小时还差 2 小时 15 分钟，满后自动完成。")
        case .punchEveningMissingMorning:
            return ToastTemplate.punch(
                task: .evening,
                feedback: "已记录 18:30；今天还没有上班打卡，需先打上班卡；下班需满 8 小时才算完成。")
        case .waterReminder:
            return ToastTemplate.health(kind: .water, minutes: 60)
        case .movementReminder:
            return ToastTemplate.health(kind: .movement, minutes: 45)
        case .settingsSaved:
            return ToastCenter.Toast(title: "设置已保存",
                                     body: "新的考勤规则已生效。",
                                     icon: "checkmark.circle.fill",
                                     tint: .green)
        case .operationFailed:
            return ToastCenter.Toast(title: "保存失败",
                                     body: "无法写入本地记录文件，请稍后重试。",
                                     icon: "exclamationmark.triangle.fill",
                                     tint: .red)
        }
    }

    // MARK: - 业务工厂

    /// 打卡结果提示。`feedback` 非 nil 表示本次打卡仍未达标，附上原因与还差多久。
    static func punch(task: PunchTask, feedback: String?) -> ToastCenter.Toast {
        if let feedback {
            return ToastCenter.Toast(title: "已记录\(task.title)",
                                     body: feedback,
                                     icon: "checkmark.circle.fill",
                                     tint: ToastPalette.brand)
        }
        return ToastCenter.Toast(title: "打卡成功",
                                 body: "\(task.title)已记录，今天这一步完成了。",
                                 icon: "checkmark.circle.fill",
                                 tint: ToastPalette.brand)
    }

    /// 喝水 / 起身弱提示。
    static func health(kind: HealthAlert.Kind, minutes: Int) -> ToastCenter.Toast {
        ToastCenter.Toast(title: HealthCopy.title(kind),
                          body: HealthCopy.body(kind, minutes: minutes),
                          icon: HealthCopy.icon(kind),
                          tint: HealthCopy.tint(kind))
    }

    /// 预览样例：下班已记录但未满工作时长（hours 传当前设置里的每日工作时长）。
    static func punchPartialSample(hours: Double) -> ToastCenter.Toast {
        punch(task: .evening,
              feedback: "已记录 18:30；距上班满 \(hoursText(hours)) 小时还差 2 小时 15 分钟，满后自动完成。")
    }

    /// 预览样例：下班已记录但今天还缺上班卡。
    static func punchMissingMorningSample(hours: Double) -> ToastCenter.Toast {
        punch(task: .evening,
              feedback: "已记录 18:30；今天还没有上班打卡，需先打上班卡；下班需满 \(hoursText(hours)) 小时才算完成。")
    }

    /// 工作时长文案：整数不带小数点（与设置页保持一致）。
    static func hoursText(_ hours: Double) -> String {
        hours == hours.rounded() ? String(Int(hours)) : String(format: "%.1f", hours)
    }
}
