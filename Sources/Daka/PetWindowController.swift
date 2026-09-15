import AppKit
import SwiftUI

@MainActor
final class PetWindowController: NSObject {
    private let model: AppModel
    private var window: NSWindow?
    private var popover: NSPopover?
    private let frameKey = "pet.frame"
    private let petSize = NSSize(width: 130, height: 130)

    init(model: AppModel) {
        self.model = model
        super.init()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func show() {
        buildIfNeeded()
        window?.orderFrontRegardless()
    }

    func hide() {
        popover?.close()
        window?.orderOut(nil)
    }

    @objc private func saveFrame() {
        guard let window else { return }
        UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: frameKey)
    }

    private func buildIfNeeded() {
        guard window == nil else { return }
        let created = NSWindow(contentRect: NSRect(origin: restoredOrigin(), size: petSize),
                               styleMask: [.borderless],
                               backing: .buffered,
                               defer: false)
        created.isOpaque = false
        created.backgroundColor = .clear
        created.hasShadow = false
        created.level = .floating
        created.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        created.isMovableByWindowBackground = true
        created.isReleasedWhenClosed = false
        created.contentView = NSHostingView(rootView: PetView(model: model, onOpenPanel: { [weak self] in
            self?.togglePanel()
        }))
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(saveFrame),
                                               name: NSWindow.didMoveNotification,
                                               object: created)
        window = created
    }

    private func restoredOrigin() -> NSPoint {
        if let saved = UserDefaults.standard.string(forKey: frameKey) {
            let frame = NSRectFromString(saved)
            if frame.width > 0, NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) {
                return frame.origin
            }
        }
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSPoint(x: visible.maxX - petSize.width - 40, y: visible.minY + 40)
    }

    private func togglePanel() {
        guard let window, let view = window.contentView else { return }
        if let popover, popover.isShown {
            popover.close()
            return
        }
        let panel = NSPopover()
        panel.behavior = .transient
        panel.contentSize = NSSize(width: 260, height: 400)
        panel.contentViewController = NSHostingController(
            rootView: ToolPanelView(model: model, onClose: { [weak self] in self?.popover?.close() }))
        panel.show(relativeTo: view.bounds, of: view, preferredEdge: .maxX)
        popover = panel
    }
}
