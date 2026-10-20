import AppKit
import MonitorCore

final class AppController: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    let preferences: Preferences
    let dashboard: Dashboard
    let popover = NSPopover()
    private(set) var statusItem: NSStatusItem!
    private(set) var latest = Snapshot()
    let history: BatteryHistory
    private let sampler = Sampler()
    private let queue = DispatchQueue(label: "MenuPup.telemetry", qos: .utility)
    private var sampleTimer: Timer?
    private var petTimer: Timer?
    private var resizeTimer: Timer?
    private var appearanceObserver: NSKeyValueObservation?
    private var statusFrames: [NSImage] = []
    private(set) var frameIndex = 0
    private(set) var animationFPS: Double = 0
    private var samplePending = false
    private var active = true
    private var workspaceObservers: [NSObjectProtocol] = []
    let checkDirectory: URL?
    var checks: UIChecks?

    init(checkDirectory: URL? = nil) {
        self.checkDirectory = checkDirectory
        let defaults = checkDirectory == nil ? UserDefaults.standard : UserDefaults(suiteName: "MenuPup.UIChecks")!
        preferences = Preferences(defaults: defaults)
        let directory = checkDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MenuPup")
        history = BatteryHistory(url: directory.appendingPathComponent("battery.json"))
        dashboard = Dashboard(preferences: preferences)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        preferences.apply()
        installMainMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self; statusItem.button?.action = #selector(statusClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem.button?.imagePosition = .imageLeft
        statusItem.button?.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        statusItem.button?.setAccessibilityLabel("MenuPup システムモニター")
        appearanceObserver = statusItem.button?.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            self?.updateStatus()
        }
        popover.behavior = .transient
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.delegate = self
        let controller = NSViewController(); controller.view = dashboard
        popover.contentViewController = controller
        popover.contentSize = NSSize(width: Dashboard.width, height: Dashboard.collapsedHeight)
        dashboard.onResize = { [weak self] size in self?.resizePopover(to: size) }
        dashboard.onSettings = { [weak self] in self?.showSettings() }
        dashboard.applyTheme()
        updateStatus()
        startSampling()
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.active = false; self?.sampleTimer?.invalidate(); self?.petTimer?.invalidate()
        })
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.active = true; self?.startSampling()
        })
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.configureAnimation()
        })
        if let directory = checkDirectory {
            checks = UIChecks(app: self, directory: directory)
            checks?.start()
        }
    }

    private func resizePopover(to requestedSize: NSSize) {
        resizeTimer?.invalidate()
        resizeTimer = nil
        let visible = statusItem?.button?.window?.screen?.visibleFrame.size
        let target = NSSize(width: min(requestedSize.width, (visible?.width ?? 1000) - 32),
                            height: min(requestedSize.height, (visible?.height ?? 1000) - 32))
        let apply: (NSSize) -> Void = { [weak self] size in
            guard let self else { return }
            self.popover.contentSize = size
            self.dashboard.frame.size = size
            self.dashboard.needsLayout = true
            self.dashboard.layoutSubtreeIfNeeded()
        }
        guard popover.isShown, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            apply(target); dashboard.terminal.expansionDidFinish(); return
        }
        let initial = popover.contentSize
        guard initial != target else { apply(target); dashboard.terminal.expansionDidFinish(); return }
        let started = ProcessInfo.processInfo.systemUptime
        // Resize the native popover so AppKit retains its arrow and screen-edge placement.
        let timer = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let progress = min(1, (ProcessInfo.processInfo.systemUptime - started) / 0.18)
            let eased = 1 - pow(1 - progress, 3)
            apply(NSSize(width: initial.width + (target.width - initial.width) * eased,
                         height: initial.height + (target.height - initial.height) * eased))
            if progress >= 1 {
                timer.invalidate()
                self.resizeTimer = nil
                self.dashboard.terminal.expansionDidFinish()
            }
        }
        resizeTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); let app = NSMenu()
        app.addItem(withTitle: "MenuPupを終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = app; main.addItem(appItem)
        let editItem = NSMenuItem(); let edit = NSMenu(title: "編集")
        edit.addItem(withTitle: "取り消す", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "カット", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "コピー", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "ペースト", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "すべて選択", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit; main.addItem(editItem)
        NSApp.mainMenu = main
    }

    func startSampling() {
        sampleTimer?.invalidate()
        sampleTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
        sampleTimer?.tolerance = 0.2
        refresh()
    }
    func refresh() {
        guard active, !samplePending else { return }
        samplePending = true
        queue.async { [weak self] in
            guard let self else { return }
            let snapshot = self.sampler.sample()
            DispatchQueue.main.async {
                self.samplePending = false
                self.latest = snapshot
                if let battery = snapshot.battery {
                    self.history.record(BatterySample(date: snapshot.date, level: battery.level, charging: battery.charging))
                }
                if self.popover.isShown { self.dashboard.update(snapshot: snapshot, history: self.history) }
                self.updateStatus()
            }
        }
    }
    @objc func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp { showSettings(); return }
        if popover.isShown { popover.performClose(nil); return }
        guard let button = statusItem.button else { return }
        dashboard.terminal.reset()
        dashboard.applyTheme()
        dashboard.update(snapshot: latest, history: history)
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        dashboard.window?.makeKey()
        dashboard.window?.makeFirstResponder(dashboard.terminal.input)
        refresh()
    }
    func popoverWillClose(_ notification: Notification) {
        dashboard.terminal.reset()
    }
    func popoverDidClose(_ notification: Notification) {
        dashboard.terminal.reset()
    }
    func updateStatus() {
        let mode = preferences.displayMode
        let frames = Pet.frames(for: preferences.petKind)
        let dark = statusItem.button?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let metrics = MenuReadout.image(snapshot: latest, dark: dark)
        switch mode {
        case .pet: statusFrames = frames
        case .petAndNumbers: statusFrames = frames.map { MenuReadout.combined(pet: $0, metrics: metrics) }
        case .monitor: statusFrames = [metrics]
        }
        statusItem.button?.image = statusFrames[frameIndex % statusFrames.count]
        statusItem.button?.title = ""
        let summary = MenuReadout.summary(latest)
        statusItem.button?.toolTip = "MenuPup · \(summary)\nクリックで表示、右クリックで設定"
        statusItem.button?.setAccessibilityLabel("MenuPup · " + summary)
        configureAnimation()
    }
    private func configureAnimation() {
        petTimer?.invalidate()
        animationFPS = 0
        guard active, preferences.animation, preferences.displayMode != .monitor,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let fps = Pet.framesPerSecond(cpu: latest.cpu)
        animationFPS = fps
        petTimer = Timer.scheduledTimer(withTimeInterval: 1 / fps, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.frameIndex += 1
            guard !self.statusFrames.isEmpty else { return }
            self.statusItem.button?.image = self.statusFrames[self.frameIndex % self.statusFrames.count]
        }
        petTimer?.tolerance = 0.03
    }
    func settingsMenu() -> NSMenu {
        let menu = NSMenu()
        for (index, title) in ["ペット", "ペット＋数値", "数値のみ"].enumerated() {
            let item = menu.addItem(withTitle: title, action: #selector(changeDisplay(_:)), keyEquivalent: "")
            item.target = self; item.tag = index; item.state = preferences.displayMode.rawValue == index ? .on : .off
        }
        menu.addItem(.separator())
        let characters = NSMenu(title: "キャラクター")
        for kind in PetKind.allCases {
            let item = characters.addItem(withTitle: kind.title, action: #selector(changePet(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = kind.rawValue
            item.image = Pet.frames(for: kind).first
            item.state = preferences.petKind == kind ? .on : .off
        }
        let charactersItem = menu.addItem(withTitle: "キャラクター", action: nil, keyEquivalent: "")
        charactersItem.submenu = characters
        let animation = menu.addItem(withTitle: "犬のアニメーション", action: #selector(toggleAnimation), keyEquivalent: "")
        animation.target = self; animation.state = preferences.animation ? .on : .off
        let themes = NSMenu(title: "テーマ")
        for (index, title) in ["Glass", "Material"].enumerated() {
            let item = themes.addItem(withTitle: title, action: #selector(changeTheme(_:)), keyEquivalent: "")
            item.target = self; item.tag = index
            item.state = (preferences.theme == .glass ? 0 : 1) == index ? .on : .off
        }
        let themeItem = menu.addItem(withTitle: "テーマ", action: nil, keyEquivalent: "")
        themeItem.submenu = themes
        let appearances = NSMenu(title: "外観")
        for (index, title) in ["システム", "ライト", "ダーク"].enumerated() {
            let item = appearances.addItem(withTitle: title, action: #selector(changeAppearance(_:)), keyEquivalent: "")
            item.target = self; item.tag = index
            item.state = preferences.colorMode.rawValue == index ? .on : .off
        }
        let appearanceItem = menu.addItem(withTitle: "外観", action: nil, keyEquivalent: "")
        appearanceItem.submenu = appearances
        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: "MenuPupを終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        return menu
    }
    func showSettings() {
        let menu = settingsMenu()
        if popover.isShown {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: dashboard.settingsButton.bounds.maxY), in: dashboard.settingsButton)
        } else if let button = statusItem.button {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY), in: button)
        }
    }
    @objc func changeDisplay(_ sender: NSMenuItem) {
        preferences.displayMode = DisplayMode(rawValue: sender.tag) ?? .pet
        updateStatus()
    }
    @objc func changePet(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let kind = PetKind(rawValue: raw) else { return }
        preferences.petKind = kind
        frameIndex = 0
        updateStatus()
    }
    @objc private func toggleAnimation() { preferences.animation.toggle(); updateStatus() }
    @objc func changeTheme(_ sender: NSMenuItem) {
        preferences.theme = sender.tag == 0 ? .glass : .material
        dashboard.applyTheme()
    }
    @objc func changeAppearance(_ sender: NSMenuItem) {
        preferences.colorMode = ColorMode(rawValue: sender.tag) ?? .automatic
        preferences.apply(); dashboard.applyTheme()
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        dashboard.terminal.reset(force: true)
        return .terminateNow
    }
    func applicationWillTerminate(_ notification: Notification) {
        active = false
        sampleTimer?.invalidate(); petTimer?.invalidate(); resizeTimer?.invalidate()
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
    }
}
