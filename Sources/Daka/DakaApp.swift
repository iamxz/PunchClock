import SwiftUI
import DakaCore

@main
struct DakaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(model: model)
        } label: {
            Image(nsImage: MenuBarProgressImage.make(
                fraction: CGFloat(WorkProgress.fraction(model.record,
                                                        now: model.now,
                                                        settings: model.settings,
                                                        leaves: model.leaves)),
                badge: !model.reminderState.isEmpty))
        }
        .menuBarExtraStyle(.window)
    }
}
