import AppKit

enum Theme: String { case glass, material }
enum DisplayMode: Int { case pet, petAndNumbers, monitor }
enum ColorMode: Int { case automatic, light, dark }

final class Preferences {
    let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    var theme: Theme {
        get { Theme(rawValue: defaults.string(forKey: "theme") ?? "") ?? .glass }
        set { defaults.set(newValue.rawValue, forKey: "theme") }
    }
    var colorMode: ColorMode {
        get { ColorMode(rawValue: defaults.object(forKey: "colorMode") as? Int ?? 2) ?? .dark }
        set { defaults.set(newValue.rawValue, forKey: "colorMode") }
    }
    var displayMode: DisplayMode {
        get { DisplayMode(rawValue: defaults.integer(forKey: "displayMode")) ?? .pet }
        set { defaults.set(newValue.rawValue, forKey: "displayMode") }
    }
    var petKind: PetKind {
        get { PetKind(rawValue: defaults.string(forKey: "petKind") ?? "") ?? .classic }
        set { defaults.set(newValue.rawValue, forKey: "petKind") }
    }
    var animation: Bool {
        get { defaults.object(forKey: "animation") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "animation") }
    }
    var dark: Bool { NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
    func apply() {
        switch colorMode {
        case .automatic: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

extension NSColor {
    static let cpuTint = NSColor.systemBlue
    static let gpuTint = NSColor.systemPurple
    static let memoryTint = NSColor.systemOrange
}

func drawText(_ value: String, _ rect: NSRect, size: CGFloat = 11, color: NSColor = .labelColor,
              weight: NSFont.Weight = .regular, align: NSTextAlignment = .left, mono: Bool = false) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = align
    paragraph.lineBreakMode = .byTruncatingTail
    let font = mono ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
    (value as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
}

class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

final class Surface: FlippedView {
    var theme: Theme = .glass { didSet { needsDisplay = true } }
    var solidBackground = false { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: theme == .glass ? 8 : 4, yRadius: theme == .glass ? 8 : 4)
        let fill = solidBackground ? (dark ? NSColor(calibratedWhite: 0.12, alpha: 1) : .white) :
            (dark ? NSColor.white.withAlphaComponent(0.035) : NSColor.white.withAlphaComponent(0.7))
        fill.setFill()
        path.fill()
        NSColor.separatorColor.withAlphaComponent(theme == .glass ? 0.25 : 0.45).setStroke()
        path.lineWidth = 0.5
        path.stroke()
    }
}
