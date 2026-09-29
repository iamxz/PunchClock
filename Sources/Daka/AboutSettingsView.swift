import SwiftUI
import DakaCore

struct AboutSettingsView: View {
    @ObservedObject var model: AppModel

    /// 解锁测试面板：连点应用名达到该次数即开启，间隔超过 `tapResetInterval` 重新计数。
    private static let unlockTaps = 5
    private static let tapResetInterval: TimeInterval = 2.5

    @State private var titleTaps = 0
    @State private var lastTitleTap: Date?

    private var currentVersionText: String {
        UpdateChecker.shared.currentVersion?.description ?? "未知"
    }

    var body: some View {
        Form {
            Section("当前版本") {
                HStack {
                    Button(action: tapAppTitle) {
                        Text("小打卡")
                    }
                    .buttonStyle(.plain)
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
        // 连点只在「同一次停留在关于页」内累计：离开再回来重新开始。
        .onAppear {
            titleTaps = 0
            lastTitleTap = nil
        }
    }

    /// 连点「小打卡」解锁测试面板；只在刚解锁时提示一次。
    private func tapAppTitle() {
        let now = Date()
        if let last = lastTitleTap, now.timeIntervalSince(last) > Self.tapResetInterval {
            titleTaps = 0
        }
        lastTitleTap = now
        titleTaps += 1
        guard titleTaps >= Self.unlockTaps else { return }
        titleTaps = 0
        guard model.unlockDebugPanel() else { return }
        ToastCenter.shared.show(ToastCenter.Toast(title: "测试面板已开启",
                                                 body: "已加进左侧「设置」列表，回到本页后会重新隐藏。",
                                                 icon: "hammer"),
                               duration: 6)
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
