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
            let created = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 600),
                                   styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                   backing: .buffered,
                                   defer: false)
            created.title = "打工人爱护自己"
            let toolbar = NSToolbar(identifier: "MainWindowToolbar")
            toolbar.displayMode = .iconOnly
            created.toolbar = toolbar
            created.isReleasedWhenClosed = false
            created.contentViewController = NSHostingController(rootView: ControlCenterView(model: model))
            created.setContentSize(NSSize(width: 860, height: 600))
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
