import SwiftUI
import DakaCore

@MainActor
final class OverlayModel: ObservableObject {
    @Published var tasks: [PunchTask] = []
    @Published var now: Date = Date()
    @Published var settings: DakaCore.Settings = .default
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
                    Button {
                        model.onPunch(task)
                    } label: {
                        Text(task.title)
                            .font(.system(size: 26, weight: .semibold))
                            .frame(width: 260, height: 64)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(task == .morning ? .green : .blue)
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

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}
