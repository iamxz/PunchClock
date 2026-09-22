import SwiftUI
import DakaCore

/// 设置 → 测试面板：触发 toast 模板与全屏遮罩预览，确认真实提示的文案、图标与配色。
///
/// 预览调用的就是线上同一份模板（`ToastTemplate`）与同一个 `ReminderController`，
/// 喝水/久坐的分钟数、工作时长取自当前设置，所以面板里看到的内容与真实触发时一致；
/// 全屏预览仅去掉「写打卡记录」这一个副作用。
struct DebugSettingsView: View {
    @ObservedObject var model: AppModel

    /// 正在依次播放全部模板。
    @State private var isPlaying = false

    var body: some View {
        Form {
            Section("Toast 提示模板") {
                Text("点击「预览」会在鼠标所在屏的右上角浮出真实提示，停留 6 秒后自动淡出；多条提示会层叠，最多同时显示 3 张。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Button("依次播放全部") { playAll() }
                        .disabled(isPlaying)
                    Button("连发 3 条（看层叠）") { burst() }
                        .disabled(isPlaying)
                    Button("立即收起") { ToastCenter.shared.dismiss() }
                }
            }

            Section("全屏打卡提醒") {
                Text("点击后立即在所有屏幕弹出真实的全屏遮罩。预览模式下：点圆形按钮只收起遮罩、不会写入打卡记录，ESC 直接结束预览。多屏时可验证每块屏都已渲染、内容是否居中。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Button("预览「上班打卡」") { model.previewOverlayReminder([.morning]) }
                    Button("预览「下班打卡」") { model.previewOverlayReminder([.evening]) }
                    Button("结束预览") { model.endOverlayPreview() }
                }
            }

            ForEach(ToastTemplate.Group.allCases) { group in
                Section {
                    ForEach(templates(in: group)) { template in
                        row(template)
                    }
                } header: {
                    Text(group.title)
                } footer: {
                    if let caption = group.caption {
                        Text(caption)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func templates(in group: ToastTemplate.Group) -> [ToastTemplate] {
        ToastTemplate.allCases.filter { $0.group == group }
    }

    private func row(_ template: ToastTemplate) -> some View {
        let item = toast(for: template)
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.icon)
                .foregroundStyle(item.tint)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(template.name)
                Text(item.body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button("预览") { ToastCenter.shared.show(item, duration: 6) }
        }
    }

    /// 模板对应的 toast：动态数字按当前设置取值，其余直接用模板默认样例。
    private func toast(for template: ToastTemplate) -> ToastCenter.Toast {
        switch template {
        case .punchEveningPartial:
            return ToastTemplate.punchPartialSample(hours: model.settings.workDurationHours)
        case .punchEveningMissingMorning:
            return ToastTemplate.punchMissingMorningSample(hours: model.settings.workDurationHours)
        case .waterReminder:
            return ToastTemplate.health(kind: .water,
                                        minutes: model.healthSettings.effectiveWaterIntervalMinutes)
        case .movementReminder:
            return ToastTemplate.health(kind: .movement,
                                        minutes: model.healthSettings.effectiveMovementIntervalMinutes)
        default:
            return template.toast
        }
    }

    private func playAll() {
        guard !isPlaying else { return }
        isPlaying = true
        Task { @MainActor in
            for template in ToastTemplate.allCases {
                ToastCenter.shared.show(toast(for: template), duration: 2.4)
                try? await Task.sleep(for: .milliseconds(2600))
            }
            isPlaying = false
        }
    }

    /// 快速连发 3 条：新提示从右侧滑入插到最上，旧的被顶下去，用来检查层叠动画。
    private func burst() {
        guard !isPlaying else { return }
        isPlaying = true
        Task { @MainActor in
            let samples: [ToastTemplate] = [.waterReminder, .punchMorning, .movementReminder]
            for template in samples {
                ToastCenter.shared.show(toast(for: template), duration: 5)
                try? await Task.sleep(for: .milliseconds(500))
            }
            isPlaying = false
        }
    }
}
