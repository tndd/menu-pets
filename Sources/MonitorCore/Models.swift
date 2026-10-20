import Foundation

public struct CPUCounter {
    public let active: UInt64
    public let idle: UInt64
    public init(active: UInt64, idle: UInt64) { self.active = active; self.idle = idle }
    public func usage(since old: CPUCounter) -> Double? {
        guard active >= old.active, idle >= old.idle else { return nil }
        let a = Double(active - old.active), i = Double(idle - old.idle)
        return a + i > 0 ? a / (a + i) : nil
    }
}

public struct BatterySample: Codable, Equatable {
    public let date: Date
    public let level: Double
    public let charging: Bool
    public init(date: Date, level: Double, charging: Bool) {
        self.date = date; self.level = level; self.charging = charging
    }
}

public struct BatteryBucket: Equatable {
    public let start: Date
    public let level: Double
    public let charging: Bool
}

public struct BatteryReading {
    public let level: Double
    public let charging: Bool
    public let pluggedIn: Bool
}

public struct Snapshot {
    public var cpu: Double?
    public var gpu: Double?
    public var memoryUsed: UInt64 = 0
    public var memoryTotal: UInt64 = 0
    public var battery: BatteryReading?
    public var date = Date()
    public init() {}
}
