import SwiftUI

struct PetSpeechBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(width: 220, height: 52)
            .background(Color(nsColor: .controlBackgroundColor),
                       in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.black.opacity(0.12))
            )
    }
}
