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
        Text(mood.emoji)
            .font(.system(size: 32))
            .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
            .offset(y: animate ? -3 : 3)
            .rotationEffect(.degrees(animate ? 6 : -6))
            .scaleEffect(animate ? 1.08 : 0.94)
            .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: animate)
            .frame(width: 52, height: 52)
            .contentShape(Rectangle())
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
