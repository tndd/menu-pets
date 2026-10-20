import AppKit
import ImageIO

enum PetKind: String, CaseIterable {
    case classic, lowRun
    var title: String { self == .classic ? "A · Classic（ずんぐり）" : "B · Low Run（横長）" }
    var assetName: String { self == .classic ? "a-classic" : "b-low-run" }
}

enum Pet {
    static func framesPerSecond(cpu: Double?) -> Double {
        2 + 8 * min(1, max(0, cpu ?? 0))
    }
    private static let cached = Dictionary(uniqueKeysWithValues: PetKind.allCases.map { ($0, load($0)) })
    static func frames(for kind: PetKind) -> [NSImage] { cached[kind]! }

    private static func load(_ kind: PetKind) -> [NSImage] {
        // SwiftPM's generated accessor misses Contents/Resources in packaged apps.
        let bundle = Bundle.main.url(forResource: "MenuPup_MenuPup", withExtension: "bundle")
            .flatMap { Bundle(url: $0) } ?? Bundle.module
        guard let url = bundle.url(forResource: kind.assetName, withExtension: "png", subdirectory: "Pets"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let atlas = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            preconditionFailure("Missing bundled pet: \(kind.assetName)")
        }
        let width = atlas.width / 2, height = atlas.height / 2
        var tiles: [CGImage] = []
        var occupied: [CGRect] = []
        for frame in 0..<4 {
            let rect = CGRect(x: (frame % 2) * width, y: (frame / 2) * height, width: width, height: height)
            guard let tile = atlas.cropping(to: rect),
                  let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else {
                preconditionFailure("Invalid pet atlas")
            }
            context.draw(tile, in: CGRect(x: 0, y: 0, width: width, height: height))
            guard let bytes = context.data?.assumingMemoryBound(to: UInt8.self), let normalized = context.makeImage() else {
                preconditionFailure("Invalid pet pixels")
            }
            var minX = width, minY = height, maxX = 0, maxY = 0
            for y in 0..<height {
                for x in 0..<width where bytes[(y * width + x) * 4 + 3] > 127 {
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
            precondition(minX <= maxX && minY <= maxY, "Empty pet frame")
            occupied.append(CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
                .insetBy(dx: -2, dy: -2).intersection(CGRect(x: 0, y: 0, width: width, height: height)))
            tiles.append(normalized)
        }
        // Remove atlas padding per frame, then share a scale and ground baseline.
        // This prevents generated cell margins from making the dog jump between frames.
        let scale = 20 / occupied.map(\.height).max()!
        let bodyWidth = ceil(occupied.map(\.width).max()! * scale)
        return zip(tiles, occupied).map { tile, crop in
            let sprite = NSImage(cgImage: tile.cropping(to: crop)!, size: .zero)
            let target = NSRect(x: 1 + (bodyWidth - crop.width * scale) / 2, y: 1,
                                width: crop.width * scale, height: crop.height * scale)
            let image = NSImage(size: NSSize(width: bodyWidth + 2, height: 22), flipped: false) { _ in
                NSGraphicsContext.saveGraphicsState()
                defer { NSGraphicsContext.restoreGraphicsState() }
                NSGraphicsContext.current?.imageInterpolation = .none
                sprite.draw(in: target)
                return true
            }
            image.isTemplate = false
            image.accessibilityDescription = kind.title
            return image
        }
    }
}
