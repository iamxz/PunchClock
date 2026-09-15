import SwiftUI
import DakaCore

struct ComingSoonView: View {
    let metadata: ToolMetadata

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: metadata.symbol)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("\(metadata.title) 即将推出")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
