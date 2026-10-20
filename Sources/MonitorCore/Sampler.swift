import Foundation
import CMetrics
import IOKit
import IOKit.ps

/// Confine the sampler and its deltas to one serial queue.
public final class Sampler {
    private var previousCPU: CPUCounter?
    public init() {}

    public func sample() -> Snapshot {
        var out = Snapshot()
        let cpu = mp_cpu()
        if cpu.valid != 0 {
            let current = CPUCounter(active: cpu.active, idle: cpu.idle)
            out.cpu = previousCPU.flatMap { current.usage(since: $0) }
            previousCPU = current
        }
        let memory = mp_memory()
        if memory.valid != 0 { out.memoryUsed = memory.used; out.memoryTotal = memory.total }
        out.gpu = Self.gpuUsage()
        out.battery = Self.battery()
        return out
    }

    public static func gpuUsage() -> Double? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var values: [Double] = []
        while true {
            let service = IOIteratorNext(iterator)
            if service == 0 { break }
            defer { IOObjectRelease(service) }
            guard let unmanaged = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0),
                  let stats = unmanaged.takeRetainedValue() as? [String: Any],
                  let number = (stats["Device Utilization %"] ?? stats["GPU Activity(%)"]) as? NSNumber else { continue }
            let percent = number.doubleValue
            if percent.isFinite && (0...100).contains(percent) { values.append(percent / 100) }
        }
        // Multi-GPU devices: show the busiest GPU; never sum percentages.
        return values.max()
    }

    public static func battery() -> BatteryReading? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? NSNumber,
                  let maximum = description[kIOPSMaxCapacityKey] as? NSNumber,
                  maximum.doubleValue > 0 else { continue }
            return BatteryReading(level: min(1, max(0, current.doubleValue / maximum.doubleValue)),
                                  charging: description[kIOPSIsChargingKey] as? Bool ?? false,
                                  pluggedIn: description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue)
        }
        return nil
    }
}
