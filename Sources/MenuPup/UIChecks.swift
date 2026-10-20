import AppKit
import MonitorCore

/// Opt-in integration checks run through the real status-item/popover and PTY.
/// Outputs are local only; normal launches do not run or persist terminal checks.
final class UIChecks {
    unowned let app: AppController
    let directory: URL
    var results: [String: Bool] = [:]
    init(app: AppController, directory: URL) { self.app = app; self.directory = directory }
    func start() {
        Task { @MainActor in
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                await wait(1)
                app.statusItem.button?.performClick(nil)
                await wait(4)
                check("status_item_opens_popover", app.popover.isShown)
                check("compact_width_256", abs(app.dashboard.bounds.width - 256) < 1)
                check("collapsed_height_302", abs(app.dashboard.bounds.height - 302) < 1)
                check("cpu_live", app.latest.cpu.map { (0...1).contains($0) } ?? false)
                check("gpu_live", app.latest.gpu.map { (0...1).contains($0) } ?? false)
                check("memory_live", app.latest.memoryUsed > 0 && app.latest.memoryUsed <= app.latest.memoryTotal)
                check("battery_history_live", app.latest.battery == nil || !app.history.samples.isEmpty)
                app.preferences.theme = .glass; app.preferences.colorMode = .dark
                app.preferences.apply(); app.dashboard.applyTheme()
                await wait(0.3)
                try screenshot("glass-collapsed.png")
                let dog = NSImage(size: NSSize(width: 104, height: 20), flipped: false) { _ in
                    for (index, frame) in Pet.frames.enumerated() {
                        frame.draw(in: NSRect(x: index * 26, y: 0, width: 26, height: 20))
                    }
                    return true
                }
                if let tiff = dog.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
                   let png = bitmap.representation(using: .png, properties: [:]) {
                    try png.write(to: directory.appendingPathComponent("dog-frames.png"))
                }
                choose("テーマ", "Material")
                choose("外観", "ライト")
                await wait(0.3)
                check("settings_theme_and_light", app.preferences.theme == .material && !app.preferences.dark)
                try screenshot("material-collapsed.png")
                choose("テーマ", "Glass")
                choose("外観", "ダーク")
                check("settings_theme_and_dark", app.preferences.theme == .glass && app.preferences.dark)
                check("load_controls_pace", Pet.framesPerSecond(cpu: 0) == 2 && Pet.framesPerSecond(cpu: 1) == 10)
                check("four_distinct_dog_frames", Set(Pet.frames.compactMap { $0.tiffRepresentation }).count == 4)
                if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                    app.preferences.animation = true; app.preferences.displayMode = .pet; app.updateStatus()
                    let initialFrame = app.frameIndex
                    await wait(1 / app.animationFPS + 0.05)
                    check("menu_bar_dog_animates", app.frameIndex != initialFrame)
                } else { check("reduce_motion_stops_animation", app.animationFPS == 0) }
                let collapsedTop = app.dashboard.window?.frame.maxY
                submit("printf '\\033[32mMENUPUP_OK\\033[0m\\n'; export MENUPUP_SESSION=present; cd /tmp; pwd")
                await wait(2)
                check("terminal_expands_on_enter", app.dashboard.terminal.expanded && app.popover.contentSize.height > 302)
                check("terminal_expands_downward", abs((app.dashboard.window?.frame.maxY ?? 0) - (collapsedTop ?? 0)) < 2)
                let terminal = app.dashboard.terminal.terminal
                let firstPID = terminal?.process.shellPid ?? 0
                check("pty_started", firstPID > 1 && terminal?.process.running == true)
                check("shell_executes", terminal?.transcript.contains("MENUPUP_OK\u{1b}[0m") == true &&
                      terminal?.transcript.contains("\r\n/tmp\r\n") == true)
                terminal?.send(txt: "clear; uname -sm; pwd\r")
                await wait(0.3)
                try screenshot("glass-terminal.png")
                terminal?.send(txt: "sleep 30\r")
                await wait(0.4)
                if let term = terminal {
                    let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .control,
                        timestamp: 0, windowNumber: term.window?.windowNumber ?? 0, context: nil,
                        characters: "\u{3}", charactersIgnoringModifiers: "c", isARepeat: false, keyCode: 8)!
                    term.keyDown(with: event)
                    await wait(0.3)
                    term.send(txt: "printf 'INTERRUPT_OK\\n'\r")
                    await wait(0.5)
                    check("terminal_ctrl_c", term.transcript.contains("\r\nINTERRUPT_OK\r\n"))
                }
                terminal?.send(txt: "sleep 30 & printf 'CHILD:%s\\n' $!\r")
                await wait(0.5)
                let childPID = extractChildPID(terminal?.transcript ?? "")
                check("background_child_started", childPID > 1)
                app.statusItem.button?.performClick(nil)
                await wait(1)
                check("terminal_closed_session", !app.popover.isShown && app.dashboard.terminal.terminal == nil && kill(firstPID, 0) != 0)
                check("background_child_stopped", childPID > 1 && kill(childPID, 0) != 0)
                app.statusItem.button?.performClick(nil)
                await wait(0.4)
                check("reopen_collapsed", !app.dashboard.terminal.expanded && app.dashboard.terminal.input.stringValue.isEmpty)
                submit("printf 'FRESH:%s\\n' \"${MENUPUP_SESSION-unset}\"; pwd")
                await wait(1)
                let fresh = app.dashboard.terminal.terminal
                check("fresh_shell", fresh?.process.shellPid != firstPID &&
                      fresh?.transcript.contains("\r\nFRESH:unset\r\n") == true)
                check("fresh_working_directory", fresh?.transcript.contains("\r\n\(FileManager.default.homeDirectoryForCurrentUser.path)\r\n") == true)
                app.popover.performClose(nil)
                await wait(0.8)
                let item = NSMenuItem()
                item.tag = DisplayMode.monitor.rawValue; app.changeDisplay(item)
                check("monitor_mode", app.statusItem.button?.image == nil && app.statusItem.button?.title.contains(" G") == true)
                item.tag = DisplayMode.petAndNumbers.rawValue; app.changeDisplay(item)
                check("combined_mode", app.statusItem.button?.image != nil && app.statusItem.button?.title.contains(" C") == true)
                item.tag = DisplayMode.pet.rawValue; app.changeDisplay(item)
                check("pet_mode", app.statusItem.button?.image != nil && app.statusItem.button?.title == "")
                let success = results.values.allSatisfy { $0 }
                let data = try JSONSerialization.data(withJSONObject: ["passed": success, "checks": results], options: [.prettyPrinted, .sortedKeys])
                try data.write(to: directory.appendingPathComponent("ui-checks.json"), options: .atomic)
                print(String(decoding: data, as: UTF8.self))
                NSApp.terminate(nil)
            } catch {
                let message = "UI checks error: \(error)"
                try? message.write(to: directory.appendingPathComponent("error.txt"), atomically: true, encoding: .utf8)
                print(message)
                NSApp.terminate(nil)
            }
        }
    }
    @MainActor private func choose(_ group: String, _ title: String) {
        guard let item = app.settingsMenu().item(withTitle: group)?.submenu?.item(withTitle: title),
              let action = item.action else { check("settings_\(title)", false); return }
        NSApp.sendAction(action, to: item.target, from: item)
    }
    @MainActor private func submit(_ command: String) {
        let field = app.dashboard.terminal.input
        field.stringValue = command
        app.dashboard.window?.makeFirstResponder(field)
        NSApp.sendAction(field.action!, to: field.target, from: field)
    }
    private func check(_ name: String, _ success: Bool) { results[name] = success }
    private func wait(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
    private func extractChildPID(_ text: String) -> Int32 {
        let regex = try! NSRegularExpression(pattern: "\\r?\\nCHILD:([0-9]+)")
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.matches(in: text, range: range).last,
              let digits = Range(match.range(at: 1), in: text) else { return 0 }
        return Int32(text[digits]) ?? 0
    }
    @MainActor private func screenshot(_ name: String) throws {
        let view = app.dashboard
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        if let window = view.window,
           let capture = CGWindowListCreateImage(.null, .optionIncludingWindow,
               CGWindowID(window.windowNumber), [.boundsIgnoreFraming, .bestResolution]) {
            let bitmap = NSBitmapImageRep(cgImage: capture)
            if let data = bitmap.representation(using: .png, properties: [:]) {
                try data.write(to: directory.appendingPathComponent(name), options: .atomic)
                return
            }
        }
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw CheckError.capture }
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            view.cacheDisplay(in: view.bounds, to: bitmap)
        }
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw CheckError.capture }
        try data.write(to: directory.appendingPathComponent(name), options: .atomic)
    }
    enum CheckError: Error { case capture }
}
