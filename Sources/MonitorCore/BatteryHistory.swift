import Foundation

public final class BatteryHistory {
    public private(set) var samples: [BatterySample] = []
    public private(set) var error: String?
    private let url: URL
    private var canWrite = true

    public init(url: URL) {
        self.url = url
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            samples = try JSONDecoder().decode([BatterySample].self, from: Data(contentsOf: url))
                .filter { $0.level.isFinite && (0...1).contains($0.level) }.sorted { $0.date < $1.date }
        } catch {
            self.error = "バッテリー履歴を読み込めません。既存ファイルは保護されています。"
            canWrite = false
        }
    }

    public func record(_ sample: BatterySample) {
        guard sample.level.isFinite, (0...1).contains(sample.level) else { return }
        // No invented samples during sleep, shutdown, or a backwards clock change.
        if let last = samples.last, sample.date.timeIntervalSince(last.date) < 60 { return }
        samples.append(sample)
        samples.removeAll { $0.date < sample.date.addingTimeInterval(-48 * 3600) }
        guard canWrite else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(samples).write(to: url, options: .atomic)
            error = nil
        } catch {
            self.error = "バッテリー履歴を保存できません。"
        }
    }

    public static func buckets(_ samples: [BatterySample], now: Date, interval: TimeInterval = 900) -> [BatteryBucket] {
        guard interval > 0 else { return [] }
        let cutoff = now.addingTimeInterval(-24 * 3600)
        var grouped: [Int: BatterySample] = [:]
        for sample in samples.sorted(by: { $0.date < $1.date }) where sample.date >= cutoff && sample.date <= now {
            guard sample.level.isFinite, (0...1).contains(sample.level) else { continue }
            grouped[Int(floor(sample.date.timeIntervalSince1970 / interval))] = sample
        }
        return grouped.sorted { $0.key < $1.key }.map { key, value in
            BatteryBucket(start: Date(timeIntervalSince1970: Double(key) * interval),
                          level: value.level, charging: value.charging)
        }
    }
}
