import AppKit
import MonitorCore

final class Dashboard: FlippedView {
    static let width: CGFloat = 256
    static let collapsedHeight: CGFloat = 302
    static let expandedSize = NSSize(width: 520, height: 464)
    let preferences: Preferences
    let settingsButton = NSButton()
    private let titleLabel = NSTextField(labelWithString: "MenuPup")
    let gauges = [GaugeView(label: "CPU", tint: .cpuTint), GaugeView(label: "GPU", tint: .gpuTint),
                  GaugeView(label: "メモリ", tint: .memoryTint)]
    let battery = BatteryChart(frame: .zero)
    let terminal = TerminalPanel(frame: .zero)
    private let effect = NSVisualEffectView()
    private let batterySurface = Surface()
    private let terminalSurface = Surface()
    var onResize: ((NSSize) -> Void)?
    var onSettings: (() -> Void)?
    var expanded = false

    init(preferences: Preferences) {
        self.preferences = preferences
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: Self.collapsedHeight))
        effect.material = .popover; effect.blendingMode = .behindWindow; effect.state = .active
        addSubview(effect)
        titleLabel.font = .systemFont(ofSize: 10, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor
        addSubview(titleLabel)
        settingsButton.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "設定")
        settingsButton.bezelStyle = .inline; settingsButton.target = self; settingsButton.action = #selector(settings)
        addSubview(settingsButton)
        gauges.forEach(addSubview)
        for surface in [batterySurface, terminalSurface] { addSubview(surface) }
        batterySurface.addSubview(battery)
        terminalSurface.addSubview(terminal)
        terminal.expandedChanged = { [weak self] expanded in
            guard let self else { return }
            self.expanded = expanded
            self.onResize?(expanded ? Self.expandedSize : NSSize(width: Self.width, height: Self.collapsedHeight))
            self.needsLayout = true
        }
        applyTheme()
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        effect.frame = bounds
        titleLabel.frame = NSRect(x: 12, y: 12, width: 90, height: 14)
        settingsButton.frame = NSRect(x: bounds.width - 30, y: 7, width: 22, height: 22)
        for (i, gauge) in gauges.enumerated() {
            gauge.frame = NSRect(x: (bounds.width - 240) / 2 + CGFloat(i) * 80, y: 34, width: 80, height: 84)
        }
        batterySurface.frame = NSRect(x: 8, y: 124, width: bounds.width - 16, height: 132)
        terminalSurface.frame = NSRect(x: 8, y: 264, width: bounds.width - 16, height: max(30, bounds.height - 272))
        battery.frame = batterySurface.bounds
        terminal.frame = terminalSurface.bounds
    }
    override func draw(_ dirtyRect: NSRect) {
        if preferences.theme == .material {
            (preferences.dark ? NSColor(calibratedWhite: 0.12, alpha: 1) :
                NSColor(calibratedWhite: 0.96, alpha: 1)).setFill()
            bounds.fill()
        }
    }
    func update(snapshot: Snapshot, history: BatteryHistory) {
        gauges[0].value = snapshot.cpu
        gauges[0].toolTip = "全コア合計を100%としたCPU使用率"
        gauges[1].value = snapshot.gpu
        gauges[1].toolTip = snapshot.gpu == nil ? "この環境ではGPU使用率を取得できません" : "IORegistryで取得したGPU使用率。複数GPUでは最大値。"
        gauges[2].value = snapshot.memoryTotal > 0 ? Double(snapshot.memoryUsed) / Double(snapshot.memoryTotal) : nil
        gauges[2].detail = snapshot.memoryTotal > 0 ?
            String(format: "%.1f / %.0f GB", Double(snapshot.memoryUsed) / 1_073_741_824, Double(snapshot.memoryTotal) / 1_073_741_824) : ""
        battery.available = snapshot.battery != nil
        battery.now = snapshot.date; battery.samples = history.samples
        if let error = history.error { battery.toolTip = error }
    }
    @objc private func settings() { onSettings?() }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        terminal.dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        needsDisplay = true
        subviews.forEach { $0.needsDisplay = true }
    }
    func applyTheme() {
        appearance = NSApp.appearance
        window?.appearance = NSApp.appearance
        effect.isHidden = preferences.theme == .material
        [batterySurface, terminalSurface].forEach { $0.theme = preferences.theme }
        terminal.dark = preferences.dark
        needsDisplay = true
        for view in subviews { view.needsDisplay = true }
    }
}
