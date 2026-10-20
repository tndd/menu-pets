import AppKit
import MonitorCore

final class GaugeView: FlippedView {
    let label: String
    let tint: NSColor
    var value: Double? { didSet { updateAccessibility(); needsDisplay = true } }
    var detail: String = "" { didSet { needsDisplay = true } }
    init(label: String, tint: NSColor) {
        self.label = label; self.tint = tint
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        updateAccessibility()
    }
    required init?(coder: NSCoder) { fatalError() }
    private func updateAccessibility() {
        setAccessibilityLabel("\(label) \(value.map { String(format: "%.0f パーセント", $0 * 100) } ?? "取得待ち")")
    }
    override func draw(_ dirtyRect: NSRect) {
        let center = NSPoint(x: bounds.midX, y: 31)
        let radius: CGFloat = 26
        func arc(_ fraction: Double, color: NSColor) {
            let path = NSBezierPath()
            let segments = max(2, Int(80 * fraction))
            for i in 0...segments {
                let angle = (135 + 270 * fraction * Double(i) / Double(segments)) * .pi / 180
                let p = NSPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
                if i == 0 { path.move(to: p) } else { path.line(to: p) }
            }
            path.lineWidth = 3.5
            path.lineCapStyle = .round
            color.setStroke()
            path.stroke()
        }
        arc(1, color: .secondaryLabelColor.withAlphaComponent(0.15))
        if let value, value > 0 { arc(min(1, value), color: tint) }
        drawText(value.map { String(format: "%.0f%%", $0 * 100) } ?? "—",
                 NSRect(x: 0, y: 20, width: bounds.width, height: 24),
                 size: 17, weight: .medium, align: .center, mono: true)
        drawText(label, NSRect(x: 0, y: 55, width: bounds.width, height: 15), size: 10, align: .center)
        if !detail.isEmpty {
            drawText(detail, NSRect(x: 0, y: 70, width: bounds.width, height: 12),
                     size: 8.5, color: .secondaryLabelColor, align: .center, mono: true)
        }
    }
}

final class BatteryChart: FlippedView {
    var samples: [BatterySample] = [] { didSet { needsDisplay = true } }
    var available = true { didSet { needsDisplay = true } }
    var now = Date()
    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("過去24時間のバッテリー残量。緑の棒は残量、下の印は充電中。空白は未計測。")
        toolTip = "実測した残量を15分ごとの棒で表示。空白は未計測、下の緑線は充電中です。"
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        drawText("バッテリー · 24時間", NSRect(x: 7, y: 7, width: bounds.width - 14, height: 15), size: 10, weight: .medium)
        let plot = NSRect(x: 8, y: 29, width: bounds.width - 34, height: bounds.height - 53)
        let grid = NSBezierPath()
        for index in 0...4 {
            let y = plot.minY + plot.height * CGFloat(index) / 4
            grid.move(to: NSPoint(x: plot.minX, y: y)); grid.line(to: NSPoint(x: plot.maxX, y: y))
        }
        for index in 0...8 {
            let x = plot.minX + plot.width * CGFloat(index) / 8
            grid.move(to: NSPoint(x: x, y: plot.minY)); grid.line(to: NSPoint(x: x, y: plot.maxY))
        }
        grid.lineWidth = 0.5
        NSColor.secondaryLabelColor.withAlphaComponent(0.18).setStroke(); grid.stroke()
        for (index, label) in ["100", "50", "0"].enumerated() {
            drawText(label, NSRect(x: plot.maxX + 3, y: plot.minY + CGFloat(index) * plot.height / 2 - 5,
                                  width: 23, height: 11), size: 7.5, color: .tertiaryLabelColor, mono: true)
        }
        let end = ceil(now.timeIntervalSince1970 / 900) * 900
        let start = end - 86400
        let formatter = DateFormatter(); formatter.dateFormat = "HH"
        for i in 0...4 {
            let date = Date(timeIntervalSince1970: start + Double(i) * 21600)
            drawText(formatter.string(from: date),
                     NSRect(x: plot.minX + CGFloat(i) * plot.width / 4 - 8, y: plot.maxY + 9, width: 16, height: 12),
                     size: 8, color: .secondaryLabelColor, align: .center, mono: true)
        }
        for bucket in BatteryHistory.buckets(samples, now: now) {
            let fraction = (bucket.start.timeIntervalSince1970 - start) / 86400
            guard (0..<1).contains(fraction) else { continue }
            let x = plot.minX + plot.width * fraction
            let width = max(0.6, plot.width / 96 - 0.65)
            let height = plot.height * bucket.level
            NSColor.systemGreen.setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: plot.maxY - height, width: width, height: height),
                         xRadius: 0.5, yRadius: 0.5).fill()
            if bucket.charging {
                NSColor.systemGreen.withAlphaComponent(0.11).setFill()
                NSRect(x: x, y: plot.minY, width: width + 0.65, height: plot.height).fill()
                NSColor.systemGreen.setFill()
                NSRect(x: x, y: plot.maxY + 3, width: width + 0.65, height: 2).fill()
            }
        }
        if !available || samples.count < 3 {
            drawText(available ? "履歴を記録中" : "バッテリーなし",
                     NSRect(x: plot.minX + 3, y: plot.midY - 6, width: plot.width - 6, height: 14),
                     size: 9, color: .secondaryLabelColor, align: .center)
        }
    }
}
