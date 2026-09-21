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
    private var isSnoozed = false

    init(interval: TimeInterval, onPunch: @escaping (PunchTask) -> Void) {
        self.reassertInterval = interval
        self.overlayModel.onPunch = onPunch
    }

    func showHard(tasks: [PunchTask], settings: DakaCore.Settings, record: DayRecord, now: Date) {
        snoozeTimer?.invalidate()
        snoozeTimer = nil
        isSnoozed = false
        currentTasks = tasks
        overlayModel.tasks = tasks
        overlayModel.settings = settings
        overlayModel.record = record
        overlayModel.now = now
        reassertInterval = settings.effectiveReminderIntervalSeconds
        syncOverlay(activate: true)
    }

    func refresh(settings: DakaCore.Settings, record: DayRecord, now: Date) {
        overlayModel.settings = settings
        overlayModel.record = record
        overlayModel.now = now
        let desired = settings.effectiveReminderIntervalSeconds
        if desired != reassertInterval {
            reassertInterval = desired
            if isSnoozed {
                scheduleSnooze()
            } else {
                stopReassertTimer()
                startReassertTimer()
            }
        }
        if !isSnoozed { rebuildWindowsIfNeeded() }
    }

    func hide() {
        stopReassertTimer()
        currentTasks = []
        syncOverlay(activate: false)
    }

    deinit {
        reassertTimer?.invalidate()
        snoozeTimer?.invalidate()
    }

    private var hasContent: Bool {
        !currentTasks.isEmpty
    }

    private func syncOverlay(activate: Bool) {
        guard !isSnoozed else { return }
        if hasContent {
            rebuildWindowsIfNeeded()
            if activate {
                presentWindows()
            }
            startReassertTimer()
        } else {
            stopReassertTimer()
            snoozeTimer?.invalidate()
            snoozeTimer = nil
            isSnoozed = false
            for w in windows { w.orderOut(nil) }
        }
    }

    /// 每块屏一个遮罩窗口；只有主屏窗口成为 key window，
    /// 其余仅置前显示 —— 多窗口循环抢 key 会导致其它屏显示/交互异常。
    private func presentWindows() {
        let screens = NSScreen.screens
        let keyScreen = NSScreen.main ?? screens.first
        let keyWindow = keyScreen.flatMap { key in
            windows.first { abs($0.frame.minX - key.frame.minX) < 1
                && abs($0.frame.minY - key.frame.minY) < 1 }
        } ?? windows.first
        for window in windows {
            if window === keyWindow {
                window.makeKeyAndOrderFront(nil)
            } else {
                window.orderFrontRegardless()
            }
        }
        NSApp.activate(ignoringOtherApps: true)
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
            // 背景交给 SwiftUI（Color.black.opacity(0.96)）绘制，窗口本身保持透明，
            // 避免「不透明黑窗 + 半透明内容」两层背景在部分屏幕上渲染不一致。
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: OverlayView(model: overlayModel))
            window.onEscape = { [weak self] in self?.snooze() }
            return window
        }

        if hasContent, !isSnoozed {
            presentWindows()
        }
    }

    private func startReassertTimer() {
        guard !isSnoozed else { return }
        let desired = reassertInterval
        if let reassertTimer, reassertTimer.timeInterval == desired { return }
        reassertTimer?.invalidate()
        let t = Timer(timeInterval: desired, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isSnoozed, self.hasContent else { return }
                self.presentWindows()
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
        guard hasContent, !isSnoozed else { return }
        stopReassertTimer()
        for w in windows { w.orderOut(nil) }
        isSnoozed = true
        scheduleSnooze()
    }

    private func snoozeInterval() -> TimeInterval {
        reassertInterval
    }

    private func scheduleSnooze() {
        snoozeTimer?.invalidate()
        let t = Timer(timeInterval: snoozeInterval(), repeats: false) { [weak self] _ in
            Task { @MainActor in self?.resume() }
        }
        RunLoop.main.add(t, forMode: .common)
        snoozeTimer = t
    }

    private func resume() {
        snoozeTimer?.invalidate()
        snoozeTimer = nil
        isSnoozed = false
        syncOverlay(activate: true)
    }
}
