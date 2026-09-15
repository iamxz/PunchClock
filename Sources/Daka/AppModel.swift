import Foundation
import AppKit
import SwiftUI
import DakaCore

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published private(set) var record: DayRecord
    @Published private(set) var settings: DakaCore.Settings
    @Published private(set) var hasPendingTasks = false
    @Published var errorMessage: String?
    @Published var startupWarning: String?

    private let store: PunchStore
    private let clock: AdjustableClock
    private var scheduler: Scheduler?
    private var reminder: ReminderController?

    init(clock: AdjustableClock = AdjustableClock(), store: PunchStore? = nil) {
        let resolvedStore = store ?? PunchStore(fileURL: PunchStore.defaultFileURL())
        self.clock = clock
        self.store = resolvedStore
        self.settings = resolvedStore.data.settings
        self.record = resolvedStore.record(for: clock.now)
    }

    func start() {
        var warnings: [String] = []
        if let registerError = LoginItemManager.registerIfNeeded() {
            warnings.append(registerError)
        }
        if store.didRecoverFromCorruption {
            warnings.append("打卡记录文件损坏，已备份并重置。" +
                (store.corruptionBackupURL.map { "备份：\($0.lastPathComponent)" } ?? ""))
        }
        if !warnings.isEmpty {
            startupWarning = warnings.joined(separator: "\n")
        }

        let reminder = ReminderController(interval: settings.reminderIntervalSeconds) { [weak self] task in
            self?.punch(task)
        }
        self.reminder = reminder

        let scheduler = Scheduler(clock: clock, store: store, presenter: reminder,
                                  launchForced: true, interval: 1)
        scheduler.onStateChange = { [weak self] tasks in
            guard let self else { return }
            self.hasPendingTasks = !tasks.isEmpty
            self.refreshRecord()
        }
        self.scheduler = scheduler

        NotificationCenter.default.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduler?.tick() }
        }
        NotificationCenter.default.addObserver(
            forName: .NSSystemClockDidChange,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduler?.tick() }
        }
        NotificationCenter.default.addObserver(
            forName: .NSSystemTimeZoneDidChange,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduler?.tick() }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduler?.tick() }
        }

        scheduler.start()
    }

    func refreshRecord() {
        record = store.record(for: clock.now)
        settings = store.data.settings
    }

    func punch(_ task: PunchTask) {
        errorMessage = nil
        do {
            try store.mark(task, at: clock.now)
            refreshRecord()
            scheduler?.tick()
        } catch {
            errorMessage = "打卡记录写入失败：\(error.localizedDescription)"
        }
    }

    func setSkipped(_ skipped: Bool) {
        errorMessage = nil
        do {
            try store.setSkipped(skipped, on: clock.now)
            refreshRecord()
            scheduler?.tick()
        } catch {
            errorMessage = "保存失败：\(error.localizedDescription)"
        }
    }

    func setEnabled(_ enabled: Bool) { updateSettings { $0.enabled = enabled } }
    func updateMorning(_ hhmm: String) { updateSettings { $0.morningTime = hhmm } }
    func updateEvening(_ hhmm: String) { updateSettings { $0.eveningTime = hhmm } }

    private func updateSettings(_ mutate: (inout DakaCore.Settings) -> Void) {
        errorMessage = nil
        var s = store.data.settings
        mutate(&s)
        do {
            try store.updateSettings(s)
            refreshRecord()
            scheduler?.tick()
        } catch {
            errorMessage = "设置保存失败：\(error.localizedDescription)"
        }
    }

    func debugAdvanceClock(by seconds: TimeInterval) {
        clock.addOffset(seconds)
        scheduler?.tick()
    }

    func resetClock() {
        clock.reset()
        scheduler?.tick()
    }

    func repairLoginItem() {
        errorMessage = LoginItemManager.registerIfNeeded()
        objectWillChange.send()
    }

    func quit() {
        NSApp.terminate(nil)
    }
}
