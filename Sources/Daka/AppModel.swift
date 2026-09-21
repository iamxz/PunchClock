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
            self.presentHealthToasts(alerts)
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
                ToastCenter.shared.repositionIfNeeded()
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

    // MARK: - 健康提醒弱提示（toast）

    /// 每个提醒种类上一次弹出 toast 的时间，用于忽略期内按重复间隔重弹。
    private var lastHealthToastAt: [HealthAlert.Kind: Date] = [:]
    /// 同一轮多种健康提醒之间的弹出间隔（秒）。
    private static let healthToastStagger: TimeInterval = 2.6

    /// 喝水/走动是唯一走 toast 弱提示的提醒：弹出数秒后自动消失，不抢焦点、不打断工作。
    /// 到期未处理时，每个提醒种类按自身重复间隔（如喝水间隔 60 分钟）重弹一次。
    private func presentHealthToasts(_ alerts: [HealthAlert]) {
        let now = clock.now
        var delay: TimeInterval = 0
        for alert in alerts {
            if let last = lastHealthToastAt[alert.kind],
               now.timeIntervalSince(last) < alert.repeatIntervalSeconds {
                continue
            }
            lastHealthToastAt[alert.kind] = now
            let toast = ToastCenter.Toast(title: alert.title,
                                          body: alert.body,
                                          icon: HealthCopy.icon(alert.kind),
                                          tint: HealthCopy.tint(alert.kind))
            if delay == 0 {
                ToastCenter.shared.show(toast)
            } else {
                // 两种提醒同时到期时错开依次弹出，避免后一张把前一张瞬间顶掉、来不及看。
                let wait = delay
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(wait))
                    ToastCenter.shared.show(toast)
                }
            }
            delay += Self.healthToastStagger
        }
        // 已解决的提醒清掉节流记录，下次到期立刻弹出。
        let active = Set(alerts.map(\.kind))
        lastHealthToastAt = lastHealthToastAt.filter { active.contains($0.key) }
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
            // 全屏遮罩可能因任务完成而立即收起，打卡反馈改用 toast 呈现，保证可见。
            let feedback = PunchFeedback.text(task: task,
                                              record: record,
                                              settings: settings,
                                              punchedAt: clock.now)
            ToastCenter.shared.show(ToastTemplate.punch(task: task, feedback: feedback))
        } catch {
            errorMessage = "打卡记录写入失败：\(error.localizedDescription)"
        }
    }

    /// 补一条打卡记录（可指定任意日期，供「补卡（遗漏）」使用）。
    ///
    /// 同一任务在 1 分钟内已有记录时直接忽略，避免误点造成重复刷屏。
    /// - Returns: 是否真的写入了新记录。
    @discardableResult
    func addPunch(_ task: PunchTask, at time: Date) -> Bool {
        errorMessage = nil

        let existing = store.record(for: time)
        let punches = task == .morning ? existing.morningPunches : existing.eveningPunches
        if punches.contains(where: { abs($0.timeIntervalSince(time)) < 60 }) {
            return false
        }

        do {
            try store.mark(task, at: time)
            refreshRecord()
            scheduler?.tick()
            return true
        } catch {
            errorMessage = "打卡记录写入失败：\(error.localizedDescription)"
            return false
        }
    }

    func clearError() {
        errorMessage = nil
    }

    func updatePunch(_ task: PunchTask, index: Int, to time: Date) {
        errorMessage = nil
        do {
            try store.updatePunch(task, at: index, to: time, on: clock.now)
            refreshRecord()
            scheduler?.tick()
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
        } catch {
            errorMessage = "打卡记录写入失败：\(error.localizedDescription)"
        }
    }

    func setSkipped(_ skipped: Bool) {
        setSkipped(skipped, on: clock.now)
    }

    /// 设置某天为休假 / 取消休假（日历右键入口，可作用于今天与过去任意日期）。
    func setSkipped(_ skipped: Bool, on day: Date) {
        errorMessage = nil
        do {
            try store.setSkipped(skipped, on: day)
            refreshRecord()
            scheduler?.tick()
        } catch {
            errorMessage = "保存失败：\(error.localizedDescription)"
        }
    }

    /// 清除某天的全部打卡记录（日历右键入口）。
    func clearPunches(on day: Date) {
        errorMessage = nil
        do {
            let existing = store.record(for: day)
            for index in existing.morningPunches.indices.reversed() {
                try store.removePunch(.morning, at: index, on: day)
            }
            for index in existing.eveningPunches.indices.reversed() {
                try store.removePunch(.evening, at: index, on: day)
            }
            refreshRecord()
            scheduler?.tick()
        } catch {
            errorMessage = "打卡记录写入失败：\(error.localizedDescription)"
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

    /// 全部打卡记录（只读），供日历等组件使用。
    var records: [String: DayRecord] { store.data.records }

    /// 某月的考勤日历网格（每月 1 号 ~ 月末）。
    func attendanceMonthGrid(month: Date) -> MonthGrid {
        AttendanceCalendar.monthGrid(records: store.data.records,
                                     settings: store.data.settings,
                                     month: month,
                                     now: clock.now)
    }

    /// 某天「合格下班卡」的下限时刻：上班卡 + 工作时长。没有上班卡时返回 nil。
    func eveningThreshold(on day: Date) -> Date? {
        guard let morning = store.record(for: day).morningDoneAt else { return nil }
        return morning.addingTimeInterval(store.data.settings.workDuration)
    }

    /// 当前连续打卡天数（跨月统计）。
    var currentStreak: Int {
        Statistics.compute(records: store.data.records,
                           settings: store.data.settings,
                           now: clock.now,
                           rangeDays: 400).currentStreak
    }

    func setWorkdays(_ days: Set<Int>) {
        updateSettings { $0.workdays = days }
    }

    // MARK: - 退出

    /// 退出影响说明（确认弹窗正文），按今日打卡状态生成。
    var quitImpactText: String {
        QuitPrompt.impactText(skipped: record.skipped,
                              morningDone: record.morningDone,
                              eveningDone: isEveningComplete)
    }

    /// 弹退出确认框，返回用户是否确认退出。
    ///
    /// 菜单/快捷键（Cmd+Q）与设置页「退出应用」共用同一条确认路径；
    /// 系统关机、或已经确认过一次时直接返回 true，不重复打扰。
    @discardableResult
    func confirmQuit() -> Bool {
        if allowTermination { return true }
        let alert = NSAlert()
        alert.messageText = QuitPrompt.title
        alert.informativeText = quitImpactText
        alert.alertStyle = .warning
        alert.addButton(withTitle: "取消")
        alert.addButton(withTitle: "仍要退出")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertSecondButtonReturn else { return false }
        allowTermination = true
        return true
    }

    /// 设置页「退出应用」入口。
    func quit() {
        guard confirmQuit() else { return }
        NSApp.terminate(nil)
    }

    /// 系统退出请求（Cmd+Q、Dock 菜单等）的拦截点：确认后放行，取消则继续运行。
    func shouldTerminate() -> NSApplication.TerminateReply {
        confirmQuit() ? .terminateNow : .terminateCancel
    }
}
