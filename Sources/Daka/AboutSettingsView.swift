import SwiftUI
import DakaCore

struct AboutSettingsView: View {
    @ObservedObject var model: AppModel

    private var currentVersionText: String {
        UpdateChecker.shared.currentVersion?.description ?? "未知"
    }

    var body: some View {
        Form {
            Section("当前版本") {
                HStack {
                    Text("小打卡")
                    Spacer()
                    Text(currentVersionText)
                        .foregroundStyle(.secondary)
                }
            }

            Section("更新") {
                updateStatusRow

                HStack {
                    Button("立即检查") { model.checkForUpdates() }
                        .disabled(model.updateCheckState == .checking)
                    Spacer()
                    Button("前往 GitHub 下载") { model.openDownloadPage() }
                        .keyboardShortcut(.defaultAction)
                }

                Text("新版本发布在 GitHub Releases。检测到新版本时会弹窗提醒，也可随时点上方按钮前往下载安装包。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("开源与下载") {
                Link("GitHub Releases", destination: UpdateChecker.releasesURL)
                Text("仓库：github.com/iamxz/PunchClock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var updateStatusRow: some View {
        switch model.updateCheckState {
        case .idle:
            Text("尚未检查更新").foregroundStyle(.secondary)
        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("正在检查更新…").foregroundStyle(.secondary)
            }
        case .upToDate:
            Label("已是最新版本", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .available:
            if let res = model.updateResult {
                Label("发现新版本 \(res.latestVersion.description)", systemImage: "arrow.down.circle.fill")
                    .foregroundStyle(.blue)
            } else {
                Label("发现新版本", systemImage: "arrow.down.circle.fill")
                    .foregroundStyle(.blue)
            }
        case .error:
            Label("检查更新失败（可能离线）", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        }
    }
}
