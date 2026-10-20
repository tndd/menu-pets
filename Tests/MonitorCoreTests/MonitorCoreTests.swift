import Foundation
import MonitorCore

func cpuDeltasAndReset() throws {
    let before = CPUCounter(active: 500, idle: 500)
    try expect(CPUCounter(active: 525, idle: 575).usage(since: before) == 0.25)
    try expect(CPUCounter(active: 2, idle: 5).usage(since: before) == nil)
    try expect(before.usage(since: before) == nil)
}

func batteryPersistenceAndSleepGaps() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("battery.json")
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let history = BatteryHistory(url: url)
    history.record(BatterySample(date: now.addingTimeInterval(-7200), level: 0.8, charging: false))
    history.record(BatterySample(date: now, level: 0.7, charging: false))
    history.record(BatterySample(date: now.addingTimeInterval(2), level: 0.6, charging: false))
    try expect(history.samples.count == 2)
    let restored = BatteryHistory(url: url)
    try expect(restored.samples == history.samples)
    let buckets = BatteryHistory.buckets(restored.samples, now: now)
    try expect(buckets.count == 2) // Missing time stays missing rather than interpolated.
    try expect(buckets[1].level == 0.7)
}

func batteryBucketsFilterFutureAndInvalidValues() throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let samples = [
        BatterySample(date: now.addingTimeInterval(-90_000), level: 0.4, charging: false),
        BatterySample(date: now.addingTimeInterval(100), level: 0.4, charging: false),
        BatterySample(date: now.addingTimeInterval(-60), level: 3, charging: false),
        BatterySample(date: now, level: 0.6, charging: true)
    ]
    let buckets = BatteryHistory.buckets(samples, now: now)
    try expect(buckets.count == 1)
    try expect(buckets.first?.charging == true)
    try expect(BatteryHistory.buckets(samples, now: now, interval: 0).isEmpty)
}

func corruptedHistoryIsPreserved() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("battery.json")
    let original = Data("broken history".utf8)
    try original.write(to: url)
    let history = BatteryHistory(url: url)
    history.record(BatterySample(date: Date(), level: 0.5, charging: false))
    try expect(history.error != nil)
    try expect(try Data(contentsOf: url) == original)
}

func liveTelemetryIsPlausible() throws {
    let sampler = Sampler()
    let initial = sampler.sample()
    try expect(initial.cpu == nil)
    try expect(initial.memoryTotal > 0)
    try expect(initial.memoryUsed > 0 && initial.memoryUsed <= initial.memoryTotal)
    if let gpu = initial.gpu { try expect((0...1).contains(gpu)) }
    if let battery = initial.battery { try expect((0...1).contains(battery.level)) }
}

struct CheckFailure: Error { let line: UInt }
func expect(_ condition: @autoclosure () throws -> Bool, line: UInt = #line) throws {
    if try !condition() { throw CheckFailure(line: line) }
}
let checks: [(String, () throws -> Void)] = [
    ("CPU deltas and reset", cpuDeltasAndReset),
    ("Battery persistence and sleep gaps", batteryPersistenceAndSleepGaps),
    ("Battery invalid and future samples", batteryBucketsFilterFutureAndInvalidValues),
    ("Corrupt history preservation", corruptedHistoryIsPreserved),
    ("Live telemetry", liveTelemetryIsPlausible)
]
var failures = 0
for (name, check) in checks {
    do { try check(); print("PASS: \(name)") }
    catch { failures += 1; print("FAIL: \(name): \(error)") }
}
exit(failures == 0 ? 0 : 1)
