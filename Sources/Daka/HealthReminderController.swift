import Foundation
import DakaCore

/// 独立的健康提醒调度：按工作时段评估喝水/走动，到期以全屏强提示呈现。
@MainActor
final class HealthReminderController {
    /// 当到期提醒集合变化时回调（空数组表示全部解决）。
    var onHealthAlerts: (([HealthAlert]) -> Void)?
    var onTick: (() -> Void)?

    private let clock: DakaClock
    private let healthStore: HealthStore
    private let scheduleStore: PunchStore
    private let interval: TimeInterval

    private var timer: Timer?
    private var lastEmitted: [HealthAlert] = []

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
                                      title: "该喝水啦 💧",
                                      body: "已经 \(minutes) 分钟没喝水了，起来接杯水吧。",
                                      repeatIntervalSeconds: every))
        }
        if status.movementDue {
            let every = TimeInterval(health.effectiveMovementIntervalMinutes * 60)
            let minutes = status.minutesSinceStand ?? health.effectiveMovementIntervalMinutes
            alerts.append(HealthAlert(kind: .movement,
                                      title: "起来走两步 🚶",
                                      body: "坐了 \(minutes) 分钟，活动一下肩颈和腿吧。",
                                      repeatIntervalSeconds: every))
        }

        if alerts != lastEmitted {
            lastEmitted = alerts
            onHealthAlerts?(alerts)
        }
        onTick?()
    }
}
