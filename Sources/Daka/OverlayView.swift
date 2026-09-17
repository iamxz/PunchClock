import SwiftUI
import DakaCore

@MainActor
final class OverlayModel: ObservableObject {
    @Published var tasks: [PunchTask] = []
    @Published var settings: DakaCore.Settings = .default
    @Published var now: Date = Date()
    @Published var message: String?
    @Published var healthAlerts: [HealthAlert] = []
    var onPunch: (PunchTask) -> Void = { _ in }
    var onWater: () -> Void = {}
    var onMovement: () -> Void = {}
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
                ForEach(model.tasks, id: \.self) { task in
                    VStack(spacing: 8) {
                        Button {
                            model.onPunch(task)
                        } label: {
                            Text(task.title)
                                .font(.system(size: 26, weight: .semibold))
                                .frame(width: 260, height: 64)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(task == .morning ? .green : .blue)

                        if let overdue = overdueText(for: task) {
                            Text(overdue)
                                .font(.system(size: 18))
                                .foregroundStyle(.orange)
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
