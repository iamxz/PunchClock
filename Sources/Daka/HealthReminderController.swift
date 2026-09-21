import Foundation
import DakaCore

/// 独立的健康提醒调度：按工作时段评估喝水/走动，到期以 toast 弱提示呈现（不弹全屏）。
@MainActor
final class HealthReminderController {
    /// 每次 tick 汇报当前到期的提醒集合（空数组表示全部已解决），由消费方决定如何呈现。
    var onHealthAlerts: (([HealthAlert]) -> Void)?
    var onTick: (() -> Void)?

    private let clock: DakaClock
    private let healthStore: HealthStore
    private let scheduleStore: PunchStore
    private let interval: TimeInterval

    private var timer: Timer?

    init(clock: DakaClock,
         healthStore: HealthStore,
         scheduleStore: PunchStore,
         interval: TimeInterval = 30) {
        self.clock = clock
        self.healthStore = healthStore
        self.scheduleStore = scheduleStore
        self.interval = interval
    }

    func start() {
        stop()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    deinit {
        timer?.invalidate()
    }

    func tick() {
        let now = clock.now
        let health = healthStore.data.settings
        let schedule = scheduleStore.data.settings
        let record = healthStore.record(for: now)
        let skipped = scheduleStore.record(for: now).skipped
        let status = HealthRules.status(health: health, schedule: schedule,
                                        record: record, skipped: skipped, now: now)

        var alerts: [HealthAlert] = []

        if status.waterDue {
            let every = TimeInterval(health.effectiveWaterIntervalMinutes * 60)
            let minutes = status.minutesSinceDrink ?? health.effectiveWaterIntervalMinutes
            alerts.append(HealthAlert(kind: .water,
                                      title: HealthCopy.title(.water),
                                      body: HealthCopy.body(.water, minutes: minutes),
                                      repeatIntervalSeconds: every))
        }
        if status.movementDue {
            let every = TimeInterval(health.effectiveMovementIntervalMinutes * 60)
            let minutes = status.minutesSinceStand ?? health.effectiveMovementIntervalMinutes
            alerts.append(HealthAlert(kind: .movement,
                                      title: HealthCopy.title(.movement),
                                      body: HealthCopy.body(.movement, minutes: minutes),
                                      repeatIntervalSeconds: every))
        }

        onHealthAlerts?(alerts)
        onTick?()
    }
}
