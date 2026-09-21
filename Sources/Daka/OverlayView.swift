import SwiftUI
import DakaCore

@MainActor
final class OverlayModel: ObservableObject {
    @Published var tasks: [PunchTask] = []
    @Published var settings: DakaCore.Settings = .default
    @Published var now: Date = Date()
    @Published var record: DakaCore.DayRecord = .init()
    var onPunch: (PunchTask) -> Void = { _ in }
}

/// 打卡按钮：纯点击触发。边框风格与菜单（.bordered 蓝色描边）保持一致，
/// 在纯黑遮罩上用明确的蓝色描边保证可见。
struct OverlayPunchButton: View {
    let task: PunchTask
    let onComplete: (PunchTask) -> Void

    var body: some View {
        Button {
            onComplete(task)
        } label: {
            Text(task.title)
                .font(.system(size: 20, weight: .semibold))
                .frame(width: 200, height: 60)
        }
        .buttonStyle(BorderedPunchButtonStyle())
    }
}

/// 模仿菜单中 .bordered 的蓝色描边按钮，但用显式颜色，确保纯黑背景上始终可见。
private struct BorderedPunchButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.blue.opacity(configuration.isPressed ? 0.30 : 0.14))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.blue.opacity(configuration.isPressed ? 1.0 : 0.6),
                                  lineWidth: 1.5)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.7),
                       value: configuration.isPressed)
    }
}

struct OverlayView: View {
    @ObservedObject var model: OverlayModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.96).ignoresSafeArea()
            // ScrollView 兜底：副屏/低分辨率屏放不下固定字号内容时改为可滚动，避免被裁切。
            ScrollView {
                VStack(spacing: 30) {
                    Image(systemName: "alarm.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.yellow)
                    Text(promptTitle)
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.6)
                    Text("当前时间 " + Self.timeFormatter.string(from: model.now))
                        .font(.system(size: 22))
                        .foregroundStyle(.gray)
                        .monospacedDigit()
                    HStack(spacing: 48) {
                        ForEach(model.tasks, id: \.self) { task in
                            OverlayPunchButton(
                                task: task,
                                onComplete: model.onPunch
                            )
                        }
                    }
                    Text("ESC 可暂停，过提醒间隔后重新弹出")
                        .font(.system(size: 14))
                        .foregroundStyle(.gray)
                }
                .padding(48)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(.dark)
    }

    private var promptTitle: String {
        switch model.tasks {
        case [.morning]: return "该上班打卡了"
        case [.evening]: return "该下班打卡了"
        case []: return "打卡完成"
        default: return "还有打卡未完成"
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}
