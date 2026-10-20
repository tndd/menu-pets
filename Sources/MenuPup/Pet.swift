import AppKit

enum Pet {
    // Annoying Dog (UNDERTALE / Toby Fox), redrawn for the menu bar.
    // White body, black face and outline stay legible on either menu-bar appearance.
    static func framesPerSecond(cpu: Double?) -> Double {
        2 + 8 * min(1, max(0, cpu ?? 0))
    }
    static let frames: [NSImage] = (0..<4).map { phase in
        var pixels = [
            "............w...w.....",
            "...........wwwwwww....",
            "..........wwwwwwwww...",
            "..........wwwwwwwww...",
            ".........wwwbwwwbwww..",
            "w.......wwwwwwwwwwww..",
            "ww....wwwwwwwwwwbbwww.",
            "wwwwwwwwwwwwwbwwwbww..",
            "wwwwwwwwwwwwwwbbbwww..",
            "wwwwwwwwwwwwwwwwwww...",
            "wwwwwwwwwwwwwwwwwww...",
            "wwwwwwwwwwwwwwwwwww...",
            ".wwwwwwwwwwwwwwwww....",
            "..wwwwwwwwwwwwwww.....",
            "..www.........www.....",
            "..ww...........ww....."
        ]
        let legs = [
            ["..www.........www.....", "..ww...........ww....."],
            [".www...........www....", ".ww.............ww...."],
            ["...www.......www......", "....ww.......ww......."],
            ["...wwww......wwww.....", "...ww..........ww....."]
        ]
        pixels[14] = legs[phase][0]; pixels[15] = legs[phase][1]
        let image = NSImage(size: NSSize(width: 26, height: 20), flipped: false) { _ in
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            NSGraphicsContext.current?.shouldAntialias = false
            let bob = phase % 2
            // One-pixel silhouette behind the white sprite.
            NSColor.black.setFill()
            for (y, row) in pixels.enumerated() {
                for (x, pixel) in row.enumerated() where pixel != "." {
                    NSRect(x: x + 1, y: 17 - y - bob, width: 3, height: 3).fill()
                }
            }
            for (y, row) in pixels.enumerated() {
                for (x, pixel) in row.enumerated() where pixel != "." {
                    (pixel == "b" ? NSColor.black : NSColor.white).setFill()
                    NSRect(x: x + 2, y: 18 - y - bob, width: 1, height: 1).fill()
                }
            }
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "Annoying Dog"
        return image
    }
}
