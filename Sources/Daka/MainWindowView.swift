import SwiftUI

struct MainWindowView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        TabView {
            StatisticsView(model: model)
                .tabItem { Label("统计", systemImage: "chart.bar") }
            SettingsView(model: model)
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
        .padding(16)
        .frame(minWidth: 720, minHeight: 520)
    }
}
