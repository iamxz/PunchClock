import AppKit
import SwiftUI
import DakaCore

/// 全屏遮罩窗口：置顶、跨所有 Space、拦截 ESC/关闭快捷键。
final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    var onEscape: (() -> Void)?

    override func cancelOperation(_ sender: Any?) { onEscape?() }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command),
           let chars = event.charactersIgnoringModifiers?.lowercased(),
           ["q", "w", "m", "h"].contains(chars) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onEscape?(); return } // ESC：暂停提醒
        super.keyDown(with: event)
    }

    override func performClose(_ sender: Any?) {}
    override func performMiniaturize(_ sender: Any?) {}
}

@MainActor
final class ReminderController: @preconcurrency ReminderPresenting {
    private var reassertInterval: TimeInterval
    private let overlayModel = OverlayModel()
    private var windows: [OverlayWindow] = []
    private var builtFrames: [CGRect] = []
    private var reassertTimer: Timer?
    private var snoozeTimer: Timer?
    private var currentTasks: [PunchTask] = []

    init(interval: TimeInterval, onPunch: @escaping (PunchTask) -> Void) {
        self.reassertInterval = interval
        self.overlayModel.onPunch = onPunch
    }

    func showHard(tasks: [PunchTask], settings: DakaCore.Settings, now: Date) {
        snoozeTimer?.invalidate()
        snoozeTimer = nil
        overlayModel.message = nil
        currentTasks = tasks
        overlayModel.tasks = tasks
        overlayModel.settings = settings
        overlayModel.now = now
        reassertInterval = settings.effectiveReminderIntervalSeconds
        rebuildWindowsIfNeeded()
        for w in windows { w.makeKeyAndOrderFront(nil) }
        NSApp.activate(ignoringOtherApps: true)
        stopReassertTimer()
        startReassertTimer()
    }

    func refresh(settings: DakaCore.Settings, now: Date) {
        overlayModel.settings = settings
        overlayModel.now = now
        let desired = settings.effectiveReminderIntervalSeconds
        if desired != reassertInterval {
            reassertInterval = desired
            stopReassertTimer()
            startReassertTimer()
        }
        rebuildWindowsIfNeeded()
    }

    func hide() {
        stopReassertTimer()
        currentTasks = []
        for w in windows { w.orderOut(nil) }
        snoozeTimer?.invalidate()
        snoozeTimer = nil
        overlayModel.message = nil
    }

    deinit {
        reassertTimer?.invalidate()
        snoozeTimer?.invalidate()
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
            window.onEscape = { [weak self] in self?.snooze() }
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

    func snooze() {
        guard !currentTasks.isEmpty else { return }
        stopReassertTimer()
        for w in windows { w.orderOut(nil) }
        snoozeTimer?.invalidate()
        let t = Timer(timeInterval: reassertInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.resume() }
        }
        RunLoop.main.add(t, forMode: .common)
        snoozeTimer = t
    }

    func showMessage(_ text: String?) {
        overlayModel.message = text
    }

    private func resume() {
        snoozeTimer?.invalidate()
        snoozeTimer = nil
        guard !currentTasks.isEmpty else { return }
        rebuildWindowsIfNeeded()
        for w in windows { w.makeKeyAndOrderFront(nil) }
        NSApp.activate(ignoringOtherApps: true)
        startReassertTimer()
    }
}
