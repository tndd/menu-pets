import AppKit
import SwiftTerm
import CMetrics

final class SessionTerminal: LocalProcessTerminalView {
    // Bounded diagnostic transcript for local integration checks; never persisted in normal use.
    var transcript = ""
    var ended: (() -> Void)?
    var pendingCommand: String?
    static let readyMarker = "\u{1b}]133;A\u{7}"
    override func dataReceived(slice: ArraySlice<UInt8>) {
        transcript += String(decoding: slice, as: UTF8.self)
        if transcript.utf8.count > 32768 { transcript = String(transcript.suffix(16000)) }
        super.dataReceived(slice: slice)
        if transcript.contains(Self.readyMarker), let command = pendingCommand {
            pendingCommand = nil
            send(txt: command + "\r")
        }
    }
    override func processTerminated(_ source: LocalProcess, exitCode: Int32?) {
        super.processTerminated(source, exitCode: exitCode)
        ended?()
    }
}

final class TerminalPanel: FlippedView, NSTextFieldDelegate {
    let input = NSTextField()
    private let enter = NSButton()
    private(set) var terminal: SessionTerminal?
    var expandedChanged: ((Bool) -> Void)?
    private(set) var expanded = false
    var dark = true { didSet { applyColors() } }
    private var ending = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        input.placeholderString = "コマンドを入力…"
        input.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        input.isBordered = false; input.drawsBackground = false
        input.focusRingType = .none
        input.delegate = self
        input.target = self; input.action = #selector(submit)
        input.setAccessibilityLabel("一時ターミナルのコマンド")
        input.toolTip = "Enterで実行するとターミナルが展開します。閉じるとセッションを終了します。"
        addSubview(input)
        enter.image = NSImage(systemSymbolName: "return", accessibilityDescription: "コマンドを実行")
        enter.bezelStyle = .texturedRounded; enter.controlSize = .small
        enter.target = self; enter.action = #selector(submit)
        addSubview(enter)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        input.frame = NSRect(x: 29, y: 7, width: bounds.width - 63, height: 18)
        enter.frame = NSRect(x: bounds.width - 29, y: 3, width: 26, height: 25)
        terminal?.frame = bounds.insetBy(dx: 5, dy: 5)
    }
    override func draw(_ dirtyRect: NSRect) {
        if !expanded {
            drawText("›_", NSRect(x: 8, y: 6, width: 22, height: 18), size: 13, color: .secondaryLabelColor, mono: true)
        }
    }
    @objc func submit() {
        let command = input.stringValue
        guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, terminal == nil else { return }
        ending = false; expanded = true
        input.isHidden = true; enter.isHidden = true
        expandedChanged?(true)
        layoutSubtreeIfNeeded()
        let term = SessionTerminal(frame: bounds.insetBy(dx: 5, dy: 5))
        term.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        terminal = term
        addSubview(term)
        applyColors()
        term.ended = { [weak self, weak term] in
            guard let self, !self.ending, term === self.terminal else { return }
            DispatchQueue.main.async { self.reset() }
        }
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "xterm-256color"
        environment["LANG"] = environment["LANG"] ?? "ja_JP.UTF-8"
        environment["HISTFILE"] = "/dev/null"
        environment["HISTSIZE"] = "0"; environment["SAVEHIST"] = "0"
        environment["PS1"] = "%{" + SessionTerminal.readyMarker + "%}%~ %# "
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
        term.pendingCommand = command
        term.startProcess(executable: "/bin/zsh", args: ["-f", "-i"],
                          environment: environment.map { "\($0.key)=\($0.value)" },
                          currentDirectory: FileManager.default.homeDirectoryForCurrentUser.path)
        // Send only after zsh has produced its first prompt, avoiding a duplicate TTY echo.
        window?.makeFirstResponder(term)
        needsDisplay = true
    }
    func applyColors() {
        terminal?.nativeBackgroundColor = dark ? NSColor(calibratedWhite: 0.10, alpha: 1) : NSColor(calibratedWhite: 0.98, alpha: 1)
        terminal?.nativeForegroundColor = dark ? .white : .black
    }
    func reset(force: Bool = false) {
        ending = true
        if let term = terminal {
            term.ended = nil
            let pid = term.process.shellPid
            if term.process.running, pid > 1 {
                mp_signal_session(pid, SIGHUP)
                // A fresh session must not leave an interactive foreground job running.
                mp_signal_session(pid, SIGTERM)
                // This is a disposable terminal: stop even jobs that ignore HUP/TERM
                // while the owned session leader still prevents SID reuse.
                mp_signal_session(pid, SIGKILL)
                if force {
                    kill(pid, SIGKILL)
                    term.terminate()
                }
                let stillRunning = { term.process.running && term.process.shellPid == pid }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    if stillRunning() {
                        mp_signal_session(pid, SIGKILL)
                        // Direct child remains owned by SwiftTerm until reaped.
                        kill(pid, SIGKILL)
                        term.terminate()
                    }
                }
                kill(pid, SIGHUP)
            }
            term.removeFromSuperview()
        }
        terminal = nil; expanded = false
        input.stringValue = ""; input.isHidden = false; enter.isHidden = false
        expandedChanged?(false)
        needsDisplay = true
    }
}
