import AppKit
import MonitorCore

/// Compact menu-bar readout. Caches are owned by AppController, not redrawn on every pet tick.
enum MenuReadout {
    static let pairWidth: CGFloat = 38
    static let size = NSSize(width: pairWidth * 3, height: 22)

    static func percentages(_ snapshot: Snapshot) -> [Double?] {
        [snapshot.cpu, snapshot.gpu,
         snapshot.memoryTotal > 0 ? Double(snapshot.memoryUsed) / Double(snapshot.memoryTotal) : nil]
    }
    static func summary(_ snapshot: Snapshot) -> String {
        zip(["CPU", "GPU", "メモリ"], percentages(snapshot)).map { label, value in
            "\(label) \(value.map { String(format: "%.0f%%", $0 * 100) } ?? "—")"
        }.joined(separator: " · ")
    }
    static func image(snapshot: Snapshot, dark: Bool) -> NSImage {
        let values = percentages(snapshot)
        let image = NSImage(size: size, flipped: false) { _ in
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            let foreground: NSColor = dark ? .white : .black
            for (index, entry) in zip(["CPU", "GPU", "RAM"], values).enumerated() {
                let x = CGFloat(index) * pairWidth
                let track = NSRect(x: x + 1, y: 3, width: 3, height: 16)
                foreground.withAlphaComponent(0.18).setFill()
                NSBezierPath(roundedRect: track, xRadius: 1.5, yRadius: 1.5).fill()
                if let value = entry.1, value > 0 {
                    [NSColor.cpuTint, .gpuTint, .memoryTint][index].setFill()
                    NSBezierPath(roundedRect: NSRect(x: track.minX, y: track.minY,
                        width: track.width, height: max(1, track.height * min(1, max(0, value)))),
                        xRadius: 1.5, yRadius: 1.5).fill()
                }
                drawText(entry.0, NSRect(x: x + 8, y: 13, width: 30, height: 9),
                         size: 6.5, color: foreground.withAlphaComponent(0.75), weight: .medium)
                drawText(entry.1.map { String(format: "%.0f%%", $0 * 100) } ?? "—",
                         NSRect(x: x + 8, y: 0, width: 30, height: 14),
                         size: 10, color: foreground, weight: .medium, align: .right, mono: true)
            }
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = summary(snapshot)
        return image
    }
    static func combined(pet: NSImage, metrics: NSImage) -> NSImage {
        let result = NSImage(size: NSSize(width: pet.size.width + 5 + metrics.size.width, height: 22), flipped: false) { _ in
            pet.draw(in: NSRect(origin: .zero, size: pet.size))
            metrics.draw(in: NSRect(x: pet.size.width + 5, y: 0, width: metrics.size.width, height: 22))
            return true
        }
        result.isTemplate = false
        result.accessibilityDescription = "\(pet.accessibilityDescription ?? "犬") · \(metrics.accessibilityDescription ?? "")"
        return result
    }
}
