import SwiftUI
import DakaCore

struct PetView: View {
    @ObservedObject var model: AppModel
    let onOpenPanel: () -> Void

    @State private var breathe = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            character
            badge
        }
        .frame(width: 130, height: 130)
        .contentShape(Rectangle())
        .onTapGesture { onOpenPanel() }
        .contextMenu {
            Button("打开控制中心") { model.openControlCenter() }
            Button(model.petVisible ? "隐藏桌宠" : "显示桌宠") { model.setPetVisible(!model.petVisible) }
            Divider()
            Button("退出 Daka") { model.quit() }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
    }

    private var character: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 46, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.38, green: 0.62, blue: 1.0),
                                              Color(red: 0.20, green: 0.35, blue: 0.9)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 104, height: 104)
                .shadow(color: .black.opacity(0.25), radius: 6, y: 3)

            HStack(spacing: 22) {
                eye
                eye
            }
            .offset(y: -8)

            Capsule()
                .fill(.white.opacity(0.9))
                .frame(width: 26, height: 10)
                .offset(y: 22)
        }
        .scaleEffect(breathe ? 1.03 : 0.97)
    }

    private var eye: some View {
        Capsule()
            .fill(.white)
            .frame(width: 14, height: 16)
    }

    private var badge: some View {
        Image(systemName: badgeSymbol)
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(badgeColor)
            .padding(4)
            .background(.regularMaterial, in: Circle())
            .offset(x: 6, y: 4)
    }

    private var badgeSymbol: String {
        if !model.reminderState.hard.isEmpty { return "exclamationmark.triangle.fill" }
        if !model.reminderState.gentle.isEmpty { return "bell.badge.fill" }
        return "checkmark.circle.fill"
    }

    private var badgeColor: Color {
        if !model.reminderState.hard.isEmpty { return .red }
        if !model.reminderState.gentle.isEmpty { return .orange }
        return .green
    }
}
