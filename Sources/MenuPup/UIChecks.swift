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
                for kind in PetKind.allCases {
                    choose("キャラクター", kind.title)
                    let frames = Pet.frames(for: kind)
                    check("character_\(kind.rawValue)_selected", app.preferences.petKind == kind &&
                          app.statusItem.button?.image?.accessibilityDescription == kind.title)
                    check("character_\(kind.rawValue)_persisted", Preferences(defaults: app.preferences.defaults).petKind == kind)
                    check("character_\(kind.rawValue)_four_frames", Set(frames.compactMap { $0.tiffRepresentation }).count == 4)
                    check("character_\(kind.rawValue)_checked", app.settingsMenu().item(withTitle: "キャラクター")?
                        .submenu?.item(withTitle: kind.title)?.state == .on)
                    try petPreview(kind)
                    await wait(0.1)
                    if let button = app.statusItem.button,
                       let bitmap = button.bitmapImageRepForCachingDisplay(in: button.bounds) {
                        button.effectiveAppearance.performAsCurrentDrawingAppearance {
                            button.cacheDisplay(in: button.bounds, to: bitmap)
                        }
                        try bitmap.representation(using: .png, properties: [:])?.write(
                            to: directory.appendingPathComponent("\(kind.assetName)-status.png"))
                    }
                    if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                        app.preferences.animation = true; app.preferences.displayMode = .pet; app.updateStatus()
                        let initial = app.frameIndex
                        await wait(1.1)
                        check("character_\(kind.rawValue)_animates", app.frameIndex > initial)
                    }
                }
                check("characters_have_distinct_shapes", Pet.frames(for: .lowRun)[0].size.width > Pet.frames(for: .classic)[0].size.width)
                choose("キャラクター", PetKind.classic.title)
                choose("テーマ", "Material")
                choose("外観", "ライト")
                await wait(0.3)
                check("settings_theme_and_light", app.preferences.theme == .material && !app.preferences.dark)
                try screenshot("material-collapsed.png")
                choose("テーマ", "Glass")
                choose("外観", "ダーク")
                check("settings_theme_and_dark", app.preferences.theme == .glass && app.preferences.dark)
                check("load_controls_pace", Pet.framesPerSecond(cpu: 0) == 2 && Pet.framesPerSecond(cpu: 1) == 10)
                if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                    app.preferences.animation = true; app.preferences.displayMode = .pet; app.updateStatus()
                    let initialFrame = app.frameIndex
                    await wait(1.1)
                    check("menu_bar_dog_animates", app.frameIndex > initialFrame)
                } else { check("reduce_motion_stops_animation", app.animationFPS == 0) }
                let collapsedTop = app.dashboard.window?.frame.maxY
                submit("printf '\\033[32mMENUPUP_OK\\033[0m\\n'; export MENUPUP_SESSION=present; cd /tmp; pwd")
                await wait(0.07)
                if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                    check("resize_has_intermediate_frame", app.dashboard.bounds.width > 256 && app.dashboard.bounds.width < 520)
                }
                await wait(2)
                check("expanded_width_520", abs(app.dashboard.bounds.width - 520) < 1)
                check("terminal_uses_expanded_width", app.dashboard.terminal.bounds.width > 500)
                if let frame = app.dashboard.window?.frame, let screen = app.dashboard.window?.screen {
                    check("expanded_window_on_screen", frame.minX >= screen.frame.minX && frame.maxX <= screen.frame.maxX)
                }
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
                check("reopen_compact_size", abs(app.dashboard.bounds.width - 256) < 1 && abs(app.dashboard.bounds.height - 302) < 1)
                check("reopen_collapsed", !app.dashboard.terminal.expanded && app.dashboard.terminal.input.stringValue.isEmpty)
                submit("printf 'FRESH:%s\\n' \"${MENUPUP_SESSION-unset}\"; pwd")
                let freshDeadline = ProcessInfo.processInfo.systemUptime + 4
                while app.dashboard.terminal.terminal?.transcript.contains("\r\nFRESH:unset\r\n") != true &&
                        ProcessInfo.processInfo.systemUptime < freshDeadline { await wait(0.05) }
                let fresh = app.dashboard.terminal.terminal
                try (fresh?.transcript ?? "NO TERMINAL").write(to: directory.appendingPathComponent("fresh-check.txt"), atomically: true, encoding: .utf8)
                check("fresh_shell", fresh?.process.shellPid != firstPID &&
                      fresh?.transcript.contains("\r\nFRESH:unset\r\n") == true)
                check("fresh_working_directory", fresh?.transcript.contains("\r\n\(FileManager.default.homeDirectoryForCurrentUser.path)\r\n") == true)
                app.popover.performClose(nil)
                await wait(0.8)
                app.statusItem.button?.performClick(nil)
                await wait(0.3)
                submit("printf 'LATE_COMMAND\\n'")
                let cancelledTerminal = app.dashboard.terminal.terminal
                await wait(0.04)
                app.popover.performClose(nil)
                await wait(0.6)
                check("close_cancels_initial_command", cancelledTerminal?.pendingCommand == nil &&
                      cancelledTerminal?.transcript.contains("\r\nLATE_COMMAND\r\n") == false)
                app.statusItem.button?.performClick(nil)
                await wait(0.3)
                check("close_during_resize_stays_compact", abs(app.dashboard.bounds.width - 256) < 1 &&
                      abs(app.dashboard.bounds.height - 302) < 1 && app.dashboard.terminal.terminal == nil)
                app.popover.performClose(nil)
                await wait(0.4)
                let item = NSMenuItem()
                item.tag = DisplayMode.monitor.rawValue; app.changeDisplay(item)
                check("monitor_mode", app.statusItem.button?.image?.size == MenuReadout.size && app.statusItem.button?.image?.accessibilityDescription?.contains("GPU") == true)
                item.tag = DisplayMode.petAndNumbers.rawValue; app.changeDisplay(item)
                check("combined_mode", (app.statusItem.button?.image?.size.width ?? 0) > MenuReadout.size.width && app.statusItem.button?.image?.accessibilityDescription?.contains("GPU") == true)
                try menuReadoutPreview()
                await wait(0.1)
                if let button = app.statusItem.button,
                   let bitmap = button.bitmapImageRepForCachingDisplay(in: button.bounds) {
                    button.effectiveAppearance.performAsCurrentDrawingAppearance {
                        button.cacheDisplay(in: button.bounds, to: bitmap)
                    }
                    try bitmap.representation(using: .png, properties: [:])?.write(
                        to: directory.appendingPathComponent("combined-status.png"))
                }
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
    @MainActor private func menuReadoutPreview() throws {
        let preview = NSImage(size: NSSize(width: 240, height: 120), flipped: false) { _ in
            for (index, dark) in [false, true].enumerated() {
                (dark ? NSColor(calibratedWhite: 0.1, alpha: 1) : .white).setFill()
                NSRect(x: 0, y: index * 60, width: 240, height: 60).fill()
                MenuReadout.image(snapshot: self.app.latest, dark: dark).draw(in:
                    NSRect(x: 10, y: index * 60 + 8, width: 228, height: 44))
            }
            return true
        }
        if let tiff = preview.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]) {
            try png.write(to: directory.appendingPathComponent("menu-readout.png"))
        }
        let unavailable = Snapshot()
        check("unavailable_metrics_are_dashes", MenuReadout.summary(unavailable).contains("GPU —"))
        check("readout_width_stays_fixed", MenuReadout.image(snapshot: unavailable, dark: false).size == MenuReadout.size)
    }
    @MainActor private func petPreview(_ kind: PetKind) throws {
        let frames = Pet.frames(for: kind)
        // Render the actual runtime frames at 1x and enlarged on both menu-bar appearances.
        let preview = NSImage(size: NSSize(width: 400, height: 180), flipped: false) { _ in
            for (row, background) in [NSColor(calibratedWhite: 0.12, alpha: 1), .white].enumerated() {
                background.setFill()
                NSRect(x: 0, y: row * 90, width: 400, height: 90).fill()
                for (index, frame) in frames.enumerated() {
                    NSGraphicsContext.current?.imageInterpolation = .none
                    frame.draw(in: NSRect(x: CGFloat(index * 100 + 5), y: CGFloat(row * 90 + 4),
                        width: frame.size.width, height: frame.size.height))
                    frame.draw(in: NSRect(x: CGFloat(index * 100 + 5), y: CGFloat(row * 90 + 29),
                        width: frame.size.width * 2, height: frame.size.height * 2))
                }
            }
            return true
        }
        if let tiff = preview.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]) {
            try png.write(to: directory.appendingPathComponent("\(kind.assetName)-preview.png"))
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
