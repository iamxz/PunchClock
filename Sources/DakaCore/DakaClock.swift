import Foundation

public protocol DakaClock: AnyObject {
    var now: Date { get }
}

public final class SystemClock: DakaClock {
    public init() {}
    public var now: Date { Date() }
}

/// 真实时间 + 可调偏移，用于「调试：模拟时间」。
public final class AdjustableClock: DakaClock {
    private let base: DakaClock
    private var offset: TimeInterval

    public init(base: DakaClock = SystemClock(), offset: TimeInterval = 0) {
        self.base = base
        self.offset = offset
    }

    public var now: Date { base.now.addingTimeInterval(offset) }

    public func addOffset(_ seconds: TimeInterval) { offset += seconds }
    public func reset() { offset = 0 }
}
