import SwiftUI

struct PunchToolView: View {
    @ObservedObject var model: AppModel
    @State private var tab = 0

    var body: some View {
        VStack(spacing: 12) {
            Picker("", selection: $tab) {
                Text("统计").tag(0)
                Text("设置").tag(1)
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
            .padding(.top, 8)

            if tab == 0 {
                StatisticsView(model: model)
            } else {
                SettingsView(model: model)
            }
        }
    }
}
