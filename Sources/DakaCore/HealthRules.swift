import Foundation

public struct HealthStatus: Equatable, Sendable {
    public let cups: Int
    public let stands: Int
    public let minutesSinceDrink: Int?
    public let minutesSinceStand: Int?
    public let waterDue: Bool
    public let movementDue: Bool
    public let active: Bool

    public init(cups: Int,
                stands: Int,
                minutesSinceDrink: Int?,
                minutesSinceStand: Int?,
                waterDue: Bool,
                movementDue: Bool,
                active: Bool) {
        self.cups = cups
        self.stands = stands
        self.minutesSinceDrink = minutesSinceDrink
        self.minutesSinceStand = minutesSinceStand
        self.waterDue = waterDue
        self.movementDue = movementDue
        self.active = active
    }

    public static let idle = HealthStatus(cups: 0, stands: 0,
                                          minutesSinceDrink: nil, minutesSinceStand: nil,
                                          waterDue: false, movementDue: false, active: false)
}

public enum HealthRules {
    public static func status(health: HealthSettings,
                              schedule: Settings,
                              record: DayHealthRecord,
                              leaves: [LeaveRecord],
                              now: Date,
                              calendar: Calendar = .current) -> HealthStatus {
        let windowStart = DakaDate.date(on: now, at: schedule.workStartTime, calendar: calendar)
        let windowEnd = windowStart?.addingTimeInterval(schedule.workDuration)

        let inWindow: Bool
        if let start = windowStart, let end = windowEnd {
            // 单日窗口假设（与打卡一致）：start <= end。
            inWindow = now >= start && now <= end
        } else {
            inWindow = false
        }

        let daySlices = LeaveRules.slices(on: now, in: leaves, calendar: calendar)
        let active = schedule.enabled
            && schedule.isWorkday(now, calendar: calendar)
            && inWindow
            // 整天请假不提醒；半天请假只在请假的那段时间内安静，工作时段照常。
            && !AttendanceRule.isFullDayLeave(schedule, on: now, leaves: leaves, calendar: calendar)
            && !LeaveRules.contains(now, slices: daySlices)

        // 已知取舍：基线仍锚在上班时刻，所以「上午请假到 11:00」后第一次喝水提醒会立刻触发。
        let drinkBase = record.lastDrinkAt ?? windowStart ?? now
        let standBase = record.lastStandAt ?? windowStart ?? now
        let drinkMinutes = max(0, Int(now.timeIntervalSince(drinkBase) / 60))
        let standMinutes = max(0, Int(now.timeIntervalSince(standBase) / 60))

        let waterDue = active
            && health.waterEnabled
            && drinkMinutes >= health.effectiveWaterIntervalMinutes
        let movementDue = active
            && health.movementEnabled
            && standMinutes >= health.effectiveMovementIntervalMinutes

        return HealthStatus(cups: record.cups,
                            stands: record.standCount,
                            minutesSinceDrink: drinkMinutes,
                            minutesSinceStand: standMinutes,
                            waterDue: waterDue,
                            movementDue: movementDue,
                            active: active)
    }
}
