import SwiftUI
import DakaCore

struct PetView: View {
    @ObservedObject var model: AppModel
    let onOpenPanel: () -> Void

    @State private var animate = false

    private var mood: PetMood {
        PetMood.resolve(reminderState: model.reminderState, now: model.now)
    }

    var body: some View {
        ZStack {
            BubbleShape()
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.20), radius: 3, y: 2)
            Text(mood.emoji)
                .font(.system(size: 26))
                .offset(y: -3)
        }
        .frame(width: 52, height: 52)
        .offset(y: animate ? -3 : 3)
        .rotationEffect(.degrees(animate ? 6 : -6))
        .scaleEffect(animate ? 1.08 : 0.94)
        .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: animate)
        .contentShape(BubbleShape())
        .onTapGesture { onOpenPanel() }
        .contextMenu {
            Button("打开控制中心") { model.openControlCenter() }
            Button(model.petVisible ? "隐藏桌宠" : "显示桌宠") { model.setPetVisible(!model.petVisible) }
            Divider()
            Button("退出 Daka") { model.quit() }
        }
        .onAppear { animate = true }
        .help("点击打开 Daka 工具面板")
    }
}

/// 对话气泡：上方圆角矩形 + 左下小尾巴。
private struct BubbleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let tailHeight = rect.height * 0.18
        let body = CGRect(x: rect.minX, y: rect.minY,
                          width: rect.width, height: rect.height - tailHeight)
        let radius = min(body.width, body.height) * 0.34
        var path = Path()
        path.addRoundedRect(in: body, cornerSize: CGSize(width: radius, height: radius))

        let baseX = rect.minX + rect.width * 0.26
        path.move(to: CGPoint(x: baseX, y: body.maxY - 1))
        path.addLine(to: CGPoint(x: baseX + rect.width * 0.18, y: body.maxY - 1))
        path.addLine(to: CGPoint(x: baseX - rect.width * 0.02, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
