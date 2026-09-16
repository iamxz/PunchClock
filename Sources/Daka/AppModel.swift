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

    var hasSettingsFeedback: Bool {
        errorMessage != nil || startupWarning != nil || scheduledLaunchWarning != nil
    }

    @Published var selectedSidebar: SidebarSelection = .tool(.punch)
    let tools = ToolCatalog.all

    @Published private(set) var healthSettings: HealthSettings
    @Published private(set) var healthRecord: DayHealthRecord

    weak var mainWindow: MainWindowController?

    /// 唯一放行退出的开关：设置页确认退出、或系统关机时置 true。
    var allowTermination = false

    var now: Date { clock.now }

    var minWorkDuration: TimeInterval { settings.minWorkDuration }

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
    private let healthStore: HealthStore
    private var healthReminder: HealthReminderController?

    init(clock: AdjustableClock = AdjustableClock(),
         store: PunchStore? = nil,
         healthStore: HealthStore? = nil) {
        let resolvedStore = store ?? PunchStore(fileURL: PunchStore.defaultFileURL())
        let resolvedHealth = healthStore ?? HealthStore(fileURL: HealthStore.defaultFileURL())
        self.clock = clock
        self.store = resolvedStore
        self.healthStore = resolvedHealth
        self.settings = resolvedStore.data.settings
        self.record = resolvedStore.record(for: clock.now)
        self.healthSettings = resolvedHealth.data.settings
        self.healthRecord = resolvedHealth.record(for: clock.now)
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
        if healthStore.didRecoverFromCorruption {
            warnings.append("健康记录文件损坏，已备份并重置。" +
                (healthStore.corruptionBackupURL.map { "备份：\($0.lastPathComponent)" } ?? ""))
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
            self.refreshHealth()
        }
        self.scheduler = scheduler

        let healthReminder = HealthReminderController(clock: clock,
                                                      healthStore: healthStore,
                                                      scheduleStore: store)
        healthReminder.onTick = { [weak self] in self?.refreshHealth() }
        self.healthReminder = healthReminder
        healthReminder.start()

        installScheduledLaunch()

        NotificationCenter.default.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.scheduler?.tick()
                self?.healthReminder?.tick()
            }
        }
        NotificationCenter.default.addObserver(
            forName: .NSSystemClockDidChange,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.scheduler?.tick()
                self?.healthReminder?.tick()
            }
        }
        NotificationCenter.default.addObserver(
            forName: .NSSystemTimeZoneDidChange,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.scheduler?.tick()
                self?.healthReminder?.tick()
            }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.scheduler?.tick()
                self?.healthReminder?.tick()
            }
        }

        scheduler.start()
    }

    func refreshRecord() {
        record = store.record(for: clock.now)
        settings = store.data.settings
    }

    var healthStatus: HealthStatus {
        HealthRules.status(health: healthSettings,
                           schedule: settings,
                           record: healthRecord,
                           skipped: record.skipped,
                           now: clock.now)
    }

    func refreshHealth() {
        healthRecord = healthStore.record(for: clock.now)
        healthSettings = healthStore.data.settings
    }

    func drinkWater() {
        do { try logHealth(.water) } catch {}
    }

    func standUp() {
        do { try logHealth(.movement) } catch {}
    }

    private func logHealth(_ kind: HealthLogKind) throws {
        errorMessage = nil
        do {
            try healthStore.log(kind, at: clock.now)
            refreshHealth()
            scheduler?.tick()
        } catch {
            errorMessage = "记录失败：\(error.localizedDescription)"
            throw error
        }
    }

    func healthStatistics(rangeDays: Int) -> HealthSummary {
        HealthStatistics.compute(records: healthStore.data.records,
                                 settings: healthStore.data.settings,
                                 schedule: settings,
                                 now: clock.now,
                                 rangeDays: rangeDays)
    }

    func updateHealthSettings(_ mutate: (inout HealthSettings) -> Void) {
        errorMessage = nil
        var s = healthStore.data.settings
        mutate(&s)
        do {
            try healthStore.updateSettings(s)
            refreshHealth()
            healthReminder?.tick()
        } catch {
            errorMessage = "设置保存失败：\(error.localizedDescription)"
        }
    }

    func setWaterEnabled(_ on: Bool) { updateHealthSettings { $0.waterEnabled = on } }
    func setWaterGoalCups(_ n: Int) { updateHealthSettings { $0.waterGoalCups = max(1, n) } }
    func setWaterIntervalMinutes(_ n: Int) { updateHealthSettings { $0.waterIntervalMinutes = max(15, n) } }
    func setMovementEnabled(_ on: Bool) { updateHealthSettings { $0.movementEnabled = on } }
    func setMovementGoalCount(_ n: Int) { updateHealthSettings { $0.movementGoalCount = max(1, n) } }
    func setMovementIntervalMinutes(_ n: Int) { updateHealthSettings { $0.movementIntervalMinutes = max(15, n) } }

    func punch(_ task: PunchTask) {
        errorMessage = nil
        do {
            try store.mark(task, at: clock.now)
            refreshRecord()
            scheduler?.tick()
            reminder?.showMessage(PunchFeedback.text(task: task,
                                                      record: record,
                                                      settings: settings,
                                                      punchedAt: clock.now))
        } catch {
            errorMessage = "打卡记录写入失败：\(error.localizedDescription)"
        }
    }

    func addPunch(_ task: PunchTask, at time: Date) {
        errorMessage = nil
        do {
            try store.mark(task, at: time)
            refreshRecord()
            scheduler?.tick()
            reminder?.showMessage(nil)
        } catch {
            errorMessage = "打卡记录写入失败：\(error.localizedDescription)"
        }
    }

    func updatePunch(_ task: PunchTask, index: Int, to time: Date) {
        errorMessage = nil
        do {
            try store.updatePunch(task, at: index, to: time, on: clock.now)
            refreshRecord()
            scheduler?.tick()
            reminder?.showMessage(nil)
        } catch {
            errorMessage = "打卡记录写入失败：\(error.localizedDescription)"
        }
    }

    func removePunch(_ task: PunchTask, index: Int) {
        errorMessage = nil
        do {
            try store.removePunch(task, at: index, on: clock.now)
            refreshRecord()
            scheduler?.tick()
            reminder?.showMessage(nil)
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

    func setReminderIntervalMinutes(_ minutes: Int) {
        let clamped = min(60, max(1, minutes))
        updateSettings { $0.reminderIntervalSeconds = TimeInterval(clamped * 60) }
    }

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

    func repairLoginItem() {
        errorMessage = LoginItemManager.registerIfNeeded()
        objectWillChange.send()
    }

    func select(_ item: SidebarSelection) {
        selectedSidebar = item
    }

    func openControlCenter(selecting id: ToolID? = nil) {
        if let id { selectedSidebar = .tool(id) }
        mainWindow?.show()
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

    func confirmQuit() {
        let alert = NSAlert()
        alert.messageText = "退出 打工人爱护自己？"
        alert.informativeText = "退出后将无法提醒打卡，直到下次开机或手动启动。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "取消")
        alert.addButton(withTitle: "仍要退出")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        allowTermination = true
        NSApp.terminate(nil)
    }
}
