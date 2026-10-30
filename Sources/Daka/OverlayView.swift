import SwiftUI
import DakaCore

@MainActor
final class OverlayModel: ObservableObject {
    @Published var tasks: [PunchTask] = []
    @Published var settings: DakaCore.Settings = .default
    @Published var now: Date = Date()
    @Published var record: DakaCore.DayRecord = .init()
    /// 遮罩被收起（ESC 暂停、结束预览）时递增，用于中止进行中的长按，
    /// 避免窗口藏起来后计时器照样跑完、悄悄打卡。
    @Published private(set) var pressCancelSignal = 0
    var onPunch: (PunchTask) -> Void = { _ in }

    func cancelPresses() {
        pressCancelSignal &+= 1
    }
}

/// 打卡按钮：圆形大按钮，长按 3 秒（3-2-1 倒计时）才算完成打卡，避免误触；
/// 配色与菜单栏环形按钮一致（上班绿、下班蓝）。
struct OverlayPunchButton: View {
    let task: PunchTask
    let cancelSignal: Int
    let onComplete: (PunchTask) -> Void

    @StateObject private var press = PunchPressModel()

    private static let duration: CGFloat = 3

    private var tint: Color { task == .morning ? .green : .blue }

    var body: some View {
        ZStack {
            Circle().fill(tint.opacity(press.isActive ? 0.5 : 0.32))
            Circle().strokeBorder(tint, lineWidth: 3)
            Circle()
                .inset(by: 11)
                .stroke(tint.opacity(0.22), lineWidth: 6)
            Circle()
                .inset(by: 11)
                .trim(from: 0, to: press.progress)
                .stroke(tint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            label
        }
        .frame(width: 150, height: 150)
        .contentShape(Circle())
        .scaleEffect(press.isActive ? 0.97 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: press.isActive)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in press.start { onComplete(task) } }
                .onEnded { _ in press.cancel() }
        )
        .onChange(of: task) { _, _ in press.cancel() }
        .onChange(of: cancelSignal) { _, _ in press.cancel() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(task.title))
        .accessibilityHint(Text("长按 3 秒完成打卡；旁白可直接操作"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Text("完成打卡")) { onComplete(task) }
    }

    @ViewBuilder
    private var label: some View {
        if press.isActive {
            VStack(spacing: 0) {
                Text(task.title)
                    .font(.system(size: 14, weight: .medium))
                    .opacity(0.8)
                Text("\(remainingSeconds)")
                    .font(.system(size: 56, weight: .bold))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.easeOut(duration: 0.18), value: remainingSeconds)
            }
            .foregroundStyle(.white)
        } else {
            Text(task.title)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    private var remainingSeconds: Int {
        max(1, Int(ceil(Self.duration * (1 - press.progress))))
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
                                    cancelSignal: model.pressCancelSignal,
                                    onComplete: model.onPunch
                                )
                            }
                        }
                        VStack(spacing: 6) {
                            Text("长按圆形按钮 3 秒完成打卡")
                                .foregroundStyle(.white.opacity(0.75))
                            Text("ESC 可暂停，过提醒间隔后重新弹出")
                                .foregroundStyle(.gray)
                        }
                        .font(.system(size: 14))
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
