import AppKit
import SwiftUI

@MainActor
final class PetWindowController: NSObject {
    private let model: AppModel
    private var window: NSWindow?
    private var popover: NSPopover?
    private var bubbleWindow: NSWindow?
    private let frameKey = "pet.frame"
    private let petSize = NSSize(width: 60, height: 60)

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
        hideSpeech()
        window?.orderOut(nil)
    }

    func showSpeech(_ text: String) {
        guard !text.isEmpty, let window, window.isVisible else { return }
        let size = NSSize(width: 220, height: 52)
        let panel = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                             styleMask: [.borderless],
                             backing: .buffered,
                             defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: PetSpeechBubble(text: text))

        let petFrame = window.frame
        let screen = window.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? petFrame
        let x = min(max(petFrame.midX - size.width / 2, visible.minX + 4),
                    visible.maxX - size.width - 4)
        var y = petFrame.maxY + 6
        if y + size.height > visible.maxY {
            y = petFrame.minY - size.height - 6
        }
        panel.setFrameOrigin(NSPoint(x: x, y: y))

        bubbleWindow?.orderOut(nil)
        panel.orderFrontRegardless()
        bubbleWindow = panel
    }

    func hideSpeech() {
        bubbleWindow?.orderOut(nil)
        bubbleWindow = nil
    }

    @objc private func saveFrame() {
        guard let window else { return }
        
        // Ensure window stays within visible screen area
        let screen = window.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        var frame = window.frame
        
        // Adjust horizontal position if needed
        if frame.minX < visible.minX {
            frame.origin.x = visible.minX
        } else if frame.maxX > visible.maxX {
            frame.origin.x = visible.maxX - frame.width
        }
        
        // Adjust vertical position if needed
        if frame.minY < visible.minY {
            frame.origin.y = visible.minY
        } else if frame.maxY > visible.maxY {
            frame.origin.y = visible.maxY - frame.height
        }
        
        // Only set frame if it changed
        if frame != window.frame {
            window.setFrame(frame, display: false, animate: false)
        }
        
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
