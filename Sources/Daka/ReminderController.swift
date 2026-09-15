import AppKit
import SwiftUI
import DakaCore

/// 全屏遮罩窗口：置顶、跨所有 Space、拦截 ESC/关闭快捷键。
final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {}

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { return } // ESC
        if event.modifierFlags.contains(.command),
           let chars = event.charactersIgnoringModifiers?.lowercased(),
           ["q", "w", "m", "h"].contains(chars) {
            return
        }
        super.keyDown(with: event)
    }
}

@MainActor
final class ReminderController: ReminderPresenting {
    private let reassertInterval: TimeInterval
    private let overlayModel = OverlayModel()
    private var windows: [OverlayWindow] = []
    private var builtFrames: [CGRect] = []
    private var reassertTimer: Timer?
    private var currentTasks: [PunchTask] = []

    init(interval: TimeInterval, onPunch: @escaping (PunchTask) -> Void) {
        self.reassertInterval = interval
        self.overlayModel.onPunch = onPunch
    }

    func show(tasks: [PunchTask], now: Date) {
        currentTasks = tasks
        overlayModel.tasks = tasks
        overlayModel.now = now
        rebuildWindowsIfNeeded()
        for w in windows { w.makeKeyAndOrderFront(nil) }
        NSApp.activate(ignoringOtherApps: true)
        startReassertTimer()
    }

    func refresh(now: Date) {
        overlayModel.now = now
    }

    func hide() {
        stopReassertTimer()
        currentTasks = []
        for w in windows { w.orderOut(nil) }
    }

    private func rebuildWindowsIfNeeded() {
        let screens = NSScreen.screens
        let frames = screens.map { $0.frame }
        if frames == builtFrames, windows.count == screens.count { return }
        builtFrames = frames
        for w in windows { w.orderOut(nil) }

        windows = screens.map { screen in
            let window = OverlayWindow(contentRect: screen.frame,
                                       styleMask: .borderless,
                                       backing: .buffered,
                                       defer: false,
                                       screen: screen)
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.isOpaque = true
            window.backgroundColor = .black
            window.hasShadow = false
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: OverlayView(model: overlayModel))
            return window
        }
    }

    private func startReassertTimer() {
        guard reassertTimer == nil else { return }
        let t = Timer(timeInterval: reassertInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.currentTasks.isEmpty else { return }
                for w in self.windows { w.makeKeyAndOrderFront(nil) }
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        RunLoop.main.add(t, forMode: .common)
        reassertTimer = t
    }

    private func stopReassertTimer() {
        reassertTimer?.invalidate()
        reassertTimer = nil
    }
}
