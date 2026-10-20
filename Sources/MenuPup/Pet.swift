import AppKit

enum Pet {
    // Annoying Dog (UNDERTALE / Toby Fox), redrawn for the menu bar.
    // White body, black face and outline stay legible on either menu-bar appearance.
    static func framesPerSecond(cpu: Double?) -> Double {
        2 + 8 * min(1, max(0, cpu ?? 0))
    }
    static let frames: [NSImage] = (0..<4).map { phase in
        // 16 × 12 logical pixels, 1.5pt each: larger eyes/nose than the old 22 × 16 sprite.
        var pixels = [
            ".w...w..........",
            ".wwwwww.........",
            "wwwwwwww........",
            "wwbwwbww........",
            "wwwwbwww........",
            "wwbwbwww......w.",
            "wwwbwwwwwwwwwww.",
            "wwwwwwwwwwwwwww.",
            "wwwwwwwwwwwwwww.",
            ".wwwwwwwwwwwww..",
            "..ww.......ww...",
            "..ww.......ww..."
        ]
        let legs = [
            ["..ww.......ww...", "..ww.......ww..."],
            [".ww.........ww..", ".ww..........ww."],
            ["...ww.....ww....", "....ww...ww....."],
            ["..www.....www...", "...ww......ww..."]
        ]
        pixels[10] = legs[phase][0]; pixels[11] = legs[phase][1]
        let image = NSImage(size: NSSize(width: 26, height: 22), flipped: false) { _ in
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            NSGraphicsContext.current?.shouldAntialias = false
            let bob = CGFloat(phase % 2) * 0.5
            let cell: CGFloat = 1.5
            // One-pixel silhouette behind the white sprite.
            NSColor.black.setFill()
            for (y, row) in pixels.enumerated() {
                for (x, pixel) in row.enumerated() where pixel != "." {
                    NSRect(x: CGFloat(x) * cell, y: 19 - CGFloat(y) * cell - bob - 1, width: cell + 2, height: cell + 2).fill()
                }
            }
            for (y, row) in pixels.enumerated() {
                for (x, pixel) in row.enumerated() where pixel != "." {
                    (pixel == "b" ? NSColor.black : NSColor.white).setFill()
                    NSRect(x: 1 + CGFloat(x) * cell, y: 19 - CGFloat(y) * cell - bob, width: cell, height: cell).fill()
                }
            }
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "Annoying Dog"
        return image
    }
}
