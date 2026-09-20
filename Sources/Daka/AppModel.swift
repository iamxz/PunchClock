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

    // MARK: - 升级检测
    @Published private(set) var updateResult: UpdateCheckResult?
    @Published var updateCheckState: UpdateCheckState = .idle

    enum UpdateCheckState: Equatable {
        case idle, checking, upToDate, available, error
    }

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

    var workDuration: TimeInterval { settings.workDuration }

    var isEveningComplete: Bool {
        AttendanceRule.isEveningComplete(record, settings: settings, on: now, calendar: .current)
    }

    func setWorkDurationHours(_ hours: Double) {
        updateSettings { $0.workDurationHours = hours }
    }

    func updateWorkStart(_ hhmm: String) { updateSettings { $0.workStartTime = hhmm } }
    func setFlexMinutes(_ minutes: Int) { updateSettings { $0.flexMinutes = max(0, minutes) } }

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
        reminder.setWaterAction { [weak self] in self?.drinkWater() }
        reminder.setMovementAction { [weak self] in self?.standUp() }
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
        healthReminder.onHealthAlerts = { [weak self] alerts in
            guard let self else { return }
            self.reminder?.updateHealth(alerts, settings: self.settings, now: self.now)
        }
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

        // 启动后后台检查一次 GitHub 是否有新版本（仅公开 API 版本号比较）。
        checkForUpdates()
    }

    // MARK: - 升级检测

    /// 检查 GitHub Releases 是否有新版本，结果写入 `updateResult` / `updateCheckState`。
    func checkForUpdates() {
        updateCheckState = .checking
        UpdateChecker.shared.check { [weak self] result in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    switch result {
                    case .success(let res):
                        self.updateResult = res
                        if res.isUpdateAvailable {
                            self.updateCheckState = .available
                            self.remindIfNeeded(res)
                        } else {
                            self.updateCheckState = .upToDate
                        }
                    case .failure:
                        self.updateCheckState = .error
                        self.updateResult = nil
                    }
                }
            }
        }
    }

    /// 前往 GitHub Releases 下载页（用户指定的下载地址）。
    func openDownloadPage() {
        NSWorkspace.shared.open(UpdateChecker.releasesURL)
    }

    /// 发现新版本时弹一次性提醒；同一版本仅提示一次（UserDefaults 去重）。
    private func remindIfNeeded(_ res: UpdateCheckResult) {
        // dev 环境下若读不到当前版本（非 .app 运行），不弹提醒，避免误报。
        guard UpdateChecker.shared.currentVersion != nil else { return }
        let key = "DakaShownUpdateVersion"
        guard UserDefaults.standard.string(forKey: key) != res.latestTag else { return }
        UserDefaults.standard.set(res.latestTag, forKey: key)

        let alert = NSAlert()
        alert.messageText = "发现新版本 \(res.latestVersion.description)"
        alert.informativeText = "当前版本 \(res.currentVersion.description)。是否前往 GitHub 下载最新版本？"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "前往下载")
        alert.addButton(withTitle: "稍后提醒")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            openDownloadPage()
        }
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
            healthReminder?.tick()
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

    /// 循环微调某天的工作日状态：默认 → 强制相反 → 强制还原 → 默认。
    func cycleWorkdayOverride(for date: Date, calendar: Calendar = .current) {
        let key = DakaDate.key(for: date, calendar: calendar)
        updateSettings { settings in
            var overrides = settings.workdayOverrides
            let natural = WorkdayCalendar(baseWorkdays: settings.workdays, overrides: [:])
                .isWorkday(date, calendar: calendar)
            if let current = overrides[key] {
                if current {
                    overrides[key] = false
                } else {
                    overrides.removeValue(forKey: key)
                }
            } else {
                overrides[key] = !natural
            }
            settings.workdayOverrides = overrides
        }
    }

    /// 直接设置某天的微调（nil 表示清除，恢复默认）。
    func setWorkdayOverride(_ dateKey: String, workday: Bool?) {
        updateSettings { settings in
            var overrides = settings.workdayOverrides
            if let value = workday {
                overrides[dateKey] = value
            } else {
                overrides.removeValue(forKey: dateKey)
            }
            settings.workdayOverrides = overrides
        }
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
