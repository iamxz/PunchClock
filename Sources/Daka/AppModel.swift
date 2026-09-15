import Foundation
import AppKit
import SwiftUI
import DakaCore

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published private(set) var record: DayRecord
    @Published private(set) var settings: DakaCore.Settings
    @Published private(set) var reminderState = ReminderState()
    @Published var errorMessage: String?
    @Published var startupWarning: String?
    @Published var scheduledLaunchWarning: String?
    @Published var scheduledLaunchInstalled = false

    @Published var selectedTool: ToolID = .punch
    let tools = ToolCatalog.all

    @Published var petVisible: Bool
    weak var petWindow: PetWindowController?

    weak var mainWindow: MainWindowController?

    var hasHardTasks: Bool { !reminderState.hard.isEmpty }

    /// 唯一放行退出的开关：设置页确认退出、或系统关机时置 true。
    var allowTermination = false

    var now: Date { clock.now }

    var minWorkDuration: TimeInterval { settings.minWorkDuration }

    var effectiveEveningPunch: Date? {
        PunchRules.effectiveEveningPunch(record, minWorkDuration: settings.minWorkDuration)
    }

    var isEveningComplete: Bool {
        PunchRules.isEveningComplete(record, minWorkDuration: settings.minWorkDuration)
    }

    func setMinWorkHours(_ hours: Double) {
        updateSettings { $0.minWorkDurationHours = hours }
    }

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
        self.petVisible = UserDefaults.standard.object(forKey: "pet.visible") as? Bool ?? true
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

        let reminder = ReminderController(interval: settings.effectiveReminderIntervalSeconds) { [weak self] task in
            self?.punch(task)
        }
        self.reminder = reminder

        let scheduler = Scheduler(clock: clock, store: store, presenter: reminder,
                                  interval: 1)
        scheduler.onStateChange = { [weak self] state in
            guard let self else { return }
            self.reminderState = state
            self.refreshRecord()
        }
        self.scheduler = scheduler

        installScheduledLaunch()

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
    func updateMorningStart(_ hhmm: String) { updateSettings { $0.morningWindowStart = hhmm } }
    func updateMorningDeadline(_ hhmm: String) { updateSettings { $0.morningDeadline = hhmm } }
    func updateEveningStart(_ hhmm: String) { updateSettings { $0.eveningWindowStart = hhmm } }
    func updateEveningDeadline(_ hhmm: String) { updateSettings { $0.eveningDeadline = hhmm } }

    private func updateSettings(_ mutate: (inout DakaCore.Settings) -> Void) {
        errorMessage = nil
        var s = store.data.settings
        mutate(&s)
        do {
            try store.updateSettings(s)
            refreshRecord()
            installScheduledLaunch()
            scheduler?.tick()
        } catch {
            errorMessage = "设置保存失败：\(error.localizedDescription)"
        }
    }

    private func installScheduledLaunch() {
        ScheduledLaunchManager.install(settings: store.data.settings) { [weak self] result in
            guard let self else { return }
            self.scheduledLaunchInstalled = result.installed
            self.scheduledLaunchWarning = result.warning
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

    func selectTool(_ id: ToolID) {
        selectedTool = id
    }

    func openControlCenter(selecting id: ToolID? = nil) {
        if let id { selectedTool = id }
        mainWindow?.show()
    }

    func setPetVisible(_ visible: Bool) {
        petVisible = visible
        UserDefaults.standard.set(visible, forKey: "pet.visible")
        if visible { petWindow?.show() } else { petWindow?.hide() }
    }

    func statistics(rangeDays: Int) -> StatisticsSummary {
        Statistics.compute(records: store.data.records,
                           settings: store.data.settings,
                           now: clock.now,
                           rangeDays: rangeDays)
    }

    func setWorkdays(_ days: Set<Int>) {
        updateSettings { $0.workdays = days }
    }

    func quit() {
        NSApp.terminate(nil)
    }

    func confirmQuit() {
        let alert = NSAlert()
        alert.messageText = "退出 Daka？"
        alert.informativeText = "退出后将无法提醒打卡，直到下次开机或手动启动。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "仍要退出")
        alert.addButton(withTitle: "取消")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        allowTermination = true
        NSApp.terminate(nil)
    }
}
