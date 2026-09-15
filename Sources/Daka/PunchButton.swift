import SwiftUI
import DakaCore

@MainActor
final class PunchPressModel: ObservableObject {
    @Published var progress: CGFloat = 0
    private var timer: Timer?
    private var completed = false
    private let duration: TimeInterval = 3

    func start(onComplete: @escaping () -> Void) {
        guard timer == nil, !completed else { return }
        progress = 0
        let steps = 60
        var step = 0
        let interval = duration / Double(steps)
        let newTimer = Timer(timeInterval: interval, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { timer.invalidate(); return }
                step += 1
                self.progress = min(1, CGFloat(step) / CGFloat(steps))
                if step >= steps {
                    timer.invalidate()
                    self.timer = nil
                    self.completed = true
                    self.progress = 1
                    onComplete()
                }
            }
        }
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        completed = false
        withAnimation(.easeOut(duration: 0.2)) { progress = 0 }
    }
}

struct PunchButton: View {
    let task: PunchTask?
    let onComplete: (PunchTask) -> Void

    @StateObject private var press = PunchPressModel()

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: press.progress)
                    .stroke(tint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(task?.title ?? "已完成")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(task == nil ? Color.secondary : tint)
            }
            .frame(width: 108, height: 108)
            .contentShape(Circle())
            .opacity(task == nil ? 0.6 : 1)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard let task else { return }
                        press.start { onComplete(task) }
                    }
                    .onEnded { _ in press.cancel() }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(task?.title ?? "打卡已完成"))
            .accessibilityHint(Text(task == nil ? "今日两次打卡都已完成" : "长按 3 秒完成打卡，或使用旁白操作直接完成"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: Text("完成打卡")) {
                if let task { onComplete(task) }
            }

            if task != nil {
                Text("长按 3 秒完成打卡")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .onChange(of: task) { _, _ in
            press.cancel()
        }
    }

    private var tint: Color {
        switch task {
        case .morning: return .green
        case .evening: return .blue
        case nil: return .secondary
        }
    }
}
