import SwiftUI
import DakaCore

@MainActor
final class OverlayModel: ObservableObject {
    @Published var tasks: [PunchTask] = []
    @Published var settings: DakaCore.Settings = .default
    @Published var now: Date = Date()
    @Published var message: String?
    @Published var healthAlerts: [HealthAlert] = []
    @Published var record: DakaCore.DayRecord = .init()
    var onPunch: (PunchTask) -> Void = { _ in }
    var onWater: () -> Void = {}
    var onMovement: () -> Void = {}
}

@MainActor
final class OverlayPressModel: ObservableObject {
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

struct OverlayPunchButton: View {
    let task: PunchTask
    let record: DayRecord
    let now: Date
    let settings: DakaCore.Settings
    let onComplete: (PunchTask) -> Void

    @StateObject private var press = OverlayPressModel()

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: press.progress > 0 ? press.progress : ringFraction)
                    .stroke(tint, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text(task.title)
                        .font(.system(size: 18, weight: .semibold))
                        .monospacedDigit()
                    if press.progress > 0 {
                        Text("\(Int(press.progress * 100))%")
                            .font(.system(size: 14))
                            .monospacedDigit()
                    }
                }
                .foregroundStyle(tint)
            }
            .frame(width: 140, height: 140)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in press.start { onComplete(task) } }
                    .onEnded { _ in press.cancel() }
            )
            if press.progress == 0 {
                Text("长按打卡")
                    .font(.system(size: 14))
                    .foregroundStyle(.gray)
            }
        }
    }

    private var isEveningComplete: Bool {
        AttendanceRule.isEveningComplete(record, settings: settings, on: now, calendar: .current)
    }

    private var ringFraction: CGFloat {
        CGFloat(WorkProgress.fraction(record, now: now, settings: settings))
    }

    private var tint: Color {
        if isEveningComplete { return .green }
        return task == .morning ? .green : .blue
    }
}

struct OverlayView: View {
    @ObservedObject var model: OverlayModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.96).ignoresSafeArea()
            VStack(spacing: 26) {
                Image(systemName: "alarm.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.yellow)
                Text(promptTitle)
                    .font(.system(size: 46, weight: .bold))
                    .foregroundStyle(.white)
                Text("当前时间 " + Self.timeFormatter.string(from: model.now))
                    .font(.system(size: 22))
                    .foregroundStyle(.gray)
                if let message = model.message {
                    Text(message)
                        .font(.system(size: 18))
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 560)
                }
                HStack(spacing: 40) {
                    ForEach(model.tasks, id: \.self) { task in
                        VStack(spacing: 8) {
                            OverlayPunchButton(
                                task: task,
                                record: model.record,
                                now: model.now,
                                settings: model.settings,
                                onComplete: model.onPunch
                            )
                            if let overdue = overdueText(for: task) {
                                Text(overdue)
                                    .font(.system(size: 18))
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
                ForEach(model.healthAlerts) { alert in
                    VStack(spacing: 10) {
                        Label(alert.title,
                              systemImage: alert.kind == .water ? "drop.fill" : "figure.walk")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.white)
                        Text(alert.body)
                            .font(.system(size: 20))
                            .foregroundStyle(.yellow)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 560)
                        Button {
                            if alert.kind == .water { model.onWater() } else { model.onMovement() }
                        } label: {
                            Text(alert.kind == .water ? "已喝水" : "已起身")
                                .font(.system(size: 22, weight: .semibold))
                                .frame(width: 240, height: 56)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(alert.kind == .water ? .blue : .green)
                    }
                }
                Text("ESC 可暂停，过提醒间隔后重新弹出")
                    .font(.system(size: 14))
                    .foregroundStyle(.gray)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var promptTitle: String {
        switch model.tasks {
        case [.morning]: return "该上班打卡了"
        case [.evening]: return "该下班打卡了"
        case []: return model.healthAlerts.isEmpty ? "打卡完成" : "健康提醒"
        default: return "还有打卡未完成"
        }
    }

    private func overdueText(for task: PunchTask) -> String? {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        guard let start = fmt.date(from: model.settings.workStartTime) else { return nil }
        let endInterval = task == .morning
            ? model.settings.workDuration
            : model.settings.workDuration + model.settings.flexDuration
        let due = start.addingTimeInterval(endInterval)
        guard model.now > due else { return nil }
        let seconds = Int(model.now.timeIntervalSince(due))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 {
            return "已欠 \(hours) 小时 \(minutes) 分"
        }
        return "已欠 \(minutes) 分"
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}
