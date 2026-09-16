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
    let task: PunchTask
    let record: DayRecord
    let nowProvider: () -> Date
    let minWorkDuration: TimeInterval
    let onComplete: (PunchTask) -> Void

    @StateObject private var press = PunchPressModel()

    var body: some View {
        VStack(spacing: 8) {
            TimelineView(.everyMinute) { _ in
                ring
            }
            Text("长按 3 秒打卡")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .onChange(of: task) { _, _ in press.cancel() }
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: 8)
            Circle()
                .trim(from: 0, to: ringFraction)
                .stroke(tint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                ForEach(Array(centerLines.enumerated()), id: \.offset) { index, line in
                    Text(line)
                        .font(.system(size: index == 0 ? 15 : 12,
                                      weight: index == 0 ? .semibold : .regular))
                        .monospacedDigit()
                }
            }
            .foregroundStyle(tint)
        }
        .frame(width: 108, height: 108)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in press.start { onComplete(task) } }
                .onEnded { _ in press.cancel() }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(task.title))
        .accessibilityHint(Text("长按 3 秒完成打卡；旁白可直接操作"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Text("完成打卡")) { onComplete(task) }
    }

    private var isPressing: Bool { press.progress > 0 }

    private var isEveningComplete: Bool {
        PunchRules.isEveningComplete(record, minWorkDuration: minWorkDuration)
    }

    private var ringFraction: CGFloat {
        if isPressing { return press.progress }
        return CGFloat(WorkProgress.fraction(record, now: nowProvider(), minWorkDuration: minWorkDuration))
    }

    private var tint: Color {
        if isEveningComplete && !isPressing { return .green }
        return task == .morning ? .green : .blue
    }

    private var centerLines: [String] {
        if isPressing { return [task.title] }

        var lines: [String] = []
        if let punch = PunchRules.latestPunch(record, task: task) {
            lines.append(Self.timeFormatter.string(from: punch))
        } else {
            lines.append(task.title)
        }
        if let elapsed = WorkProgress.elapsed(record, now: nowProvider(), minWorkDuration: minWorkDuration) {
            lines.append(WorkProgress.hoursText(elapsed))
        }
        return lines
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}
