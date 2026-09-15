import SwiftUI
import DakaCore

@MainActor
final class OverlayModel: ObservableObject {
    @Published var tasks: [PunchTask] = []
    @Published var settings: DakaCore.Settings = .default
    @Published var now: Date = Date()
    var onPunch: (PunchTask) -> Void = { _ in }
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
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var promptTitle: String {
        switch model.tasks {
        case [.morning]: return "该上班打卡了"
        case [.evening]: return "该下班打卡了"
        case []: return "打卡完成"
        default: return "还有打卡未完成"
        }
    }

    private func overdueText(for task: PunchTask) -> String? {
        let hhmm = task == .morning ? model.settings.morningDeadline : model.settings.eveningDeadline
        guard let due = DakaDate.date(on: model.now, at: hhmm), model.now > due else { return nil }
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
