import SwiftUI
import DakaCore

struct PetView: View {
    @ObservedObject var model: AppModel
    let onOpenPanel: () -> Void

    @State private var animate = false

    private var mood: PetMood {
        PetMood.resolve(reminderState: model.reminderState,
                        now: model.now,
                        health: model.healthStatus)
    }

    var body: some View {
        ZStack {
            bubble
            Text(mood.emoji)
                .font(.system(size: 26))
                .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
        }
        .frame(width: 52, height: 52)
        .padding(4)
        .rotationEffect(.degrees(animate ? 2 : -2))
        .scaleEffect(animate ? 1.02 : 0.98)
        .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: animate)
        .contentShape(Circle())
        .onTapGesture { onOpenPanel() }
        .contextMenu {
            Button("打开控制中心") { model.openControlCenter() }
            Button(model.petVisible ? "隐藏桌宠" : "显示桌宠") { model.setPetVisible(!model.petVisible) }
        }
        .onAppear { animate = true }
        .help("点击打开 打工人爱护自己 工具面板")
    }

    /// 吹泡泡那种透明玻泡：淡渐变填充 + 反光边 + 高光。
    private var bubble: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color.white.opacity(0.38),
                            Color(red: 0.62, green: 0.82, blue: 1.0).opacity(0.16),
                            Color.white.opacity(0.30)
                        ]),
                        center: .center,
                        startRadius: 1,
                        endRadius: 27
                    )
                )
                .overlay(
                    Circle().strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.95), .white.opacity(0.20)],
                                       startPoint: .topLeading,
                                       endPoint: .bottomTrailing),
                        lineWidth: 1.2
                    )
                )
                .shadow(color: .black.opacity(0.14), radius: 3, y: 2)

            Ellipse()
                .fill(.white.opacity(0.85))
                .frame(width: 12, height: 8)
                .rotationEffect(.degrees(-25))
                .blur(radius: 1.2)
                .offset(x: -10, y: -13)

            Circle()
                .fill(.white.opacity(0.55))
                .frame(width: 4, height: 4)
                .blur(radius: 0.8)
                .offset(x: 12, y: 12)
        }
    }
}
