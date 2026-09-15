import Foundation
import DakaCore

/// 独立的健康提醒调度：按工作时段评估喝水/走动，到点发通知并驱动桌宠气泡。
@MainActor
final class HealthReminderController {
    var onSpeak: ((String) -> Void)?

    private let clock: DakaClock
    private let healthStore: HealthStore
    private let scheduleStore: PunchStore
    private let notifier = GentleNotifier()
    private let interval: TimeInterval

    private var timer: Timer?
    private var lastWaterNoticeAt: Date?
    private var lastMovementNoticeAt: Date?

    init(clock: DakaClock,
         healthStore: HealthStore,
         scheduleStore: PunchStore,
         interval: TimeInterval = 30) {
        self.clock = clock
        self.healthStore = healthStore
        self.scheduleStore = scheduleStore
        self.interval = interval
        notifier.requestAuthorizationIfNeeded()
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

        var speech: String?

        if status.waterDue {
            let every = TimeInterval(health.effectiveWaterIntervalMinutes * 60)
            if lastWaterNoticeAt.map({ now.timeIntervalSince($0) >= every }) ?? true {
                lastWaterNoticeAt = now
                let minutes = status.minutesSinceDrink ?? health.effectiveWaterIntervalMinutes
                notifier.notify(id: "daka.water",
                                title: "该喝水啦 💧",
                                body: "已经 \(minutes) 分钟没喝水了，起来接杯水吧。")
                speech = "该喝水啦～💧"
            }
        } else {
            lastWaterNoticeAt = nil
        }

        if status.movementDue {
            let every = TimeInterval(health.effectiveMovementIntervalMinutes * 60)
            if lastMovementNoticeAt.map({ now.timeIntervalSince($0) >= every }) ?? true {
                lastMovementNoticeAt = now
                let minutes = status.minutesSinceStand ?? health.effectiveMovementIntervalMinutes
                notifier.notify(id: "daka.movement",
                                title: "起来走两步 🚶",
                                body: "坐了 \(minutes) 分钟，活动一下肩颈和腿吧。")
                if speech == nil { speech = "坐太久啦，起来走两步 🚶" }
            }
        } else {
            lastMovementNoticeAt = nil
        }

        if let speech { onSpeak?(speech) }
    }
}
