import AppKit
import SwiftUI

@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private var window: NSWindow?

    init(model: AppModel) {
        self.model = model
        super.init()
    }

    func show() {
        if window == nil {
            let hosting = NSHostingView(rootView: MainWindowView(model: model))
            let created = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 580),
                                   styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                   backing: .buffered,
                                   defer: false)
            created.title = "Daka"
            created.isReleasedWhenClosed = false
            created.contentView = hosting
            created.delegate = self
            created.center()
            created.setFrameAutosaveName("DakaMainWindow")
            window = created
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}
