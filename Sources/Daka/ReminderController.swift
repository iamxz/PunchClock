import AppKit
import SwiftUI
import DakaCore

/// 全屏遮罩窗口：置顶、跨所有 Space、拦截 ESC/关闭快捷键。
final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {}

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command),
           let chars = event.charactersIgnoringModifiers?.lowercased(),
           ["q", "w", "m", "h"].contains(chars) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { return } // ESC
        super.keyDown(with: event)
    }

    override func performClose(_ sender: Any?) {}
    override func performMiniaturize(_ sender: Any?) {}
}

@MainActor
final class ReminderController: ReminderPresenting {
    private let reassertInterval: TimeInterval
    private let overlayModel = OverlayModel()
    private var windows: [OverlayWindow] = []
    private var builtFrames: [CGRect] = []
    private var reassertTimer: Timer?
    private var currentTasks: [PunchTask] = []
    private var currentLevel: ReminderLevel?
    private var gentleTasks: [PunchTask] = []
    private let notifier = GentleNotifier()
    private var lastNotifyAt: Date?

    init(interval: TimeInterval, onPunch: @escaping (PunchTask) -> Void) {
        self.reassertInterval = interval
        self.overlayModel.onPunch = onPunch
        notifier.requestAuthorizationIfNeeded()
    }

    func showGentle(tasks: [PunchTask], settings: DakaCore.Settings, now: Date) {
        currentLevel = .gentle
        gentleTasks = tasks
        currentTasks = []
        overlayModel.tasks = tasks
        overlayModel.settings = settings
        overlayModel.now = now
        stopReassertTimer()
        for w in windows { w.orderOut(nil) }
        notifier.notify(tasks: tasks)
        lastNotifyAt = now
    }

    func showHard(tasks: [PunchTask], settings: DakaCore.Settings, now: Date) {
        currentLevel = .hard
        gentleTasks = []
        currentTasks = tasks
        overlayModel.tasks = tasks
        overlayModel.settings = settings
        overlayModel.now = now
        rebuildWindowsIfNeeded()
        for w in windows { w.makeKeyAndOrderFront(nil) }
        NSApp.activate(ignoringOtherApps: true)
        startReassertTimer()
    }

    func refresh(settings: DakaCore.Settings, now: Date) {
        overlayModel.settings = settings
        overlayModel.now = now
        if currentLevel == .hard {
            rebuildWindowsIfNeeded()
        } else if currentLevel == .gentle {
            if let last = lastNotifyAt, now.timeIntervalSince(last) >= settings.effectiveReminderIntervalSeconds {
                notifier.notify(tasks: gentleTasks)
                lastNotifyAt = now
            }
        }
    }

    func hide() {
        stopReassertTimer()
        currentLevel = nil
        gentleTasks = []
        currentTasks = []
        lastNotifyAt = nil
        for w in windows { w.orderOut(nil) }
    }

    deinit {
        reassertTimer?.invalidate()
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

        if !currentTasks.isEmpty {
            for window in windows { window.makeKeyAndOrderFront(nil) }
            NSApp.activate(ignoringOtherApps: true)
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
