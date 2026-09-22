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

/// 打卡按钮：圆形大按钮，纯点击触发；配色与菜单栏环形按钮一致（上班绿、下班蓝）。
struct OverlayPunchButton: View {
    let task: PunchTask
    let onComplete: (PunchTask) -> Void

    var body: some View {
        Button {
            onComplete(task)
        } label: {
            Text(task.title)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 150, height: 150)
        }
        .buttonStyle(CircularPunchButtonStyle(tint: task == .morning ? .green : .blue))
    }
}

private struct CircularPunchButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Circle().fill(tint.opacity(configuration.isPressed ? 0.55 : 0.32))
            )
            .overlay(
                Circle().strokeBorder(tint, lineWidth: 3)
            )
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.7),
                       value: configuration.isPressed)
    }
}

struct OverlayView: View {
    @ObservedObject var model: OverlayModel

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.opacity(0.96)
                // ScrollView 兜底：副屏/低分辨率屏放不下内容时改为可滚动，避免被裁切。
                // minHeight 撑满一屏：内容放得下时垂直居中（ScrollView 本身会把
                // maxHeight: .infinity 提案变成无界高度，导致顶部对齐，故用 minHeight）。
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
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: proxy.size.height)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
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
