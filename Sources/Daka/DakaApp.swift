import SwiftUI

@main
struct DakaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(model: model)
        } label: {
            Image(systemName: model.hasPendingTasks ? "exclamationmark.circle.fill" : "checkmark.seal")
        }
        .menuBarExtraStyle(.window)
    }
}
