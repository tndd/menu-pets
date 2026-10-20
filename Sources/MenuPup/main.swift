import AppKit
import MonitorCore

if CommandLine.arguments.contains("--probe") {
    let sampler = Sampler()
    _ = sampler.sample()
    Thread.sleep(forTimeInterval: 1)
    let sample = sampler.sample()
    let data: [String: Any] = [
        "cpuPercent": sample.cpu.map { $0 * 100 } as Any? ?? NSNull(),
        "gpuPercent": sample.gpu.map { $0 * 100 } as Any? ?? NSNull(),
        "memoryUsedBytes": sample.memoryUsed,
        "memoryTotalBytes": sample.memoryTotal,
        "batteryPercent": sample.battery.map { $0.level * 100 } as Any? ?? NSNull(),
    ]
    let json = try JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys])
    print(String(decoding: json, as: UTF8.self))
} else {
    let application = NSApplication.shared
    let args = CommandLine.arguments
    var directory: URL?
    if let index = args.firstIndex(of: "--ui-checks"), args.count > index + 1 {
        directory = URL(fileURLWithPath: args[index + 1])
    }
    let controller = AppController(checkDirectory: directory)
    application.delegate = controller
    withExtendedLifetime(controller) { application.run() }
}
